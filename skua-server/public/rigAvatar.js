// Requires window.RufflePlayer.config to be set (autoplay:'on' etc, same as
// index.html/calibrate.html) BEFORE ruffle.js loads, on any page that
// includes this file — otherwise Ruffle shows a "click to play" splash and
// every capture below hangs until its timeout.
//
// Wrapped in an IIFE so its internal consts (CHROMA_THRESHOLD, RENDER_SCALE,
// etc — names generic enough that a host page defines its own copies) stay
// out of the global scope; only window.RigAvatar is exposed.
(function() {
//
// Real nested DOM hierarchy for the match-detail win/lose avatar rig —
// replaces animating mcSkel's flat sibling parts directly in AS3 (where
// keeping a downstream part attached to its rotating parent required
// guessing pivot points; the arm/shoulder joint never looked right no
// matter what we tried). Here, each part is a genuine parent-child DOM
// node, so a CSS `rotate()` on a parent always carries its children
// correctly — the disconnection bug is structurally impossible.
//
// All positions below come from a one-time calibration pass (calibrate.html
// isolates each mcSkel part, one at a time, behind FFDec/new_Game.as's
// isolatePart/calibrate flashvars) against a reference character (Artix).
// The rig's *skeleton* (where each joint is) is a constant shared by every
// player — only the art plugged into each slot differs by equipped gear.

// Crop rectangles: each part's bounding box within the rig's 960x550 stage,
// measured from an isolated capture, diffed against a "nothing visible"
// baseline (this stage has real scenic background art, not a flat color,
// so a corner-sampled color guess doesn't work here — a baseline diff does).
const RIG_PART_CROPS = {
  head:          { x: 152, y: 186, w: 27, h: 25 },
  chest:         { x: 141, y: 194, w: 49, h: 52 },
  hip:           { x: 154, y: 231, w: 19, h: 19 },
  frontshoulder: { x: 128, y: 189, w: 30, h: 47 },
  backshoulder:  { x: 163, y: 194, w: 28, h: 42 },
  fronthand:     { x: 131, y: 225, w: 23, h: 33 },
  backhand:      { x: 166, y: 229, w: 24, h: 28 },
  frontthigh:    { x: 146, y: 238, w: 19, h: 28 },
  backthigh:     { x: 162, y: 238, w: 18, h: 31 },
  frontshin:     { x: 130, y: 256, w: 31, h: 55 },
  backshin:      { x: 163, y: 256, w: 32, h: 54 },
  idlefoot:      { x: 129, y: 288, w: 24, h: 32 },
  backfoot:      { x: 170, y: 286, w: 33, h: 28 },
};

// Rotation pivots, in the same stage coordinate space as the crops above.
// hip/backshoulder/backthigh/backshin/backfoot didn't register a marker
// during calibration (lower priority than the crop-rectangle fix, since
// the extraction itself needed that working first) — hip reuses
// frontthigh's own pivot (already proven correct: that's exactly why
// rotating frontthigh around its own origin looked right in the old AS3
// leg-kick — it IS the hip joint), and the other four use each one's front
// counterpart's PROPORTIONAL pivot position within its own crop box (e.g.
// frontshin's pivot sits at 24% down its box, not 50%) applied to the
// back-side crop — a crude "center of the box" guess was visibly wrong
// (backshin/backfoot's true pivot sits much higher in the box than center,
// since it's near the ankle/knee, not the middle of the limb), causing
// visible splitting once those joints actually rotated during the win emote.
const RIG_JOINTS = {
  head:          { x: 167, y: 199 },
  chest:         { x: 162, y: 223 },
  hip:           { x: 155, y: 251 }, // = frontthigh's own (known-good) pivot
  frontshoulder: { x: 149, y: 218 },
  backshoulder:  { x: 183, y: 220 }, // estimate: frontshoulder's proportional pivot applied to backshoulder's crop
  fronthand:     { x: 143, y: 238 },
  backhand:      { x: 177, y: 239 },
  frontthigh:    { x: 155, y: 251 },
  backthigh:     { x: 171, y: 252 }, // estimate: frontthigh's proportional pivot applied to backthigh's crop
  frontshin:     { x: 145, y: 269 },
  backshin:      { x: 179, y: 269 }, // estimate: frontshin's proportional pivot applied to backshin's crop
  idlefoot:      { x: 135, y: 294 },
  backfoot:      { x: 178, y: 291 }, // estimate: idlefoot's proportional pivot applied to backfoot's crop
};

// True parent-child structure (this is the whole point of the rebuild).
const PARENT_OF = {
  chest: null,
  head: 'chest',
  hip: 'chest',
  frontshoulder: 'chest',
  backshoulder: 'chest',
  fronthand: 'frontshoulder',
  backhand: 'backshoulder',
  frontthigh: 'hip',
  backthigh: 'hip',
  frontshin: 'frontthigh',
  backshin: 'backthigh',
  idlefoot: 'frontshin',
  backfoot: 'backshin',
};

// Standard 2D layering convention for this kind of rig: "back" parts render
// behind the torso, "front" parts in front, head on top of everything.
// Refine visually once the static reconstruction is checked against the
// original capture.
const Z_INDEX = {
  backshoulder: 1, backhand: 1, backthigh: 1, backshin: 1, backfoot: 1,
  chest: 2, hip: 2,
  frontshoulder: 3, fronthand: 3, frontthigh: 3, frontshin: 3, idlefoot: 3,
  head: 4,
};

// 1.5x the original 960x550 — must stay in sync with new_Game.as's backdrop
// drawRect. Oversized cosmetics (huge wings, weapons, pets) were getting
// hard-clipped at the old stage edge; the extra room is free for normal
// characters since every crop below is alpha-bounding-box driven, not
// stage-size driven.
const RIG_STAGE_W = 1440, RIG_STAGE_H = 825;
// A `head` crop is only 27x25 *pixels* at native 1x — anti-aliasing fringe
// at the chroma-key edge is proportionally huge at that resolution. The
// production renderer (index.html) supersamples 4-7x before scaling down
// for exactly this reason; this was rendering at flat 1x, which is the
// real cause of the persistent blue outline no amount of threshold/erosion
// tuning fully fixed.
// Was 3 — dropped to 2 after the 1.5x stage-size increase above made the
// animated (48-frame, dual-key) capture path unusably slow on detailed
// characters: 2.25x more pixels per frame (1.5 squared) pushed a render
// that took 13.8s at the old stage size to still not finish after 3+
// minutes at the new one, almost certainly GC/memory pressure from the
// per-frame ImageData allocations, not just proportionally-more work. 2x
// keeps the same absolute pixel count as the OLD 3x-at-960x550 setup
// (1440*2 = 2880, same as 960*3), so this should restore the old
// performance envelope while keeping the extra stage headroom. Slightly
// softer anti-aliasing on small crops (like the head-only closeups
// mentioned above) is the tradeoff.
const RENDER_SCALE = 2;
// Must match new_Game.as's hardcoded `this.rig.x` — the character rig's
// stage position is a fixed constant, not something we can query back from
// the SWF, so it's mirrored here for the render pages to use when they need
// to find the character specifically (e.g. centering the name over the head
// without a pet, positioned elsewhere, throwing it off). Was 240; bumped to
// 400 for real left-side headroom after a wide cape (Ryuu's "Shadow of the
// Dragon") got hard-clipped by the stage's own left edge at 240.
const RIG_CENTER_X = 400;
const BEACON_RECT = { x: 0, y: 0, w: 24, h: 24 }; // native stage units — scaled by RENDER_SCALE where used below
// Was green (0,255,0) — moved to orange since green is now also a valid
// backdrop color (bgColorOverride, for dual-key matting); must match
// new_Game.as's readyBeacon fill exactly.
const BEACON_COLOR = [255, 165, 0];

function colorDist(r,g,b, cr,cg,cb) {
  return Math.sqrt((r-cr)**2 + (g-cg)**2 + (b-cb)**2);
}
function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

// Earlier approach (kept only in history/memory, not code): a distinct-
// colored marker Shape drawn ON the character at the head's true position.
// Abandoned — dual-key capture composites whatever's actually topmost at
// each pixel, so an opaque marker occludes whatever real content would
// otherwise be there; that content is never actually captured, so clearing
// the marker afterward can't recover it, leaving a genuine hole (confirmed
// on Ryuu: the marker overlapped his cape's own solid shape, and clearing
// it punched a visible hole through the cape's silhouette no matter how
// precisely the marker's color was matched).
//
// Current approach: new_Game.as's positionHeadInfoBeacons() encodes the
// head's true X/Y (from the rig's own object hierarchy, immune to a tall
// cosmetic like a cape or glowing helm — see the AS3 comment for why
// pixel-alpha scanning alone can't tell those apart from the head) as plain
// RGB values in two small swatches living in the SAME reserved corner the
// ready beacon already occupies — space that's always blank and already
// gets wiped before any bounding-box scan, so nothing is ever drawn on the
// character at all. R = high byte, G = low byte, giving 16-bit precision
// per axis (the stage doesn't come close to needing that much). Values are
// in NATIVE stage units, matching AS3 Rectangle coordinates — scale by
// RENDER_SCALE to land on the supersampled capture canvas.
// Positions here MUST match new_Game.as's positionHeadInfoBeacons() exactly.
const HEAD_X_BEACON_CENTER = { x: 26 + 5, y: 0 + 5 };
const HEAD_Y_BEACON_CENTER = { x: 38 + 5, y: 0 + 5 };
function readHeadInfoBeacons(data, w, h) {
  function sample(nativeCx, nativeCy) {
    const cx = Math.round(nativeCx * RENDER_SCALE);
    const cy = Math.round(nativeCy * RENDER_SCALE);
    if (cx < 0 || cy < 0 || cx >= w || cy >= h) return null;
    const i = (cy * w + cx) * 4;
    if (data[i + 3] < 200) return null;
    return (data[i] << 8) | data[i + 1];
  }
  const xNative = sample(HEAD_X_BEACON_CENTER.x, HEAD_X_BEACON_CENTER.y);
  const yNative = sample(HEAD_Y_BEACON_CENTER.x, HEAD_Y_BEACON_CENTER.y);
  if (xNative == null || yNative == null) return null;
  return { x: xNative * RENDER_SCALE, y: yNative * RENDER_SCALE };
}

// `scale` (default 1) sizes the player element to `scale`x the normal
// RENDER_SCALE resolution — see CAPTURE_SUPERSAMPLE below for why. Ruffle
// renders to fill whatever CSS box its player element occupies, so a
// bigger element genuinely gets Ruffle to rasterize with more real
// anti-aliased detail (not synthetic upsampling of already-captured
// pixels) — same principle the RENDER_SCALE comment above already
// describes for head-crop supersampling, just made reusable/parametric
// instead of baked into the one fixed RENDER_SCALE value.
function createOffscreenPlayer(scale = 1) {
  const w = RIG_STAGE_W * RENDER_SCALE * scale, h = RIG_STAGE_H * RENDER_SCALE * scale;
  const stage = document.createElement('div');
  stage.style.cssText = `position:absolute;left:-9999px;top:0;width:${w}px;height:${h}px`;
  document.body.appendChild(stage);
  const ruffle = window.RufflePlayer.newest();
  const player = ruffle.createPlayer();
  player.style.width = w + 'px';
  player.style.height = h + 'px';
  stage.appendChild(player);
  return { stage, player };
}

function destroyOffscreenPlayer(stage, player) {
  try { player.remove(); } catch {}
  try { document.body.removeChild(stage); } catch {}
}

// Loads the given flashvars into an EXISTING player (reload, not a fresh
// instance) and polls the readyBeacon rather than guessing a delay. Captures
// at RENDER_SCALE x the native stage size for crisper per-part slices.
function loadAndCapture(player, flashvars, extra) {
  return new Promise(async (resolve) => {
    player.load({
      // Absolute URL, not relative: Ruffle's own relative-load resolution
      // for stuff the movie loads afterward (hair/cape/weapon/etc.) was
      // dropping the port off a relative-loaded movie's base, sending those
      // follow-up requests to the default port instead of ours.
      url: location.origin + '/api/avatarrigswf',
      parameters: { ...flashvars, matchResult: '', isolatePart: '', calibrate: '', ...extra },
      allowScriptAccess: 'always',
      backgroundColor: null,
      quality: 'best',
    });

    const w = RIG_STAGE_W * RENDER_SCALE, h = RIG_STAGE_H * RENDER_SCALE;
    const canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    const beaconCx = (BEACON_RECT.x + BEACON_RECT.w / 2) * RENDER_SCALE;
    const beaconCy = (BEACON_RECT.y + BEACON_RECT.h / 2) * RENDER_SCALE;

    let ready = false;
    const deadline = Date.now() + 25000;
    while (!ready && Date.now() < deadline) {
      const src = player.shadowRoot?.querySelector('canvas') || player.querySelector('canvas');
      if (src) {
        try {
          ctx.clearRect(0, 0, w, h);
          ctx.drawImage(src, 0, 0, w, h);
          const px = ctx.getImageData(beaconCx, beaconCy, 1, 1).data;
          ready = colorDist(px[0], px[1], px[2], ...BEACON_COLOR) < 40;
        } catch (e) { /* keep polling */ }
      }
      if (!ready) await sleep(150);
    }
    resolve({ canvas, ready });
  });
}

// Same load+poll as loadAndCapture, but deliberately does NOT capture a
// snapshot when ready fires — used by the dual-key path below, where two
// independent players each become "ready" at a different wall-clock moment
// (each one's own gear/sub-asset network fetch finishes at its own pace).
// loadAndCapture snapshotting the instant ITS OWN poll succeeds is exactly
// what broke dual-key matting at first: a weapon's shine/glow loop keeps
// playing in real time regardless of network timing, so capturing pass A
// and pass B at two different moments caught two different phases of that
// same animation — averaging two different phases of a moving highlight
// produced the wrong (pink-tinted) color the user reported, not just at
// the edges but wherever that highlight happened to be. Splitting "wait
// until ready" from "take the snapshot" lets both passes be told to load,
// waited on independently, and ONLY THEN snapshotted back-to-back in the
// same tick — by which point both SWFs' own animation clocks (which start
// when each begins executing, not when its assets finish fetching) have
// been running for effectively the same real time regardless of which one
// happened to report "ready" first.
function waitUntilReady(player, flashvars, extra) {
  return new Promise(async (resolve) => {
    player.load({
      url: location.origin + '/api/avatarrigswf',
      parameters: { ...flashvars, matchResult: '', isolatePart: '', calibrate: '', ...extra },
      allowScriptAccess: 'always',
      backgroundColor: null,
      quality: 'best',
    });

    const w = RIG_STAGE_W * RENDER_SCALE, h = RIG_STAGE_H * RENDER_SCALE;
    const probeCanvas = document.createElement('canvas');
    probeCanvas.width = w;
    probeCanvas.height = h;
    const probeCtx = probeCanvas.getContext('2d', { willReadFrequently: true });
    const beaconCx = (BEACON_RECT.x + BEACON_RECT.w / 2) * RENDER_SCALE;
    const beaconCy = (BEACON_RECT.y + BEACON_RECT.h / 2) * RENDER_SCALE;

    let ready = false;
    const deadline = Date.now() + 25000;
    while (!ready && Date.now() < deadline) {
      const src = player.shadowRoot?.querySelector('canvas') || player.querySelector('canvas');
      if (src) {
        try {
          probeCtx.clearRect(0, 0, w, h);
          probeCtx.drawImage(src, 0, 0, w, h);
          const px = probeCtx.getImageData(beaconCx, beaconCy, 1, 1).data;
          ready = colorDist(px[0], px[1], px[2], ...BEACON_COLOR) < 40;
        } catch (e) { /* keep polling */ }
      }
      if (!ready) await sleep(150);
    }
    resolve(ready);
  });
}

// Draws whatever the player is showing RIGHT NOW into a fresh canvas — no
// waiting, no polling. Paired with waitUntilReady so two players can be
// snapshotted back-to-back with (as close as JS allows) zero time gap.
function snapshotPlayer(player, w, h) {
  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  const src = player.shadowRoot?.querySelector('canvas') || player.querySelector('canvas');
  if (src) ctx.drawImage(src, 0, 0, w, h);
  return canvas;
}

// One-shot capture of the whole character at rest (Idle, no emote). Three
// masking approaches were tried before this one: corner-sampled flat-color
// guess (failed — this stage's original backdrop had real scenic art, not
// a flat color), and baseline-diff between two separate captures at two
// thresholds (failed both directions — two separate player instances
// rendering the "same" static frame differ by enough rasterization noise
// that no single color-distance threshold worked, and the backdrop wasn't
// even guaranteed static since something in it animated independently of
// our stop()). The actual fix: new_Game.as now paints its own solid cyan
// backdrop (0x00FFFF) behind everything, so there's nothing left to guess —
// just a flat, deterministic, known chroma-key color. One capture, no
// baseline needed.
// Was [0,255,255] (cyan) — switched to magenta after confirming a real
// collision on the "Prime Bank Pet"'s dark energy aura, which is itself a
// genuinely teal/cyan-toned glow effect (verified by sampling its raw
// un-keyed pixels: R sat at exactly 0 across its whole fade, meaning the
// true art color shares cyan's hue family). Cyan and magenta/teal-ish
// effects turn out to be common enough in AQW's "dark energy" aesthetic
// that keying on cyan silently ate into that pet's own art. Magenta is
// far rarer in actual character/effect color palettes. Must match
// new_Game.as's backdrop fill exactly (now 0xFF00FF).
// NOTE: For the dual-key path, we use neutral gray backdrops instead of
// chromatic ones to avoid the weapon-glow corruption issue (see CHROMA_KEY_A/B).
// The single-key chroma key below is only used by the static render path.
const CHROMA_KEY = [100, 100, 100]; // dark gray — matches default backdrop in new_Game.as (used by single-key static render path)
const CHROMA_THRESHOLD = 100; // 60 still left a visible fringe, especially around the small head crop — pushed looser

// Exact same per-pixel math that was validated against the "quality is
// perfect, don't touch it" bar — only pulled out into its own function
// (unchanged) so the animated multi-frame capture below can apply it once
// per frame without duplicating it inline. Mutates img.data in place.
//
// A pixel can pass a binary chroma check (not close enough to pure key
// color to count as "background") and still be a character-edge/backdrop
// BLEND — anti-aliasing always leaves a thin ring of these right at the
// silhouette. The old fix eroded the background outward by a fixed
// pixel radius to eat that fringe, but a fixed erosion radius eats
// clean through anything narrower than 2x that radius — hair strands,
// weapon tips, thin straps all got fully deleted, not just fringed
// (visible as a bald head with one eye and no hair at all once sliced).
//
// A plain RGB-distance-to-key alpha ramp (tried first) doesn't work
// either: different TRUE character colors sit at wildly different raw
// distances from the key color (gray armor is "far", dark brown hair
// is much "closer" even at full opacity), so a single global distance
// threshold can't treat every color consistently — hair kept getting
// partial alpha (and a visible fringe) even where it was 100% opaque.
//
// Real chroma-key software instead measures key-color EXCESS: for a
// magenta (255,0,255) key, that's how much the red/blue channels exceed
// green, since pure magenta is the extreme case of that and most real
// character colors (skin, armor, hair, gold trim, red cape) aren't
// anywhere near it. This tracks the actual blend fraction directly,
// independent of the true color's own baseline distance from the key.
function applyChromaKeyMask(img) {
  const d = img.data;
  const [bgR, bgG, bgB] = CHROMA_KEY;
  // For gray backdrops, measure Euclidean distance from the backdrop color.
  // Pixels identical to gray (including pure black and white) have distance
  // equal to their offset from the backdrop — this gives a perceptually
  // uniform ramp that works for any gray value. Pure backdrop pixels have
  // distance 0 (alpha 0 = transparent); pixels far from gray have high
  // distance (alpha ~1 = opaque).
  const EXCESS_MAX = 255 * Math.sqrt(3); // distance from (100,100,100) to (255,255,255) ≈ 268.7, sqrt(3)*255 is the theoretical max
  for (let p = 0; p < d.length / 4; p++) {
    const i = p * 4;
    const excess = Math.sqrt((d[i]   - bgR) ** 2 + (d[i+1] - bgG) ** 2 + (d[i+2] - bgB) ** 2);
    const alpha = 1 - Math.max(0, Math.min(1, excess / EXCESS_MAX));

    // De-spill: a partially-transparent edge pixel's rendered color is
    // itself alpha-blended with the cyan backdrop (pixel = alpha*trueColor
    // + (1-alpha)*bg) — just lowering alpha and keeping that color leaves
    // a visible cyan tint/fringe at every edge. Unmix using the known
    // background color to recover the true underlying color, so edges
    // fade out to transparent without carrying a cyan tinge with them.
    if (alpha > 0.02) {
      d[i]     = Math.max(0, Math.min(255, Math.round((d[i]   - (1 - alpha) * bgR) / alpha)));
      d[i + 1] = Math.max(0, Math.min(255, Math.round((d[i+1] - (1 - alpha) * bgG) / alpha)));
      d[i + 2] = Math.max(0, Math.min(255, Math.round((d[i+2] - (1 - alpha) * bgB) / alpha)));
    }
    d[i + 3] = Math.round(d[i + 3] * alpha);
  }
}

async function captureFullBody(flashvars) {
  const { stage, player } = createOffscreenPlayer();
  try {
    const { canvas: full, ready } = await loadAndCapture(player, flashvars, {});

    const ctx = full.getContext('2d', { willReadFrequently: true });
    const w = full.width, h = full.height;
    const img = ctx.getImageData(0, 0, w, h);
    applyChromaKeyMask(img);
    ctx.putImageData(img, 0, 0);

    return { canvas: full, ready };
  } finally {
    destroyOffscreenPlayer(stage, player);
  }
}

// Multi-frame capture for effects that are baked into a gear item's own SWF
// timeline (e.g. a weapon's native shine/glow loop) rather than anything we
// animate ourselves — no rig-slicing, no DOM joint puppeteering (that's what
// previously looked "off" and was dropped). The player loads ONCE and is
// left running after the ready-beacon fires (Ruffle autoplays nested
// MovieClips on their own timelines by default), and we just sample its
// canvas at intervals, masking each sample with the exact same
// applyChromaKeyMask used above.
async function captureAnimatedFrames(flashvars, { frameCount = 20, intervalMs = 100 } = {}) {
  const { stage, player } = createOffscreenPlayer();
  try {
    const { canvas: full, ready } = await loadAndCapture(player, flashvars, {});
    if (!ready) return { frames: [], ready };

    const w = full.width, h = full.height;
    const src = player.shadowRoot?.querySelector('canvas') || player.querySelector('canvas');
    const frames = [];
    const sampleCtx = document.createElement('canvas').getContext('2d', { willReadFrequently: true });
    sampleCtx.canvas.width = w;
    sampleCtx.canvas.height = h;

    for (let f = 0; f < frameCount; f++) {
      sampleCtx.clearRect(0, 0, w, h);
      sampleCtx.drawImage(src, 0, 0, w, h);
      const img = sampleCtx.getImageData(0, 0, w, h);
      applyChromaKeyMask(img);
      frames.push(img);
      if (f < frameCount - 1) await sleep(intervalMs);
    }

    return { frames, width: w, height: h, ready };
  } finally {
    destroyOffscreenPlayer(stage, player);
  }
}

// Two-backdrop ("triangulation") difference matting — the real fix for the
// single-key chroma problem above: ANY flat key color will collide with
// SOME AQW effect that happens to share its hue closely enough (confirmed
// twice now — cyan collided with a teal pet aura, magenta collided with
// warm-white glow effects on a different character). Rendering the same
// character against TWO different known backdrop colors and solving the
// two linear blend equations directly recovers true alpha/color without
// ever assuming anything about the foreground's own hue — this is the
// standard approach real chroma-key software uses (Smith & Blinn's
// "triangulation matting"), not a formula tuned around one specific key.
//
// pixelA = alpha*trueColor + (1-alpha)*bgA
// pixelB = alpha*trueColor + (1-alpha)*bgB
// => pixelA - pixelB = (1-alpha) * (bgA - bgB)
// => alpha = 1 - (pixelA - pixelB) / (bgA - bgB)   [per channel, then combined]
//
// Using two NEUTRAL gray shades (100,100,100 and 155,155,155) instead of
// chromatic colors (magenta/green). This avoids the weapon-glow corruption
// that plagued the dual-key path: a glow is bright foreground content, and
// when it overlaps the character the difference between two chromatic backdrops
// (e.g. green vs magenta) is large enough that the glow pixel — which is
// identical in both passes — gets misidentified as background, producing
// garbage alpha (the flicker seen on Jaide's armor). With neutral grays,
// the glow pixel (bright R+G+B) is far from both backdrop values, so alpha
// correctly stays at ~1.0 and the recovered color is just the glow itself —
// which is correct. The character body pixels (which are not gray) also
// recover correctly because their color is far from the backdrop gray.
//
// The difference vector is (55, 55, 55) — same in all channels, so all
// three channels' independent alpha estimates are equally reliable and can
// just be averaged rather than needing to pick "the best" channel per pixel.
const CHROMA_KEY_A = [100, 100, 100]; // dark gray — bgColorOverride '646464'
const CHROMA_KEY_B = [155, 155, 155]; // light gray — bgColorOverride '9B9B9B'

function applyDualKeyMatte(imgA, imgB) {
  const dA = imgA.data, dB = imgB.data;
  const out = new Uint8ClampedArray(dA.length);
  const [aR, aG, aB] = CHROMA_KEY_A;
  const [bR, bG, bB] = CHROMA_KEY_B;
  const diffR = aR - bR, diffG = aG - bG, diffB = aB - bB; // (55, 55, 55)

  for (let p = 0; p < dA.length / 4; p++) {
    const i = p * 4;

    // (1-alpha) estimate from each channel independently, then averaged —
    // all three are equally well-conditioned given the ±255 diffs above.
    const oneMinusAlphaR = (dA[i]   - dB[i])   / diffR;
    const oneMinusAlphaG = (dA[i+1] - dB[i+1]) / diffG;
    const oneMinusAlphaB = (dA[i+2] - dB[i+2]) / diffB;
    const oneMinusAlpha = Math.max(0, Math.min(1, (oneMinusAlphaR + oneMinusAlphaG + oneMinusAlphaB) / 3));
    const alpha = 1 - oneMinusAlpha;

    if (alpha > 0.02) {
      // Unmix using pass A (either pass gives the same answer in theory;
      // A is picked arbitrarily since both are equally valid here).
      out[i]     = Math.max(0, Math.min(255, Math.round((dA[i]   - oneMinusAlpha * aR) / alpha)));
      out[i + 1] = Math.max(0, Math.min(255, Math.round((dA[i+1] - oneMinusAlpha * aG) / alpha)));
      out[i + 2] = Math.max(0, Math.min(255, Math.round((dA[i+2] - oneMinusAlpha * aB) / alpha)));
    }
    out[i + 3] = Math.round(dA[i+3] * alpha);
  }
  return new ImageData(out, imgA.width, imgA.height);
}

// One-shot dual-key capture: loads two player instances with different
// backdrop colors (bgColorOverride), waits for BOTH to report ready, THEN
// snapshots both back-to-back with waitUntilReady/snapshotPlayer — NOT
// loadAndCapture, which snapshots the instant its OWN poll succeeds. Since
// each pass's gear/sub-assets finish their own network fetch at a different
// real time, capturing on independent "ready" moments caught two different
// phases of the weapon's own real-time shine/glow loop — averaging two
// different phases of a moving highlight is exactly what produced the
// wrong (pink-tinted) weapon color. Waiting for both, then capturing
// together, means both SWFs' animation clocks (running since each began
// executing, not tied to asset-fetch timing) have advanced the same real
// amount by the time either snapshot is taken.
async function captureFullBodyDualKey(flashvars) {
  const passA = createOffscreenPlayer();
  const passB = createOffscreenPlayer();
  try {
    const w = RIG_STAGE_W * RENDER_SCALE, h = RIG_STAGE_H * RENDER_SCALE;
    const [readyA, readyB] = await Promise.all([
      waitUntilReady(passA.player, flashvars, { bgColorOverride: '646464' }),
      waitUntilReady(passB.player, flashvars, { bgColorOverride: '9B9B9B' }),
    ]);
    // The ready beacon only confirms the RIG's own base structure has
    // loaded — each colorable part (hair, cape, etc.) calls mcSetColor
    // itself, independently, once ITS OWN network fetch finishes, which is
    // not gated by the beacon at all. Snapshotting the instant ready fires
    // can catch a part mid-transition (still its native/undyed color) —
    // confirmed by dumping raw frames and comparing: e.g. jase's hair
    // sampled purple at the earliest capture, correct blonde a couple
    // frames later on the animated path (see the analogous settle-delay
    // fix there). Was 500 — raised to 1500 after continued reports of the
    // same race on a DIFFERENT asset (Jaide's "Hollowborn Eternal Dark
    // Fire" cape cosmetic, purple-flashing to green) that 500ms evidently
    // wasn't always enough margin for — a genuinely intermittent race
    // (didn't reproduce in every render attempted), not deterministic at
    // 500ms despite the original comment's assumption. Some cosmetics
    // likely have more involved color-application logic (a "flame" effect
    // may layer more than one simple mcSetColor call) or slower asset
    // fetch than the hair asset this delay was originally tuned against.
    await sleep(1500);
    const canvasA = snapshotPlayer(passA.player, w, h);
    if (!readyA || !readyB) return { canvas: canvasA, ready: false };
    const canvasB = snapshotPlayer(passB.player, w, h);

    const ctxA = canvasA.getContext('2d', { willReadFrequently: true });
    const ctxB = canvasB.getContext('2d', { willReadFrequently: true });
    const imgA = ctxA.getImageData(0, 0, w, h);
    const imgB = ctxB.getImageData(0, 0, w, h);
    const matted = applyDualKeyMatte(imgA, imgB);
    ctxA.putImageData(matted, 0, 0);

    return { canvas: canvasA, ready: true };
  } finally {
    destroyOffscreenPlayer(passA.stage, passA.player);
    destroyOffscreenPlayer(passB.stage, passB.player);
  }
}

// Animated dual-key capture: same synchronized-snapshot fix as above, then
// per-frame sampling continues to draw both players back-to-back in the
// same tick each interval (that part was always fine — the bug was only in
// how the INITIAL frame got captured, and every subsequent frame inherits
// whatever phase relationship was locked in at that first synchronized
// snapshot, so fixing the first one fixes all of them).
//
// CAPTURE_SUPERSAMPLE: the GIF's mandatory binary alpha (no partial
// transparency at all) makes broad/soft gradients — a wide coarse-banded
// cape edge, a soft drop shadow — dither into visible speckle no amount of
// tuning the dither algorithm itself can fully hide (confirmed across two
// failed attempts: an ordered Bayer dither introduced its own visible
// repeating line pattern; synthetically blurring the already-captured
// low-res alpha channel fixed the broad regions but incorrectly widened
// every crisp edge too, since blur can't add real detail, only spread
// existing coarse data). The only way to genuinely close the gap toward
// the static PNG's true smooth 8-bit alpha is real additional RENDERED
// detail — Ruffle actually rasterizing at a higher resolution, not a
// software approximation applied after the fact.
//
// This renders each offscreen player at CAPTURE_SUPERSAMPLE x the normal
// output resolution (createOffscreenPlayer's `scale` param), then draws
// that bigger live canvas down into the SAME output-resolution sample
// canvas as before via `drawImage` — the browser's own canvas 2D API does
// real box/bilinear downsampling here (`imageSmoothingQuality: 'high'`),
// no custom blur code needed. Every pixel handed to applyDualKeyMatte,
// and everything downstream of THIS function (all of renderBotAnimated.
// html's masking/pet-extraction/compositing, all of renderCharacter.js's
// dithering) runs at EXACTLY the same resolution as before this change —
// completely untouched, zero risk to that fragile, multi-round-debugged
// logic — they just receive smoother, genuinely-antialiased source pixels
// instead of the coarser native-resolution capture.
//
// Deliberately NOT a RENDER_SCALE bump: RENDER_SCALE is baked into the
// output resolution used by every downstream pixel-masking/flood-fill
// algorithm, and a past bump to that exact combination (this same
// 1440x825 stage) is directly documented above as catastrophic — 13.8s to
// still-not-finished after 3+ minutes, from GC/memory pressure in that
// masking logic specifically, not naive proportional slowdown. This path
// avoids that landmine entirely: the masking logic never sees the bigger
// resolution, only Ruffle's own rendering and the dual-key unmix (simple
// per-pixel arithmetic, not flood-fill/connected-component search) run at
// the higher size.
const CAPTURE_SUPERSAMPLE = 2;
async function captureAnimatedFramesDualKey(flashvars, { frameCount = 48, intervalMs = 42 } = {}) {
  const passA = createOffscreenPlayer(CAPTURE_SUPERSAMPLE);
  const passB = createOffscreenPlayer(CAPTURE_SUPERSAMPLE);
  try {
    const w = RIG_STAGE_W * RENDER_SCALE, h = RIG_STAGE_H * RENDER_SCALE;
    const [readyA, readyB] = await Promise.all([
      waitUntilReady(passA.player, flashvars, { bgColorOverride: '646464' }),
      waitUntilReady(passB.player, flashvars, { bgColorOverride: '9B9B9B' }),
    ]);
    if (!readyA || !readyB) return { frames: [], ready: false };
    // Same race as captureFullBodyDualKey above — the ready beacon doesn't
    // gate on every colorable part's own independent mcSetColor call, so
    // frame 0 (and possibly the next couple, at 42ms apart) can be sampled
    // before a part's dye color has actually been applied, then "swap" to
    // the correct color a few frames in. Since a GIF loops back to frame 0
    // every cycle, this reads as a periodic color flicker at the start of
    // every loop (confirmed: jase's hair sampled purple at frame 0, correct
    // blonde by frame 2 without this delay). Settle before sampling starts
    // so every captured frame — including frame 0 — already has the right
    // color, rather than trying to detect/skip bad early frames after the
    // fact. Was 500 — raised to 1500, see captureFullBodyDualKey's comment
    // above for the real-world report (Jaide's cape) that motivated this.
    await sleep(1500);

    const srcA = passA.player.shadowRoot?.querySelector('canvas') || passA.player.querySelector('canvas');
    const srcB = passB.player.shadowRoot?.querySelector('canvas') || passB.player.querySelector('canvas');
    const frames = [];
    const sampleA = document.createElement('canvas').getContext('2d', { willReadFrequently: true });
    const sampleB = document.createElement('canvas').getContext('2d', { willReadFrequently: true });
    sampleA.canvas.width = sampleB.canvas.width = w;
    sampleA.canvas.height = sampleB.canvas.height = h;
    sampleA.imageSmoothingEnabled = sampleB.imageSmoothingEnabled = true;
    sampleA.imageSmoothingQuality = sampleB.imageSmoothingQuality = 'high';

    for (let f = 0; f < frameCount; f++) {
      sampleA.clearRect(0, 0, w, h);
      sampleB.clearRect(0, 0, w, h);
      // srcA/srcB are CAPTURE_SUPERSAMPLE x bigger than w,h here — this
      // draw call is the actual downsample step (see comment above).
      sampleA.drawImage(srcA, 0, 0, w, h);
      sampleB.drawImage(srcB, 0, 0, w, h);
      const imgA = sampleA.getImageData(0, 0, w, h);
      const imgB = sampleB.getImageData(0, 0, w, h);
      frames.push(applyDualKeyMatte(imgA, imgB));
      if (f < frameCount - 1) await sleep(intervalMs);
    }

    return { frames, width: w, height: h, ready: true };
  } finally {
    destroyOffscreenPlayer(passA.stage, passA.player);
    destroyOffscreenPlayer(passB.stage, passB.player);
  }
}

// Slice the one full-body capture into per-part sub-canvases using the
// calibrated crop rectangles. Cheap, one render pass — parts that overlap
// in the original z-order (e.g. shoulder over chest's edge) will carry a
// little bleed into whichever part's crop underlaps there, but the real
// covering part is redrawn on top at the correct z-index in the DOM, so it
// only matters if that covering part later animates away from its resting
// spot. Judge this visually before escalating to per-part isolated capture.
function sliceParts(fullCanvas) {
  const slices = {};
  for (const [name, crop] of Object.entries(RIG_PART_CROPS)) {
    // fullCanvas is supersampled (RENDER_SCALE x native) — read the scaled-up
    // source region, but keep the OUTPUT slice at that same higher
    // resolution too (rather than downscaling here) so the DOM's own
    // width:100%/height:100% (matching the native-size part <div>) does the
    // final downscale — the browser's image scaling gives a crisper result
    // than pre-shrinking a small crop ourselves.
    const c = document.createElement('canvas');
    c.width = crop.w * RENDER_SCALE;
    c.height = crop.h * RENDER_SCALE;
    c.getContext('2d').drawImage(
      fullCanvas,
      crop.x * RENDER_SCALE, crop.y * RENDER_SCALE, crop.w * RENDER_SCALE, crop.h * RENDER_SCALE,
      0, 0, c.width, c.height
    );
    slices[name] = c;
  }
  return slices;
}

// Build the real nested hierarchy. Each part is a <div> containing its
// sliced image, positioned via translate() relative to its DOM parent
// (not absolute stage coordinates) so nesting composes correctly, with
// transform-origin set at its calibrated joint so rotation pivots in the
// right place. Returns { root, elements } — elements keyed by part name,
// for animation code to grab and transform later.
function buildRigDom(container, slices) {
  container.innerHTML = '';
  container.style.position = 'relative';

  const elements = {};

  function makePart(name) {
    const crop = RIG_PART_CROPS[name];
    const joint = RIG_JOINTS[name];
    const parentName = PARENT_OF[name];
    const parentCrop = parentName ? RIG_PART_CROPS[parentName] : { x: 0, y: 0 };

    const el = document.createElement('div');
    el.className = 'rig-part rig-' + name;
    el.style.position = 'absolute';
    el.style.left = (crop.x - parentCrop.x) + 'px';
    el.style.top = (crop.y - parentCrop.y) + 'px';
    el.style.width = crop.w + 'px';
    el.style.height = crop.h + 'px';
    el.style.zIndex = String(Z_INDEX[name] || 0);
    el.style.transformOrigin = (joint.x - crop.x) + 'px ' + (joint.y - crop.y) + 'px';

    const img = document.createElement('img');
    img.src = slices[name].toDataURL();
    img.style.width = '100%';
    img.style.height = '100%';
    img.style.display = 'block';
    img.draggable = false;
    el.appendChild(img);

    elements[name] = el;
    return el;
  }

  // chest is the root, positioned directly against the container's own
  // origin (container itself represents the full stage, cropped/scaled by
  // the caller same way the existing production render does).
  const chest = makePart('chest');
  chest.style.left = RIG_PART_CROPS.chest.x + 'px';
  chest.style.top = RIG_PART_CROPS.chest.y + 'px';
  container.appendChild(chest);

  for (const [name, parent] of Object.entries(PARENT_OF)) {
    if (name === 'chest') continue;
    const el = makePart(name);
    elements[parent].appendChild(el);
  }

  return { root: chest, elements };
}

// Simple staged easing helpers — real elapsed time (seconds) in, not a frame
// counter, so timing reads directly as "this stage takes 0.3s" instead of an
// arbitrary phase multiplier.
function clamp01(x) { return Math.max(0, Math.min(1, x)); }
function easeOutCubic(x) { return 1 - Math.pow(1 - x, 3); }
function easeInCubic(x) { return x * x * x; }

// Winner: raise the front fist (Mixamo "Victory"/"Fist Pump" reference —
// quick ease-out raise, then hold with a small pump/bounce) rather than
// swinging through a big arc the whole time. Because frontshoulder is a
// TRUE DOM parent of fronthand, rotating just the shoulder correctly carries
// the hand with it — no repositioning math needed, which is the payoff of
// this rebuild.
// Deliberately touches ONLY joints with a real calibrated pivot (chest,
// head, frontshoulder, frontthigh/frontshin) — backshoulder/backthigh/
// backshin/backfoot never got a working calibration and visibly detach
// whenever animated, so this just doesn't touch them.
function playWinEmote(container, elements) {
  const start = performance.now();
  let rafId;

  function tick(now) {
    rafId = requestAnimationFrame(tick);
    const t = (now - start) / 1000;

    // Stage 1 (0-0.3s): raise the front arm from resting to overhead.
    const raise = easeOutCubic(clamp01(t / 0.3));
    // Stage 2 (once raised): small fist-pump bounce held at the top.
    const pump = raise >= 1 ? Math.sin((t - 0.3) * 8) : 0;
    elements.frontshoulder.style.transform = `rotate(${raise * -125 + pump * 8}deg)`;

    // Whole-body hop, synced with the pump — one-sided so it reads as a
    // bounce, not a symmetric bob.
    const hop = raise >= 1 ? Math.max(0, Math.sin((t - 0.3) * 8)) * 8 : 0;
    elements.chest.style.transform = `translateY(${-hop}px)`;

    // Head tilts back into the celebration as the arm comes up.
    elements.head.style.transform = `rotate(${-raise * 12}deg)`;

    // Front leg does a happy one-sided kick in time with the hop.
    const kick = raise >= 1 ? Math.max(0, Math.sin((t - 0.3) * 8)) * 18 : 0;
    elements.frontthigh.style.transform = `rotate(${kick}deg)`;
    elements.frontshin.style.transform = `rotate(${kick * 0.4}deg)`;
  }
  rafId = requestAnimationFrame(tick);
  return { stop: () => cancelAnimationFrame(rafId) };
}

// Loser: head-hang, then topple backward, then dim (Mixamo "Sad Idle" into
// "Falling Back Death" reference beats). The topple pivots around the feet
// (idlefoot's calibrated joint, expressed relative to chest's own box) by
// setting chest's transform-origin to a point OUTSIDE its own bounding box —
// CSS allows this natively. Only touches calibrated joints (chest, head,
// frontthigh/frontshin) for the same reason playWinEmote does.
function playLoseEmote(container, elements) {
  const start = performance.now();
  let rafId;
  let tears = null;

  const chestCrop = RIG_PART_CROPS.chest;
  const feetJoint = RIG_JOINTS.idlefoot;
  elements.chest.style.transformOrigin = `${feetJoint.x - chestCrop.x}px ${feetJoint.y - chestCrop.y}px`;

  function tick(now) {
    rafId = requestAnimationFrame(tick);
    const t = (now - start) / 1000;

    // Stage 1 (0-0.4s): head hangs down.
    const headDown = easeInCubic(clamp01(t / 0.4));
    elements.head.style.transform = `rotate(${headDown * 25}deg)`;

    // Stage 2 (0.3s-1.1s): topple backward around the feet.
    const fall = easeOutCubic(clamp01((t - 0.3) / 0.8));
    elements.chest.style.transform = `rotate(${fall * 80}deg)`;

    if (fall >= 1) {
      if (!tears) tears = createTears(elements.head);
      updateTears(tears);

      // Slow twitch of the front leg once down — not a full kick, just
      // enough to read as "still on the ground, not just a frozen ragdoll."
      const twitch = Math.sin((t - 1.1) * 2) * 10;
      elements.frontthigh.style.transform = `rotate(${twitch}deg)`;
      elements.frontshin.style.transform = `rotate(${twitch * 0.4}deg)`;
      elements.head.style.transform = `rotate(${25 + Math.sin((t - 1.1) * 1.5) * 4}deg)`;
    }

    // Stage 3 (after the fall settles): gradual dim, as consciousness fades.
    const dim = clamp01((t - 1.4) / 1.0);
    container.style.filter = `brightness(${1 - dim * 0.5})`;
  }
  rafId = requestAnimationFrame(tick);
  return { stop: () => cancelAnimationFrame(rafId) };
}

// Custom crying effect — simple CSS-drawn teardrop divs, real children of
// the head element so they automatically follow its rotation for free
// (direct DOM analog of the old AS3 createTears()/updateTears(), which
// parented tears under rig.head for the identical reason).
function createTears(headEl) {
  const tears = [];
  for (let i = 0; i < 2; i++) {
    const tear = document.createElement('div');
    tear.style.cssText = `position:absolute;width:4px;height:7px;border-radius:50% 50% 50% 0;
      background:#55ccff;transform:rotate(45deg);left:${i === 0 ? 8 : 15}px;top:${2 + i * 6}px;`;
    headEl.appendChild(tear);
    tears.push({ el: tear, y: 2 + i * 6 });
  }
  return tears;
}

function updateTears(tears) {
  for (const t of tears) {
    t.y += 0.5;
    t.el.style.top = t.y + 'px';
    t.el.style.opacity = Math.max(0, 1 - (t.y - 2) / 22);
    if (t.y > 24) { t.y = 2 + Math.random() * 4; t.el.style.opacity = 1; }
  }
}

// Connected-component (flood-fill) blob finder over an alpha mask, used to
// separate the pet from the character. A simple x-coordinate split (e.g.
// "anything left of the character's known scan window is the pet") looked
// reasonable but broke in practice: a downsized pet's body routinely
// extends INTO that window rather than staying entirely outside it, so the
// split only caught a tiny sliver of the pet's edge instead of its whole
// body. Flood-filling the real alpha mask has no such assumption — it finds
// the pet's true bounding box regardless of exactly how close it sits to
// the character, as long as there's at least a 1px gap of transparency
// between the two (which there always is; they're separately-rendered
// display objects, never touching pixel-for-pixel).
function findAlphaBlobs(alphaAt, w, h, x0, y0, x1, y1) {
  const visited = new Uint8Array(w * h);
  const blobs = [];
  const stack = [];
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      const startIdx = y * w + x;
      if (visited[startIdx] || !alphaAt(x, y)) continue;
      let bMinX = x, bMinY = y, bMaxX = x, bMaxY = y, count = 0;
      stack.length = 0;
      stack.push(startIdx);
      visited[startIdx] = 1;
      while (stack.length) {
        const cur = stack.pop();
        const cx = cur % w, cy = (cur - cx) / w;
        count++;
        if (cx < bMinX) bMinX = cx; if (cx > bMaxX) bMaxX = cx;
        if (cy < bMinY) bMinY = cy; if (cy > bMaxY) bMaxY = cy;
        for (let dy = -1; dy <= 1; dy++) {
          for (let dx = -1; dx <= 1; dx++) {
            if (dx === 0 && dy === 0) continue;
            const nx = cx + dx, ny = cy + dy;
            if (nx < x0 || nx >= x1 || ny < y0 || ny >= y1) continue;
            const nidx = ny * w + nx;
            if (visited[nidx] || !alphaAt(nx, ny)) continue;
            visited[nidx] = 1;
            stack.push(nidx);
          }
        }
      }
      blobs.push({ minX: bMinX, minY: bMinY, maxX: bMaxX, maxY: bMaxY, count });
    }
  }
  return blobs;
}

// Name/guild header presets, shared by both render harnesses. Two
// independent `style` (font) and `color` (theme) query params pick these,
// so any font can be combined with any color theme. `classic` is the
// default for both and renders identically to the original hardcoded
// look before either option existed (white name, white guild — matching
// each other, per explicit user request — plain sans-serif, black stroke).
const TEXT_STYLES = {
  classic:     { font: 'sans-serif' },
  comic:       { font: '"Comic Sans MS", cursive' },
  impact:      { font: 'Impact, sans-serif' },
  papyrus:     { font: 'Gabriola, fantasy' },
  typewriter:  { font: '"Courier New", monospace' },
  elegant:     { font: 'Georgia, serif' },
  handwritten: { font: '"Segoe Script", cursive' },
  gothic:      { font: '"MV Boli", cursive' },
  bold:        { font: '"Arial Black", sans-serif' },
  tech:        { font: '"Cascadia Mono", monospace' },
};
function getTextStyle(key) {
  return TEXT_STYLES[key] || TEXT_STYLES.classic;
}

const CLASSIC_STROKE = 'rgba(0,0,0,0.85)';
function colorTheme(color) {
  return { color, stroke: CLASSIC_STROKE };
}
const COLOR_THEMES = {
  classic: colorTheme('#ffffff'),
  gold:    colorTheme('#ffd966'),
  crimson: colorTheme('#ff4d4d'),
  azure:   colorTheme('#4da6ff'),
  emerald: colorTheme('#4dff88'),
  violet:  colorTheme('#b366ff'),
  inferno: colorTheme('#ff8c1a'),
  silver:  colorTheme('#d9d9d9'),
};
function getColorTheme(key) {
  return COLOR_THEMES[key] || COLOR_THEMES.classic;
}

window.RigAvatar = { RIG_PART_CROPS, RIG_JOINTS, PARENT_OF, RIG_STAGE_W, RIG_STAGE_H, RENDER_SCALE, RIG_CENTER_X,
  captureFullBody, captureAnimatedFrames, captureFullBodyDualKey, captureAnimatedFramesDualKey,
  sliceParts, buildRigDom, playWinEmote, playLoseEmote, findAlphaBlobs, readHeadInfoBeacons,
  TEXT_STYLES, getTextStyle, COLOR_THEMES, getColorTheme };
})();

// Drives skua-server's rig-rendering pipeline (Ruffle render -> auto-crop
// to the character, see public/renderBotStatic.html) inside a headless
// browser and returns a single static PNG buffer. Deliberately no
// rig-slicing/joint animation layer — the DOM-slicing/joint system in
// rigAvatar.js's playWinEmote path looked visibly "off" (bad head crop,
// joints not lining up).
//
// renderCharacterGif below is a separate, narrower case: some gear items
// (e.g. a weapon) bake their own shine/glow loop directly into their SWF
// timeline. That's native animation the item already has in-game, not
// anything we're puppeteering — capturing it just means sampling several
// frames instead of one and encoding them as a GIF.
const puppeteer = require('puppeteer');
const { PNG } = require('pngjs');
const { GIFEncoder, quantize, applyPalette } = require('gifenc');
const ffmpeg = require('fluent-ffmpeg');
const ffmpegPath = require('ffmpeg-static');
const { PassThrough } = require('stream');
const fs = require('fs');
const os = require('os');
const path = require('path');
ffmpeg.setFfmpegPath(ffmpegPath);

const SERVER_URL = process.env.RENDER_SERVER_URL || 'http://localhost:3000';

async function renderCharacterImage(username, style, color) {
  const browser = await puppeteer.launch({ headless: 'shell', args: ['--no-sandbox', '--disable-setuid-sandbox'] });
  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 960, height: 550 });

    const url = `${SERVER_URL}/renderBotStatic.html?username=${encodeURIComponent(username)}${style ? '&style=' + encodeURIComponent(style) : ''}${color ? '&color=' + encodeURIComponent(color) : ''}`;
    await page.goto(url, { waitUntil: 'domcontentloaded' });

    await page.waitForFunction(
      () => window.__renderReady === true || window.__renderError !== null,
      { timeout: 120000 }
    );

    const result = await page.evaluate(() => ({
      dataUrl: window.__renderDataUrl,
      error: window.__renderError,
    }));

    if (result.error) throw new Error('render page reported: ' + result.error);

    const base64 = result.dataUrl.replace(/^data:image\/png;base64,/, '');
    return Buffer.from(base64, 'base64');
  } finally {
    await browser.close();
  }
}

// Shared by renderCharacterGif and renderCharacterVideo below — both need
// the exact same raw captured frames (post-crop/extraction, pre-encode),
// just process them differently from here on.
async function captureAnimatedPngFrames(username, style, color) {
  const browser = await puppeteer.launch({ headless: 'shell', args: ['--no-sandbox', '--disable-setuid-sandbox'] });
  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 960, height: 550 });

    const url = `${SERVER_URL}/renderBotAnimated.html?username=${encodeURIComponent(username)}${style ? '&style=' + encodeURIComponent(style) : ''}${color ? '&color=' + encodeURIComponent(color) : ''}`;
    await page.goto(url, { waitUntil: 'domcontentloaded' });

    await page.waitForFunction(
      () => window.__renderReady === true || window.__renderError !== null,
      { timeout: 120000 }
    );

    const result = await page.evaluate(() => ({
      frames: window.__renderFrames,
      error: window.__renderError,
    }));

    if (result.error) throw new Error('render page reported: ' + result.error);

    return result.frames.map(dataUrl =>
      PNG.sync.read(Buffer.from(dataUrl.replace(/^data:image\/png;base64,/, ''), 'base64'))
    );
  } finally {
    await browser.close();
  }
}

async function renderCharacterGif(username, style, color) {
  const pngs = await captureAnimatedPngFrames(username, style, color);
  const { width, height } = pngs[0];

  // GIF has no partial transparency — every pixel is either the
  // transparent index or fully opaque. Our source frames have smoothly
  // fading alpha at edges (from the chroma-key de-spill, which stays
  // untouched), so any edge pixel with alpha > 0 but not high enough to
  // read as "real" gets forced fully OPAQUE by the GIF format, showing
  // whatever color it has at full strength instead of fading away.
  // That color itself is often garbage at very low alpha (the de-spill
  // divides by alpha, which is numerically unstable near zero) —
  // confirmed by comparing this exact frame data before/after: the raw
  // PNG frame had no visible fringe, only the GIF did. Thresholding
  // alpha to fully transparent/fully opaque HERE (gif-encoding step
  // only, not the shared masking function) turns those near-invisible
  // low-alpha garbage-color pixels into simply "not there" instead of
  // "loudly wrong color at full opacity."
  const ALPHA_THRESHOLD = 50; // lowered from 235 — that value was wiping out Ryuu's translucent cape almost entirely
  // A plain binary cutoff is fine for a 1-2px anti-aliased edge (the
  // "jump" is imperceptible), but wrong for a WIDE soft gradient — a large
  // glow/blur effect (Ryuu's wing aura, SmokeCity's smoke pet) has many
  // consecutive partial-alpha pixels, so the cutoff shows up as a hard,
  // straight-looking edge with a flat solid-color block on one side
  // (confirmed: isolating just this threshold step on SmokeCity's frame 0
  // reproduced the exact artifact, before any palette quantization even
  // ran). An earlier attempt blended EVERY partial-alpha pixel toward
  // white — that also smoothed thin edges that didn't need it, and
  // white is flatly wrong on Discord's dark theme (a fading glow baked
  // toward white reads as a garish light smear, not a fade). Fix: blend
  // every partial-alpha pixel toward a dark backdrop close to Discord's
  // own theme background instead of white, so any partial-alpha pixel
  // fades toward what it'll actually be seen against instead of showing
  // an arbitrary wrong color. This blend was originally gated to only
  // "broad soft regions" (a windowed density check), on the assumption a
  // thin 1-2px anti-aliased edge would look fine with a plain binary
  // cutoff — that assumption was wrong: the raw de-spilled color at those
  // edge pixels is often genuinely dark/wrong (same de-spill instability
  // as the comment above describes), so thin edges left unblended showed
  // up as a visible black outline around the whole character/pet
  // silhouette (caught by comparing static PNG vs animated GIF side by
  // side — the PNG's real partial alpha hid the same bad color, the
  // GIF's forced-opaque didn't). Blending every partial-alpha pixel the
  // same way removes the outline and is simpler — no more windowed
  // density scan needed to decide broad vs thin.
  // First attempt used #313338 (Discord's standard chat-background gray)
  // as the bake target — wrong guess. A real screenshot of the posted GIF
  // showed the actual background is near-pure-black (sampled directly
  // from the user's screenshot: RGB ~2,2,2, not 49,51,56), so every
  // blended broad-glow region showed up as a faint lighter halo against
  // it. Matching the color actually observed, not the theoretical default.
  const DARK_BACKDROP = [2, 2, 2]; // matches the real posted-GIF background, sampled directly
  // Some source assets (confirmed on Prime's "Solar Eclipse" cape, and on
  // the pet's dark wing shapes) have a genuinely COARSE alpha gradient —
  // this shows up as a visibly blocky (cape) or textured edge under a
  // plain threshold cut. Three dithering-based approaches were tried
  // afterward to soften that — ordered (Bayer) dither, then Floyd-
  // Steinberg error diffusion, then a pre-dither alpha blur — all
  // REVERTED. User's own close-up comparison (static PNG vs. GIF, same
  // glow-ring edge) made the real problem clear: GIF's alpha is strictly
  // binary (every pixel fully transparent or fully opaque, no partial
  // values at all), so ANY dithering scheme — no matter how fine or
  // well-distributed — can only ever arrange opaque/transparent pixels
  // to approximate a gradient's DENSITY from a distance. It can never
  // reproduce an actual BLUR, because that requires pixels with real
  // partial transparency, which this format cannot represent. Up close,
  // every dithering variant tried still read as visible speckle/texture,
  // not a smooth fade — explicitly rejected by the user ("looks
  // horrible"), not merely under-tuned. Reverted to the plain approach
  // below: no dithering, just a hard threshold cutoff with the backdrop
  // blend for the pixels that stay opaque.
  for (const png of pngs) {
    const d = png.data;
    for (let i = 3; i < d.length; i += 4) {
      const a = d[i];
      if (a === 255) continue;
      if (a === 0) {
        d[i-3] = 255; d[i-2] = 0; d[i-1] = 255;
        continue;
      }
      if (a < ALPHA_THRESHOLD) {
        d[i] = 0;
        // Mark cleared pixels with a distinctive color (pure magenta —
        // already established as rare-to-nonexistent in real AQW art,
        // same reasoning as the chroma-key backdrop choice) rather than
        // leaving them at whatever the de-spill happened to compute.
        // Needed because of the format switch below: 'rgba4444' kept
        // alpha IN the palette so transparent pixels and Prime's own
        // genuinely-opaque solid-black clothing (identical (0,0,0) RGB)
        // still ended up in different palette entries. Switching to
        // 'rgb565' for real color precision (4 bits/channel was forcing
        // pure white and warm skin-tone edge pixels into the same
        // compromise cluster, producing the pink tint the user caught)
        // drops alpha from the palette entirely, so without this marker
        // "transparent" and "opaque black" would collide into one
        // palette slot — making Prime's whole black body vanish too.
        d[i-3] = 255; d[i-2] = 0; d[i-1] = 255;
      } else {
        const t = a / 255;
        d[i-3] = Math.round(d[i-3] * t + DARK_BACKDROP[0] * (1 - t));
        d[i-2] = Math.round(d[i-2] * t + DARK_BACKDROP[1] * (1 - t));
        d[i-1] = Math.round(d[i-1] * t + DARK_BACKDROP[2] * (1 - t));
        d[i] = 255;
      }
    }
  }

  // ONE shared palette built from every frame combined, not a fresh
  // quantization per frame — a per-frame palette let static regions
  // (armor, hair, the name text) pick very slightly different nearest
  // colors from one frame to the next, which reads as a low-level
  // flicker/noise across the WHOLE character, not just the weapon shine
  // that's actually supposed to move. rgb565 gives real 5-6-5 bit color
  // precision (vs rgba4444's 4-4-4-4) — see the marker-color comment
  // above for why alpha no longer needs to live in the palette itself.
  const allPixels = Buffer.concat(pngs.map(p => p.data));
  const sharedPalette = quantize(allPixels, 255, { format: 'rgb565' });

  // gifenc doesn't auto-detect a transparent color — writeFrame's
  // `transparent: true` alone is a no-op without an explicit
  // transparentIndex. Since every cleared pixel was just marked pure
  // magenta above, whichever palette entry is nearest to magenta IS the
  // transparent slot — found by distance rather than exact equality
  // since quantization can round the marker color slightly.
  let transparentIndex = 0, bestDist = Infinity;
  sharedPalette.forEach((c, idx) => {
    const dist = (c[0] - 255) ** 2 + c[1] ** 2 + (c[2] - 255) ** 2;
    if (dist < bestDist) { bestDist = dist; transparentIndex = idx; }
  });

  // Matches renderBotAnimated.html's own capture interval (Ruffle's native
  // 24fps) — a mismatched delay here would still play back at the wrong
  // speed even though the source frames were sampled smoothly.
  const FRAME_DELAY_MS = Math.round(1000 / 24);

  const gif = GIFEncoder();
  for (const png of pngs) {
    const index = applyPalette(png.data, sharedPalette, 'rgb565');
    gif.writeFrame(index, width, height, { palette: sharedPalette, delay: FRAME_DELAY_MS, transparent: true, transparentIndex });
  }
  gif.finish();

  return Buffer.from(gif.bytes());
}

// GIF's fixed 256-color shared palette is the root cause of a recurring
// "flickers between two colors" bug on detailed armor — see renderCharacter.js
// history in memory: a shared palette (see sharedPalette above) already fixed
// per-frame palette drift, but with enough distinct close shades in one
// character's gear, 255 slots for the WHOLE frame just isn't enough headroom,
// and quantization rounds the same visual area to two different nearest
// palette entries from frame to frame. That's a hard format ceiling, not a
// per-asset bug — chasing it asset-by-asset (as the dithering/threshold
// investigations elsewhere in this file already did for the alpha side of
// GIF's limitations) isn't worth repeating for color depth too. This function
// sidesteps it entirely: MP4 has no shared palette, every frame gets full
// 24-bit color, so this whole bug class can't occur.
//
// No transparency handling needed here (unlike the GIF path) — video has no
// alpha channel at all, so every pixel is unconditionally composited onto a
// backdrop color using its REAL alpha value (not a binary threshold like the
// GIF path needs), which is strictly smoother than anything GIF could ever
// produce for partial-alpha edges/glows.
//
// Deliberately NOT the same near-black [2,2,2] renderCharacterGif uses.
// That value was tuned to match Discord's actual observed background so
// GIF's real transparent pixels blend in seamlessly at the edges — but
// video has no transparency at all, so its background is ALWAYS a fully
// opaque rectangle behind the character; there's no "seamless" case to
// match here regardless of color chosen. Matching near-black actively
// backfires for this format: any character in black/dark gear disappears
// into a same-color backdrop with zero contrast (reported directly: "cant
// see them"). Use Discord's own dark-theme SURFACE gray instead (close to
// its embed/message-box background, not the darker outer chat background)
// — dark enough to still look native to Discord's theme, but far enough
// from near-black gear to keep a visible silhouette edge.
const DARK_BACKDROP = [32, 34, 37];
async function renderCharacterVideo(username, style, color) {
  const pngs = await captureAnimatedPngFrames(username, style, color);
  const { width, height } = pngs[0];
  // yuv420p (chroma subsampling) requires even dimensions on both axes —
  // our frame size is whatever the alpha-bbox crop happened to measure for
  // this specific character (arbitrary, often odd, e.g. 523px wide for
  // Ryuu), not a fixed render resolution. Pad by at most 1px per axis with
  // solid DARK_BACKDROP rather than scaling, so the real content is never
  // resized/resampled — just given up to 1 extra edge pixel of backdrop.
  const outW = width + (width % 2);
  const outH = height + (height % 2);

  const rgbFrames = pngs.map(png => {
    const src = png.data;
    // Buffer.alloc's fill takes a single repeated byte, not an RGB triplet,
    // so the 1px padding column/row (see above) is written explicitly with
    // the real DARK_BACKDROP below rather than relying on the zero-fill
    // default — that default silently stopped matching once DARK_BACKDROP
    // moved off a near-zero value.
    const rgb = Buffer.alloc(outW * outH * 3);
    for (let y = 0; y < outH; y++) {
      for (let x = 0; x < outW; x++) {
        const di = (y * outW + x) * 3;
        if (x >= width || y >= height) {
          rgb[di] = DARK_BACKDROP[0];
          rgb[di + 1] = DARK_BACKDROP[1];
          rgb[di + 2] = DARK_BACKDROP[2];
          continue;
        }
        const si = (y * width + x) * 4;
        const a = src[si + 3] / 255;
        rgb[di] = Math.round(src[si] * a + DARK_BACKDROP[0] * (1 - a));
        rgb[di + 1] = Math.round(src[si + 1] * a + DARK_BACKDROP[1] * (1 - a));
        rgb[di + 2] = Math.round(src[si + 2] * a + DARK_BACKDROP[2] * (1 - a));
      }
    }
    return rgb;
  });

  // Matches the GIF path's own frame pacing (Ruffle's native 24fps capture).
  const FPS = 24;

  // `-movflags +faststart` (moves the moov atom to the front of the file,
  // needed so Discord/browsers can start playback before the whole file
  // downloads) requires a SEEKABLE output — confirmed via a direct ffmpeg
  // stderr dump ("muxer does not support non seekable output") when piping
  // straight to stdout. A plain OS temp file is trivially seekable and the
  // total output here is only a couple hundred KB for a few dozen frames,
  // so the extra disk round-trip costs nothing worth avoiding.
  const outPath = path.join(os.tmpdir(), `aqwavatarbot_${process.pid}_${Date.now()}.mp4`);
  try {
    await new Promise((resolve, reject) => {
      const input = new PassThrough();
      input.end(Buffer.concat(rgbFrames));

      ffmpeg(input)
        .inputFormat('rawvideo')
        .inputOptions([`-pixel_format rgb24`, `-video_size ${outW}x${outH}`, `-framerate ${FPS}`])
        .videoCodec('libx264')
        // yuv420p (not the default yuv444p) is required for QuickTime/mobile/
        // Discord's own embedded player compatibility, not just a size choice.
        // crf 18 is visually near-lossless — file size isn't a concern at this
        // resolution/duration (a couple seconds), correctness/quality is.
        .outputOptions(['-pix_fmt yuv420p', '-crf 18', '-preset veryfast', '-movflags +faststart'])
        .format('mp4')
        .on('error', reject)
        .on('end', resolve)
        .save(outPath);
    });
    return await fs.promises.readFile(outPath);
  } finally {
    await fs.promises.unlink(outPath).catch(() => {}); // best-effort cleanup, render result is already read/returned either way
  }
}

module.exports = { renderCharacterImage, renderCharacterGif, renderCharacterVideo };

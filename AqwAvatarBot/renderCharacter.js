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

const SERVER_URL = process.env.RENDER_SERVER_URL || 'http://localhost:3000';

async function renderCharacterImage(username) {
  const browser = await puppeteer.launch({ headless: true });
  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 960, height: 550 });

    const url = `${SERVER_URL}/renderBotStatic.html?username=${encodeURIComponent(username)}`;
    await page.goto(url, { waitUntil: 'domcontentloaded' });

    await page.waitForFunction(
      () => window.__renderReady === true || window.__renderError !== null,
      { timeout: 30000 }
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

async function renderCharacterGif(username) {
  const browser = await puppeteer.launch({ headless: true });
  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 960, height: 550 });

    const url = `${SERVER_URL}/renderBotAnimated.html?username=${encodeURIComponent(username)}`;
    await page.goto(url, { waitUntil: 'domcontentloaded' });

    await page.waitForFunction(
      () => window.__renderReady === true || window.__renderError !== null,
      { timeout: 30000 }
    );

    const result = await page.evaluate(() => ({
      frames: window.__renderFrames,
      error: window.__renderError,
    }));

    if (result.error) throw new Error('render page reported: ' + result.error);

    const pngs = result.frames.map(dataUrl =>
      PNG.sync.read(Buffer.from(dataUrl.replace(/^data:image\/png;base64,/, ''), 'base64'))
    );
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
    const ALPHA_THRESHOLD = 235; // was 200 — pushed higher after a residual fringe was still visible on Prime's halo ring
    for (const png of pngs) {
      const d = png.data;
      for (let i = 3; i < d.length; i += 4) {
        if (d[i] < ALPHA_THRESHOLD) {
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
  } finally {
    await browser.close();
  }
}

module.exports = { renderCharacterImage, renderCharacterGif };

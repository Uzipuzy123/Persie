// Local preview server — lets you view a render directly in a browser tab
// (just hit refresh) instead of going through Discord every time. Calls the
// EXACT SAME renderCharacterImage/renderCharacterGif functions the real bot
// uses (index.js), so whatever shows up here is guaranteed to match what
// the bot would post — no separate code path to drift out of sync.
//
// Run: node preview-server.js
// Then open: http://localhost:3001/?username=ryuu
require('dotenv').config();
const http = require('http');
const { URL } = require('url');
const { renderCharacterImage, renderCharacterGif, renderCharacterVideo } = require('./renderCharacter');

const PORT = 3001;

const STYLES = ['classic', 'comic', 'impact', 'papyrus', 'typewriter', 'elegant', 'handwritten', 'gothic', 'bold', 'tech'];
const COLORS = ['classic', 'gold', 'crimson', 'azure', 'emerald', 'violet', 'inferno', 'silver'];

function page(username, style, color) {
  const u = encodeURIComponent(username || 'ryuu');
  const s = STYLES.includes(style) ? style : 'classic';
  const c = COLORS.includes(color) ? color : 'classic';
  const styleOptions = STYLES.map(v => `<option value="${v}" ${v === s ? 'selected' : ''}>${v}</option>`).join('');
  const colorOptions = COLORS.map(v => `<option value="${v}" ${v === c ? 'selected' : ''}>${v}</option>`).join('');
  return `<!doctype html>
<html><head><meta charset="utf-8"><title>Preview: ${username}</title>
<style>
  body { font-family: sans-serif; background: #222; color: #eee; padding: 20px; }
  form { margin-bottom: 20px; }
  input, select { font-size: 16px; padding: 4px 8px; }
  button { font-size: 16px; padding: 4px 12px; margin-left: 4px; }
  .row { display: flex; gap: 20px; flex-wrap: wrap; }
  .card { background: #333; padding: 10px; border-radius: 6px; }
  .card h3 { margin-top: 0; }
  img { background: repeating-conic-gradient(#444 0% 25%, #555 0% 50%) 50% / 20px 20px; max-width: 600px; }
  .timestamp { color: #888; font-size: 12px; }
</style>
</head><body>
<form method="get" action="/">
  <label>Username: <input name="username" value="${username || 'ryuu'}"></label>
  <label>Style: <select name="style">${styleOptions}</select></label>
  <label>Color: <select name="color">${colorOptions}</select></label>
  <button type="submit">Load</button>
  <button type="button" onclick="location.reload()">Refresh (re-render)</button>
</form>
<div class="row">
  <div class="card">
    <h3>Static (renderCharacterImage)</h3>
    <img id="render-png" alt="loading...">
  </div>
  <div class="card">
    <h3>Animated GIF (renderCharacterGif — what the bot posts by default)</h3>
    <img id="render-gif" alt="loading...">
  </div>
  <div class="card">
    <h3>Animated Video (renderCharacterVideo — the "format: video" option)</h3>
    <video id="render-video" autoplay loop muted controls style="max-width:600px"></video>
  </div>
</div>
<p class="timestamp">Rendered fresh on every page load/refresh — no caching. Loaded at ${new Date().toLocaleTimeString()}.</p>
<script>
// Each render is its own headless-Chromium + Ruffle capture (see
// renderCharacter.js) — genuinely heavy (documented history of this exact
// pipeline being sensitive to memory/CPU pressure under concurrency, e.g.
// the RENDER_SCALE/CAPTURE_SUPERSAMPLE regressions). Loading all three
// <img>/<video> src's at once fired 3 of these concurrently, which could
// blow past the AS3-side 25s gear-ready deadline under contention — this
// is what caused a real "video won't load" report (confirmed: GIF failed
// with the identical timeout in the same concurrent run; isolated
// sequential requests for the same character succeeded every time). Fetch
// one at a time instead, so only one heavy capture ever runs at once.
(async () => {
  const targets = [
    ['render-png', 'png'],
    ['render-gif', 'gif'],
    ['render-video', 'video'],
  ];
  for (const [elId, format] of targets) {
    const el = document.getElementById(elId);
    try {
      const res = await fetch(\`/render?username=${u}&style=${s}&color=${c}&format=\${format}&t=${Date.now()}\`);
      if (!res.ok) throw new Error(await res.text());
      const blob = await res.blob();
      el.src = URL.createObjectURL(blob);
    } catch (e) {
      el.replaceWith(document.createTextNode('render failed: ' + e.message));
    }
  }
})();
</script>
</body></html>`;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);

  if (url.pathname === '/render') {
    const username = url.searchParams.get('username');
    const style = url.searchParams.get('style');
    const color = url.searchParams.get('color');
    const format = ['gif', 'video'].includes(url.searchParams.get('format')) ? url.searchParams.get('format') : 'png';
    if (!username) { res.writeHead(400); res.end('missing username'); return; }
    try {
      const buf = format === 'gif' ? await renderCharacterGif(username, style, color)
        : format === 'video' ? await renderCharacterVideo(username, style, color)
        : await renderCharacterImage(username, style, color);
      const contentType = format === 'gif' ? 'image/gif' : format === 'video' ? 'video/mp4' : 'image/png';
      res.writeHead(200, {
        'Content-Type': contentType,
        'Cache-Control': 'no-store',
      });
      res.end(buf);
    } catch (e) {
      res.writeHead(500, { 'Content-Type': 'text/plain' });
      res.end('render failed: ' + e.message);
    }
    return;
  }

  if (url.pathname === '/') {
    const username = url.searchParams.get('username') || 'ryuu';
    const style = url.searchParams.get('style');
    const color = url.searchParams.get('color');
    res.writeHead(200, { 'Content-Type': 'text/html', 'Cache-Control': 'no-store' });
    res.end(page(username, style, color));
    return;
  }

  res.writeHead(404);
  res.end('not found');
});

server.listen(PORT, () => {
  console.log(`Preview server running at http://localhost:${PORT}/?username=ryuu`);
});

// AQW's gear/cosmetic SWFs each declare their own small frame-size RECT in
// their file header (independent of any AS3 drawing code — same header-level
// field FFDec/patch_stage_size.js patches on our own avatarRig.swf). Ruffle
// (and real Flash Player) clips a loaded child SWF's rendering to that
// declared rect. Most gear fits comfortably inside it, but some assets'
// artwork extends past their own declared bounds (confirmed on Ryuu's
// "Shadow of the Dragon" cape — its wing draws out to local x=-214, but the
// SWF's own header only declares 0..550 x 0..400), producing a hard flat
// clip edge instead of the shape's natural taper. Since this could affect
// any gear file, not just this one cape, patch EVERY external asset SWF's
// frame rect to the widest bounds its own header can represent (rather than
// guessing a fixed margin that might not be enough for some other asset) —
// applied once here at the proxy layer, so every consumer benefits without
// needing per-asset knowledge.
const zlib = require('zlib');

function patchSwfFrameRectToMax(buf) {
  const sig = buf.toString('ascii', 0, 3);
  if (sig !== 'CWS' && sig !== 'FWS') return buf;

  let body;
  try {
    body = sig === 'CWS' ? Buffer.concat([buf.slice(0, 8), zlib.inflateSync(buf.slice(8))]) : buf;
  } catch {
    return buf; // not a well-formed SWF body — leave untouched rather than throw
  }

  const bytes = body.slice(8);
  let bitPos = 0;
  function readBits(n) {
    let val = 0;
    for (let i = 0; i < n; i++) {
      const byteIdx = bitPos >> 3;
      const bitIdx = 7 - (bitPos & 7);
      val = (val << 1) | ((bytes[byteIdx] >> bitIdx) & 1);
      bitPos++;
    }
    return val;
  }
  function writeBits(value, n) {
    for (let i = n - 1; i >= 0; i--) {
      const bit = (value >> i) & 1;
      const byteIdx = bitPos >> 3;
      const bitIdx = 7 - (bitPos & 7);
      if (bit) bytes[byteIdx] |= (1 << bitIdx);
      else bytes[byteIdx] &= ~(1 << bitIdx);
      bitPos++;
    }
  }

  const nbits = readBits(5);
  if (nbits < 2) return buf; // degenerate header, don't touch

  // Widest symmetric range this file's own RECT field can represent, minus a
  // small safety margin so the two's-complement max-negative edge case never
  // rounds into the sign bit.
  const maxMagnitudeTwips = (1 << (nbits - 1)) - 20;

  bitPos = 5;
  const negTwips = ((1 << nbits) - maxMagnitudeTwips) & ((1 << nbits) - 1);
  writeBits(negTwips, nbits);        // xmin
  writeBits(maxMagnitudeTwips, nbits); // xmax
  writeBits(negTwips, nbits);        // ymin
  writeBits(maxMagnitudeTwips, nbits); // ymax

  if (sig === 'CWS') {
    return Buffer.concat([body.slice(0, 8), zlib.deflateSync(body.slice(8))]);
  }
  return body;
}

module.exports = { patchSwfFrameRectToMax };

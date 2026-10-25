// A synthetic, decodable "outdoor" photo that carries GPS metadata, so the
// journeys can prove the app strips it before upload. Drawn by the browser
// (no image tooling needed); the EXIF segment is synthetic (latitude "N",
// no real location).
import fs from 'node:fs';

const ascii = (s) => Array.from(s, (c) => c.charCodeAt(0));
const le16 = (v) => [v & 0xff, v >> 8];
const le32 = (v) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, v >>> 24];

/** APP1 EXIF with a camera make and a GPS sub-IFD (GPSLatitudeRef = N). */
function exifWithGps() {
  const entries = [[...le16(0x010f), ...le16(2), ...le32(4), ...ascii('Cam\0')]];
  const ifd0Size = 2 + (entries.length + 1) * 12 + 4;
  entries.push([...le16(0x8825), ...le16(4), ...le32(1), ...le32(8 + ifd0Size)]);
  const tiff = [...ascii('II'), ...le16(42), ...le32(8), ...le16(entries.length), ...entries.flat(), ...le32(0)];
  tiff.push(...le16(1), ...le16(0x0001), ...le16(2), ...le32(2), ...ascii('N\0'), 0, 0, ...le32(0));
  const payload = [...ascii('Exif\0\0'), ...tiff];
  return [0xff, 0xe1, (payload.length + 2) >> 8, (payload.length + 2) & 0xff, ...payload];
}

/** True when [bytes] still contain an EXIF block or a GPS IFD pointer. */
export function hasExifOrGps(bytes) {
  const b = Buffer.from(bytes);
  return b.includes(Buffer.from('Exif\0\0')) || b.includes(Buffer.from([0x25, 0x88, 0x04, 0x00]));
}

/** Writes the photo to [file] and returns its bytes. */
export async function makeSyntheticPhoto(page, file) {
  const dataUrl = await page.evaluate(() => {
    const c = document.createElement('canvas');
    c.width = 640;
    c.height = 480;
    const g = c.getContext('2d');
    const sky = g.createLinearGradient(0, 0, 0, 480);
    sky.addColorStop(0, '#5ab0f0');
    sky.addColorStop(1, '#d8f0ff');
    g.fillStyle = sky;
    g.fillRect(0, 0, 640, 480);
    g.fillStyle = '#3c8d3c';
    g.fillRect(0, 330, 640, 150);
    g.fillStyle = '#ffd34d';
    g.beginPath();
    g.arc(520, 90, 45, 0, Math.PI * 2);
    g.fill();
    return c.toDataURL('image/jpeg', 0.9);
  });
  const jpeg = Buffer.from(dataUrl.split(',')[1], 'base64');
  // Insert the EXIF segment right after SOI (FF D8).
  const out = Buffer.concat([jpeg.subarray(0, 2), Buffer.from(exifWithGps()), jpeg.subarray(2)]);
  if (!hasExifOrGps(out)) throw new Error('fixture lost its GPS metadata');
  fs.writeFileSync(file, out);
  return out;
}

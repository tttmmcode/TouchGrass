/**
 * Synthetic JPEG builder for the ops tests (unit and emulator) and the
 * revocation experiment's test photo (Phase 7F). Nothing in the app or the
 * deployed functions imports it.
 */
export const ascii = (s: string) => Array.from(s, (c) => c.charCodeAt(0));
export const seg = (marker: number, payload: number[]) =>
  [0xff, marker, (payload.length + 2) >> 8, (payload.length + 2) & 0xff, ...payload];
const le16 = (v: number) => [v & 0xff, v >> 8];
const le32 = (v: number) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, v >>> 24];

/** EXIF (little-endian) with a camera make, an orientation and, optionally,
 * a GPS sub-IFD holding a latitude reference. */
export function exifSegment(o: {orientation?: number; gps?: boolean}): number[] {
  const entries: number[][] = [];
  entries.push([...le16(0x010f), ...le16(2), ...le32(4), ...ascii("Cam\0")]);
  if (o.orientation) entries.push([...le16(0x0112), ...le16(3), ...le32(1), ...le16(o.orientation), 0, 0]);
  const ifd0Size = 2 + (entries.length + (o.gps ? 1 : 0)) * 12 + 4;
  if (o.gps) entries.push([...le16(0x8825), ...le16(4), ...le32(1), ...le32(8 + ifd0Size)]);
  const tiff = [...ascii("II"), ...le16(42), ...le32(8), ...le16(entries.length), ...entries.flat(), ...le32(0)];
  if (o.gps) tiff.push(...le16(1), ...le16(0x0001), ...le16(2), ...le32(2), ...ascii("N\0"), 0, 0, ...le32(0));
  return seg(0xe1, [...ascii("Exif\0\0"), ...tiff]);
}

const IMAGE_DATA = [0x00, 0x3f, 0x00, 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0xff, 0xd9];

export function jpeg(parts: {
  jfif?: boolean; exif?: number[]; xmp?: boolean; comment?: boolean; icc?: boolean; app5?: boolean;
} = {}): Uint8Array {
  return Uint8Array.from([
    0xff, 0xd8,
    ...(parts.jfif ? seg(0xe0, [...ascii("JFIF\0"), 1, 1, 0, 0, 1, 0, 1, 0, 0]) : []),
    ...(parts.exif ?? []),
    ...(parts.xmp ? seg(0xe1, ascii("http://ns.adobe.com/xap/1.0/\0<x:xmpmeta exif:GPSLatitude=\"30,15N\"/>")) : []),
    ...(parts.comment ? seg(0xfe, ascii("taken at 30.2,-97.7")) : []),
    ...(parts.icc ? seg(0xe2, [...ascii("ICC_PROFILE\0"), 1, 1, 9, 9]) : []),
    ...(parts.app5 ? seg(0xe5, ascii("vendor")) : []),
    ...seg(0xdb, [0, ...Array(64).fill(1)]), // DQT
    ...seg(0xc0, [8, 0, 16, 0, 16, 1, 1, 0x11, 0]), // SOF0 16×16, 1 component
    0xff, 0xda, 0x00, 0x08, 1, 1, 0, 0, 0x3f, 0, // SOS header
    ...IMAGE_DATA,
  ]);
}


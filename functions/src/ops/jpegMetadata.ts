/**
 * JPEG metadata inspection and lossless removal (Phase 6, N-7).
 *
 * Mirrors the app's upload-time stripping (lib/core/utils/image_metadata.dart)
 * for photos stored BEFORE that fix: metadata segments are dropped
 * byte-for-byte and the compressed image data (from SOS on) is copied
 * unchanged — no re-encoding, no quality loss, no image library.
 *
 * Kept: APP0 (JFIF), APP2 ICC colour profiles, APP14 (Adobe colour
 * transform) and all non-APP segments (tables, frame headers). Dropped:
 * APP1 (EXIF and XMP — both can hold GPS), APP3–APP13, APP15 and comments,
 * any APPn/comment between progressive scans, and everything after the
 * image's EOI marker — phones append a second (MPF) image with its own
 * EXIF/GPS, motion-photo video or vendor trailers there (Phase 7C).
 * If the photo relied on an EXIF orientation other than "normal", a minimal
 * EXIF segment carrying ONLY that orientation is written back, so it still
 * displays upright.
 *
 * Pure functions with full bounds checking: malformed input never throws
 * out of `inspectJpeg`; it is reported as "malformed" instead.
 */

export type JpegKind = "jpeg" | "not-jpeg" | "malformed" | "incomplete-header";

export interface JpegMetadata {
  kind: JpegKind;
  /** An EXIF APP1 segment is present. */
  exif: boolean;
  /** The only EXIF is a single Orientation tag (what stripping writes back
   * for rotated photos) — nothing else to remove. */
  exifOrientationOnly: boolean;
  /** The EXIF data has a non-empty GPS sub-IFD (or one that can't be read). */
  gps: boolean;
  /** An XMP APP1 segment is present (XMP can also carry GPS). */
  xmp: boolean;
  /** COM segments or other APPn segments that would be dropped. */
  otherMetadata: boolean;
  /** EXIF orientation (1–8); 1 when absent or unreadable. */
  orientation: number;
  /** Offset of the SOS marker (start of image data), when found. */
  sosOffset?: number;
  /** Offset just past the EOI marker — only when the whole image was read
   * (a header-only read never reaches it). */
  imageEnd?: number;
  /** Bytes follow EOI (appended images, video, vendor data). Only known
   * when imageEnd is. */
  trailingData: boolean;
  /** APPn or comment segments sit between scans. Only known when imageEnd is. */
  afterScanMetadata: boolean;
}

const EXIF_ID = "Exif\0\0";
const XMP_IDS = ["http://ns.adobe.com/xap/1.0/\0", "http://ns.adobe.com/xmp/extension/\0"];

function startsWith(b: Uint8Array, at: number, ascii: string): boolean {
  if (at + ascii.length > b.length) return false;
  for (let k = 0; k < ascii.length; k++) if (b[at + k] !== ascii.charCodeAt(k)) return false;
  return true;
}

interface Segment {
  marker: number;
  /** Offset of the 0xFF marker byte. */
  start: number;
  /** Offset just past the segment. */
  end: number;
}

/** Walks the segments before SOS. Returns null if the structure is wrong;
 * `incomplete` when the bytes end before SOS (e.g. a partial read). */
function walk(b: Uint8Array): {segments: Segment[]; sos?: number; incomplete?: boolean} | null {
  if (b.length < 2 || b[0] !== 0xff || b[1] !== 0xd8) return null;
  const segments: Segment[] = [];
  let i = 2;
  for (;;) {
    if (i + 1 >= b.length) return {segments, incomplete: true};
    if (b[i] !== 0xff) return null;
    const marker = b[i + 1];
    if (marker === 0xff) {
      i++; // fill byte
      continue;
    }
    if (marker === 0xda) return {segments, sos: i};
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
      segments.push({marker, start: i, end: i + 2});
      i += 2;
      continue;
    }
    if (marker === 0xd9) return null; // EOI before any image data
    if (i + 3 >= b.length) return {segments, incomplete: true};
    const length = (b[i + 2] << 8) | b[i + 3];
    if (length < 2) return null;
    if (i + 2 + length > b.length) return {segments, incomplete: true};
    segments.push({marker, start: i, end: i + 2 + length});
    i += 2 + length;
  }
}

/** The image from SOS to EOI: the byte ranges to keep (tables, scan data,
 * restart markers, EOI — never APPn/comments), whether APPn/comments sat
 * between scans, and the offset just past EOI. Null when EOI isn't reached
 * (a header-only read or a truncated file) or the structure is wrong. */
function walkImage(b: Uint8Array, sos: number):
    {parts: Array<[number, number]>; afterScanMetadata: boolean; end: number} | null {
  const parts: Array<[number, number]> = [];
  let afterScanMetadata = false;
  let i = sos;
  for (;;) {
    if (i + 1 >= b.length || b[i] !== 0xff) return null;
    const marker = b[i + 1];
    if (marker === 0xff) {
      i++; // fill byte
      continue;
    }
    if (marker === 0xd9) {
      parts.push([i, i + 2]);
      return {parts, afterScanMetadata, end: i + 2};
    }
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
      parts.push([i, i + 2]);
      i += 2;
      continue;
    }
    if (i + 3 >= b.length) return null;
    const end = i + 2 + ((b[i + 2] << 8) | b[i + 3]);
    if (end < i + 4 || end > b.length) return null;
    if ((marker >= 0xe0 && marker <= 0xef) || marker === 0xfe) afterScanMetadata = true;
    else parts.push([i, end]);
    i = end;
    if (marker === 0xda) {
      // Scan data runs to the next marker: an 0xFF that isn't a stuffed
      // 0xFF00 byte or a restart marker (RST0–7 belong to the scan).
      const start = i;
      while (i + 1 < b.length && !(b[i] === 0xff && b[i + 1] !== 0x00 && !(b[i + 1] >= 0xd0 && b[i + 1] <= 0xd7))) i++;
      if (i + 1 >= b.length) return null;
      parts.push([start, i]);
    }
  }
}

function concat(b: Uint8Array, ranges: Array<[number, number]>): Uint8Array {
  const out = new Uint8Array(ranges.reduce((n, [s, e]) => n + e - s, 0));
  let o = 0;
  for (const [s, e] of ranges) {
    out.set(b.subarray(s, e), o);
    o += e - s;
  }
  return out;
}

/** Orientation and GPS presence from an EXIF (TIFF) block. */
function readExif(b: Uint8Array, tiff: number, end: number):
    {orientation: number; gps: boolean; orientationOnly: boolean} {
  // Unreadable EXIF: assume the worst.
  const fail = {orientation: 1, gps: true, orientationOnly: false};
  if (tiff + 8 > end) return fail;
  const le = b[tiff] === 0x49 && b[tiff + 1] === 0x49;
  const be = b[tiff] === 0x4d && b[tiff + 1] === 0x4d;
  if (!le && !be) return fail;
  const u16 = (o: number) => (o + 2 > end ? -1 : le ? b[o] | (b[o + 1] << 8) : (b[o] << 8) | b[o + 1]);
  const u32 = (o: number) =>
    o + 4 > end ? -1 : le ?
      (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16)) + b[o + 3] * 0x1000000 :
      b[o] * 0x1000000 + ((b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]);
  if (u16(tiff + 2) !== 42) return fail;
  const ifd0 = tiff + u32(tiff + 4);
  const count = u16(ifd0);
  if (count < 0 || ifd0 + 2 + count * 12 > end) return fail;
  let orientation = 1;
  let gps = false;
  let onlyOrientationTag = count === 1;
  for (let k = 0; k < count; k++) {
    const e = ifd0 + 2 + k * 12;
    const tag = u16(e);
    if (tag !== 0x0112) onlyOrientationTag = false;
    if (tag === 0x0112) {
      const v = u16(e + 8);
      if (v >= 1 && v <= 8) orientation = v;
    } else if (tag === 0x8825) {
      const gpsIfd = tiff + u32(e + 8);
      const n = u16(gpsIfd);
      gps = n !== 0; // -1 (out of bounds) also counts as "may have GPS"
    }
  }
  // No further IFDs (thumbnail, EXIF sub-IFD) may follow.
  const orientationOnly = onlyOrientationTag && !gps && u32(ifd0 + 2 + count * 12) === 0;
  return {orientation, gps, orientationOnly};
}

export function inspectJpeg(b: Uint8Array): JpegMetadata {
  const base: JpegMetadata = {
    kind: "jpeg", exif: false, exifOrientationOnly: false, gps: false, xmp: false, otherMetadata: false, orientation: 1,
    trailingData: false, afterScanMetadata: false,
  };
  if (b.length < 2 || b[0] !== 0xff || b[1] !== 0xd8) return {...base, kind: "not-jpeg"};
  const w = walk(b);
  if (!w) return {...base, kind: "malformed"};
  const out = {...base, kind: (w.incomplete ? "incomplete-header" : "jpeg") as JpegKind, sosOffset: w.sos};
  const image = w.sos === undefined ? null : walkImage(b, w.sos);
  if (image) {
    out.imageEnd = image.end;
    out.trailingData = image.end < b.length;
    out.afterScanMetadata = image.afterScanMetadata;
  }
  for (const s of w.segments) {
    const payload = s.start + 4;
    if (s.marker === 0xe1) {
      if (startsWith(b, payload, EXIF_ID)) {
        // A second EXIF segment means more than the orientation is kept.
        out.exifOrientationOnly = !out.exif;
        out.exif = true;
        const e = readExif(b, payload + EXIF_ID.length, s.end);
        out.orientation = e.orientation;
        out.gps = out.gps || e.gps;
        out.exifOrientationOnly = out.exifOrientationOnly && e.orientationOnly;
      } else if (XMP_IDS.some((id) => startsWith(b, payload, id))) {
        out.xmp = true;
      } else {
        out.otherMetadata = true;
      }
    } else if (s.marker === 0xfe || (s.marker >= 0xe3 && s.marker <= 0xed) || s.marker === 0xef) {
      out.otherMetadata = true;
    } else if (s.marker === 0xe2 && !startsWith(b, payload, "ICC_PROFILE\0")) {
      out.otherMetadata = true;
    }
  }
  return out;
}

/** True when stripping would change the file. */
export function hasRemovableMetadata(m: JpegMetadata): boolean {
  return (m.exif && !m.exifOrientationOnly) || m.gps || m.xmp || m.otherMetadata ||
    m.trailingData || m.afterScanMetadata;
}

/** A minimal big-endian EXIF APP1 segment holding only an orientation. */
export function orientationOnlyExif(orientation: number): Uint8Array {
  if (!Number.isInteger(orientation) || orientation < 1 || orientation > 8) {
    throw new Error("orientation must be 1–8");
  }
  const tiff = [
    0x4d, 0x4d, 0x00, 0x2a, 0x00, 0x00, 0x00, 0x08, // "MM", 42, IFD0 at 8
    0x00, 0x01, // one entry
    0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, // Orientation, SHORT, count 1
    0x00, orientation, 0x00, 0x00, // value
    0x00, 0x00, 0x00, 0x00, // no next IFD
  ];
  const payload = [...Array.from(EXIF_ID, (c) => c.charCodeAt(0)), ...tiff];
  const len = payload.length + 2;
  return Uint8Array.from([0xff, 0xe1, len >> 8, len & 0xff, ...payload]);
}

/**
 * The same JPEG without removable metadata, or null if it can't be done
 * safely (not a complete, well-formed JPEG ending in EOI).
 */
export function stripJpegMetadata(b: Uint8Array): Uint8Array | null {
  const m = inspectJpeg(b);
  if (m.kind !== "jpeg" || m.sosOffset === undefined || m.imageEnd === undefined) return null;
  const w = walk(b)!;
  const image = walkImage(b, m.sosOffset)!;
  const parts: Uint8Array[] = [b.subarray(0, 2)];
  let orientationWritten = m.orientation === 1;
  const writeOrientation = () => {
    if (!orientationWritten) {
      parts.push(orientationOnlyExif(m.orientation));
      orientationWritten = true;
    }
  };
  for (const s of w.segments) {
    const payload = s.start + 4;
    const keep =
      s.marker === 0xe0 ||
      s.marker === 0xee ||
      (s.marker === 0xe2 && startsWith(b, payload, "ICC_PROFILE\0")) ||
      !((s.marker >= 0xe0 && s.marker <= 0xef) || s.marker === 0xfe);
    if (s.marker !== 0xe0) writeOrientation(); // right after JFIF, if any
    if (keep) parts.push(b.subarray(s.start, s.end));
  }
  writeOrientation();
  parts.push(concat(b, image.parts)); // up to EOI; nothing after it
  const total = parts.reduce((n, p) => n + p.length, 0);
  const out = new Uint8Array(total);
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
}

/**
 * Checks a stripped copy before it may replace [original]: a complete JPEG
 * ending at EOI, no GPS/XMP/other metadata, the same orientation, and the
 * compressed image data (SOS to EOI, without APPn/comments) byte-identical.
 * Returns the failure reason, or null when valid.
 */
export function validateStripped(original: Uint8Array, stripped: Uint8Array): string | null {
  const a = inspectJpeg(original);
  const b = inspectJpeg(stripped);
  if (b.kind !== "jpeg" || b.sosOffset === undefined || b.imageEnd === undefined ||
      a.sosOffset === undefined || a.imageEnd === undefined) return "not-a-complete-jpeg";
  if (b.gps || b.xmp || b.otherMetadata || b.trailingData || b.afterScanMetadata) return "metadata-remains";
  if (b.exif && (!b.exifOrientationOnly || b.orientation === 1)) return "unexpected-exif";
  if (b.orientation !== a.orientation) return "orientation-changed";
  const imgA = concat(original, walkImage(original, a.sosOffset)!.parts);
  const imgB = concat(stripped, walkImage(stripped, b.sosOffset)!.parts);
  if (imgA.length !== imgB.length) return "image-data-changed";
  for (let k = 0; k < imgA.length; k++) if (imgA[k] !== imgB[k]) return "image-data-changed";
  return null;
}

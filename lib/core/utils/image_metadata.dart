import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../constants/app_constants.dart';

/// Thrown when an image can't be read, so its metadata can't be removed.
class UnreadableImageException implements Exception {
  const UnreadableImageException();
}

/// Removes embedded metadata — above all EXIF/XMP GPS coordinates — from a
/// photo before it is uploaded (audit N-2, part of D-09). Phone cameras and
/// the gallery picker embed where a photo was taken; the app never uses that
/// metadata, and location may only be saved through the user's
/// "Save location with adventures" setting.
///
/// - JPEG with an EXIF orientation other than "normal": the rotation is
///   applied to the pixels first (so the photo doesn't display sideways once
///   the tag is gone), then it's re-encoded without any metadata.
/// - Other JPEGs: metadata segments are dropped byte-for-byte (lossless):
///   APP1 (EXIF, XMP), APP3–APP13, APP15 and comments, wherever they sit,
///   and everything after the image's end marker (appended MPF images,
///   motion-photo video). Kept: APP0 (JFIF), APP2 (ICC colour profile) and
///   APP14 (Adobe colour transform), which carry no location.
/// - Other formats (PNG, WebP…): re-encoded as JPEG without metadata.
///
/// Throws [UnreadableImageException] if the bytes can't be decoded at all,
/// rather than uploading a file whose metadata couldn't be checked.
/// CPU-heavy only in the re-encode cases; run it off the UI isolate.
Uint8List stripImageMetadata(Uint8List bytes) {
  if (!_isJpeg(bytes)) return _reencode(bytes);
  int? orientation;
  try {
    orientation = img.decodeJpgExif(bytes)?.imageIfd.orientation ?? 1;
  } catch (_) {
    orientation = null; // malformed EXIF: take the re-encode path
  }
  if (orientation != 1) return _reencode(bytes);
  return _dropJpegMetadataSegments(bytes) ?? _reencode(bytes);
}

bool _isJpeg(Uint8List b) => b.length > 3 && b[0] == 0xFF && b[1] == 0xD8;

Uint8List _reencode(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    decoded = null; // decoders can throw on malformed input
  }
  if (decoded == null) throw const UnreadableImageException();
  final upright = img.bakeOrientation(decoded)..exif = img.ExifData();
  return Uint8List.fromList(
    img.encodeJpg(upright, quality: AppConstants.imageQualityPercent),
  );
}

/// Copies the primary JPEG image without its metadata segments, and ends
/// the copy at its end-of-image (EOI) marker. Every marker segment is
/// walked — including tables between progressive scans — and compressed
/// scan data is copied unchanged. Nothing after EOI is copied: phones
/// append a second (MPF) image with its own EXIF/GPS, motion-photo video
/// or vendor trailers there (Phase 7C). Returns null if the marker
/// structure isn't what a JPEG should look like, or there is no EOI.
Uint8List? _dropJpegMetadataSegments(Uint8List b) {
  final out = BytesBuilder(copy: false)..add([0xFF, 0xD8]);
  var i = 2;
  while (i + 1 < b.length) {
    if (b[i] != 0xFF) return null;
    final marker = b[i + 1];
    if (marker == 0xFF) {
      i++; // fill byte
      continue;
    }
    if (marker == 0xD9) {
      out.add([0xFF, 0xD9]); // end of image: stop here
      return out.takeBytes();
    }
    final standalone = marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7);
    if (standalone) {
      out.add([0xFF, marker]);
      i += 2;
      continue;
    }
    if (i + 3 >= b.length) return null;
    final length = (b[i + 2] << 8) | b[i + 3];
    final end = i + 2 + length;
    if (length < 2 || end > b.length) return null;
    final isApp = marker >= 0xE0 && marker <= 0xEF;
    final keep =
        !(isApp || marker == 0xFE) ||
        marker == 0xE0 ||
        marker == 0xEE ||
        (marker == 0xE2 && _startsWithAscii(b, i + 4, 'ICC_PROFILE'));
    if (keep) out.add(Uint8List.sublistView(b, i, end));
    i = end;
    if (marker == 0xDA) {
      // Scan data runs to the next marker: an 0xFF that isn't a stuffed
      // 0xFF00 byte or a restart marker (RST0–7, which belong to the scan).
      final start = i;
      while (i + 1 < b.length &&
          !(b[i] == 0xFF &&
              b[i + 1] != 0x00 &&
              !(b[i + 1] >= 0xD0 && b[i + 1] <= 0xD7))) {
        i++;
      }
      if (i + 1 >= b.length) return null; // no EOI
      out.add(Uint8List.sublistView(b, start, i));
    }
  }
  return null;
}

/// Removes embedded metadata from a profile photo before upload (Phase 7C).
/// The result is always a PNG, because the avatar is stored as
/// `user_avatars/{uid}.png` with `image/png`.
///
/// - PNG: only the chunks needed to draw the image are copied (IHDR, PLTE,
///   IDAT, IEND, and the colour/transparency/density chunks tRNS, gAMA, cHRM,
///   sRGB, iCCP, sBIT, pHYs, bKGD). eXIf, text chunks (tEXt/zTXt/iTXt, which
///   carry XMP), tIME, animation and unknown chunks are dropped, and nothing
///   after IEND is copied.
/// - Anything else the decoder reads (JPEG, WebP, GIF…): rotated upright,
///   then re-encoded as a PNG without metadata.
///
/// The Settings crop already redraws the photo (no metadata survives that),
/// so this is the second line of defence, at the upload boundary.
/// Throws [UnreadableImageException] if the bytes can't be decoded.
Uint8List sanitizeProfilePhoto(Uint8List bytes) {
  final copied = _isPng(bytes) ? _keepPngImageChunks(bytes) : null;
  if (copied != null) return copied;
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) throw const UnreadableImageException();
  final upright = img.bakeOrientation(decoded)..exif = img.ExifData();
  return Uint8List.fromList(img.encodePng(upright));
}

const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

bool _isPng(Uint8List b) {
  if (b.length < 8) return false;
  for (var k = 0; k < 8; k++) {
    if (b[k] != _pngSignature[k]) return false;
  }
  return true;
}

const _pngImageChunks = {
  'IHDR', 'PLTE', 'IDAT', 'IEND', //
  'tRNS', 'gAMA', 'cHRM', 'sRGB', 'iCCP', 'sBIT', 'pHYs', 'bKGD',
};

/// The PNG with only [_pngImageChunks], ending at IEND; null if the chunk
/// structure is broken (the caller then re-encodes).
Uint8List? _keepPngImageChunks(Uint8List b) {
  final out = BytesBuilder(copy: false)..add(_pngSignature);
  var i = 8;
  var sawImage = false;
  while (i + 12 <= b.length) {
    final length = (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
    final end = i + 12 + length;
    if (length < 0 || end > b.length) return null;
    final type = String.fromCharCodes(b, i + 4, i + 8);
    if (_pngImageChunks.contains(type)) {
      out.add(Uint8List.sublistView(b, i, end));
      if (type == 'IDAT') sawImage = true;
    }
    if (type == 'IEND') return sawImage ? out.takeBytes() : null;
    i = end;
  }
  return null;
}

bool _startsWithAscii(Uint8List b, int offset, String s) {
  if (offset + s.length > b.length) return false;
  for (var k = 0; k < s.length; k++) {
    if (b[offset + k] != s.codeUnitAt(k)) return false;
  }
  return true;
}

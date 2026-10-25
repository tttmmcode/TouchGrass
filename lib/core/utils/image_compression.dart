import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../constants/app_constants.dart';

/// Downsizes [bytes] to fit within [AppConstants.imageMaxWidthPx] x
/// [AppConstants.imageMaxHeightPx] (preserving aspect ratio) and re-encodes
/// as JPEG at [AppConstants.imageQualityPercent] quality — the same bounds
/// [ImagePicker]'s gallery path already applies, so camera captures and
/// gallery picks produce consistently-sized uploads.
///
/// Runs on a background isolate via [compute]: decoding/re-encoding a
/// multi-megapixel photo is CPU-heavy enough to jank the camera UI otherwise.
/// Returns [bytes] unchanged if they can't be decoded, so a compression
/// failure never blocks a capture.
Future<Uint8List> compressJpeg(Uint8List bytes) =>
    compute(_compressJpeg, bytes);

Uint8List _compressJpeg(Uint8List bytes) {
  final rawDecoded = img.decodeImage(bytes);
  if (rawDecoded == null) return bytes;

  // Physically rotate pixels to match the EXIF orientation tag, then drop
  // all EXIF: encodeJpg *does* write an image's EXIF back out, which would
  // carry GPS coordinates into the upload (audit N-2). Uploads are also
  // stripped centrally in StorageService.uploadCompletionPhoto.
  final decoded = img.bakeOrientation(rawDecoded)..exif = img.ExifData();

  final scale = [
    1.0,
    AppConstants.imageMaxWidthPx / decoded.width,
    AppConstants.imageMaxHeightPx / decoded.height,
  ].reduce(min);

  final resized = scale < 1.0
      ? img.copyResize(decoded, width: (decoded.width * scale).round())
      : decoded;

  return Uint8List.fromList(
    img.encodeJpg(resized, quality: AppConstants.imageQualityPercent),
  );
}

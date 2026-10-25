// Phase 6 (Priority C): new uploads are upright and metadata-free for every
// EXIF orientation and the other formats the `image` package can decode;
// malformed input is refused or cleaned, never uploaded with metadata.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:touchgrass/core/utils/image_metadata.dart';

/// A 64×48 JPEG with GPS, a camera make and the given EXIF orientation.
Uint8List jpeg({required int orientation}) {
  final src = img.Image(width: 64, height: 48);
  img.fill(src, color: img.ColorRgb8(30, 140, 60));
  src.exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('N');
  src.exif.imageIfd['Make'] = img.IfdValueAscii('ProbeCam');
  src.exif.imageIfd.orientation = orientation;
  return Uint8List.fromList(img.encodeJpg(src));
}

void expectNoMetadata(Uint8List out) {
  final exif = img.decodeJpgExif(out);
  expect(exif == null || exif.isEmpty, isTrue, reason: 'no EXIF at all');
  expect(String.fromCharCodes(out), isNot(contains('ProbeCam')));
}

void main() {
  for (var o = 1; o <= 8; o++) {
    test(
      'EXIF orientation $o: displayed upright, GPS and camera data gone',
      () {
        final out = stripImageMetadata(jpeg(orientation: o));
        final decoded = img.decodeJpg(out)!;
        // Orientations 5–8 involve a 90° turn, so width and height swap.
        final turned = o >= 5;
        expect(decoded.width, turned ? 48 : 64);
        expect(decoded.height, turned ? 64 : 48);
        final exif = img.decodeJpgExif(out);
        expect(exif?.gpsIfd.isEmpty ?? true, isTrue);
        final orientation = exif?.imageIfd.orientation;
        expect(
          orientation == null || orientation == 1,
          isTrue,
          reason: 'no rotation tag left to apply twice',
        );
        expect(String.fromCharCodes(out), isNot(contains('ProbeCam')));
      },
    );
  }

  test('a GIF is re-encoded as a metadata-free JPEG', () {
    final src = img.Image(width: 20, height: 10);
    img.fill(src, color: img.ColorRgb8(200, 10, 10));
    final out = stripImageMetadata(Uint8List.fromList(img.encodeGif(src)));
    expect(out.sublist(0, 2), [0xFF, 0xD8]);
    expect(img.decodeJpg(out)!.width, 20);
    expectNoMetadata(out);
  });

  test('a TIFF carrying EXIF is re-encoded without it', () {
    final src = img.Image(width: 16, height: 16);
    src.exif.imageIfd['Make'] = img.IfdValueAscii('ProbeCam');
    src.exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('N');
    final out = stripImageMetadata(Uint8List.fromList(img.encodeTiff(src)));
    expect(out.sublist(0, 2), [0xFF, 0xD8]);
    expectNoMetadata(out);
  });

  test('a JPEG cut off inside its metadata is refused or cleaned — never '
      'passed through with GPS', () {
    final full = jpeg(orientation: 1);
    for (final cut in [6, 20, 40]) {
      final truncated = Uint8List.sublistView(full, 0, cut);
      try {
        final out = stripImageMetadata(truncated);
        expectNoMetadata(out);
      } on UnreadableImageException {
        // Refused: the user is asked for another photo.
      }
    }
  });

  test('random bytes and an empty file are refused', () {
    for (final bytes in [
      Uint8List(0),
      Uint8List.fromList(List.generate(500, (i) => (i * 37) % 256)),
      Uint8List.fromList([0xFF, 0xD8, 0xFF]),
    ]) {
      expect(
        () => stripImageMetadata(bytes),
        throwsA(isA<UnreadableImageException>()),
      );
    }
  });
}

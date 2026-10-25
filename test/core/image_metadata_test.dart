// Audit N-2 (part of D-09): photos must not carry embedded GPS (EXIF/XMP)
// into Storage, whatever the location setting is.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:touchgrass/core/utils/image_compression.dart';
import 'package:touchgrass/core/utils/image_metadata.dart';

/// A 64×48 JPEG carrying GPS + camera make, and optionally an orientation.
Uint8List jpegWithGps({int orientation = 1}) {
  final src = img.Image(width: 64, height: 48);
  img.fill(src, color: img.ColorRgb8(30, 140, 60));
  src.exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('N');
  src.exif.gpsIfd['GPSLongitudeRef'] = img.IfdValueAscii('W');
  src.exif.imageIfd['Make'] = img.IfdValueAscii('ProbeCam');
  if (orientation != 1) src.exif.imageIfd.orientation = orientation;
  return Uint8List.fromList(img.encodeJpg(src));
}

/// Inserts a raw segment right after SOI.
Uint8List withSegment(Uint8List jpeg, int marker, List<int> payload) {
  final len = payload.length + 2;
  return Uint8List.fromList([
    0xFF,
    0xD8,
    0xFF,
    marker,
    len >> 8,
    len & 0xFF,
    ...payload,
    ...jpeg.sublist(2),
  ]);
}

bool hasGps(Uint8List b) => img.decodeJpgExif(b)?.gpsIfd.isEmpty == false;

int sosIndex(Uint8List b) {
  for (var i = 2; i < b.length - 1; i++) {
    if (b[i] == 0xFF && b[i + 1] == 0xDA) return i;
  }
  return -1;
}

void main() {
  test('the test fixture really contains GPS (sanity check)', () {
    expect(hasGps(jpegWithGps()), isTrue);
  });

  test('upright JPEG: EXIF (GPS, camera make) removed losslessly', () {
    final input = jpegWithGps();
    final out = stripImageMetadata(input);
    expect(hasGps(out), isFalse);
    expect(img.decodeJpgExif(out)?.imageIfd['Make'], isNull);
    final decoded = img.decodeJpg(out)!;
    expect((decoded.width, decoded.height), (64, 48));
    // Image data from SOS onward is byte-identical: nothing re-encoded.
    expect(out.sublist(sosIndex(out)), input.sublist(sosIndex(input)));
  });

  test(
    'rotated JPEG: rotation applied to the pixels, then all metadata removed',
    () {
      final out = stripImageMetadata(
        jpegWithGps(orientation: 6),
      ); // 90° clockwise
      expect(hasGps(out), isFalse);
      final decoded = img.decodeJpg(out)!;
      expect(
        (decoded.width, decoded.height),
        (48, 64),
        reason: 'still displays upright',
      );
    },
  );

  test(
    'XMP (which can also hold GPS) is removed; the ICC colour profile is kept',
    () {
      final xmp = utf8.encode(
        'http://ns.adobe.com/xap/1.0/\u0000<x:xmpmeta exif:GPSLatitude="30,15N"/>',
      );
      final icc = [...ascii.encode('ICC_PROFILE'), 0, 1, 1, 9, 9, 9];
      final input = withSegment(
        withSegment(jpegWithGps(), 0xE2, icc),
        0xE1,
        xmp,
      );
      final out = stripImageMetadata(input);
      expect(
        latin1.decode(out, allowInvalid: true),
        isNot(contains('GPSLatitude')),
      );
      expect(latin1.decode(out, allowInvalid: true), contains('ICC_PROFILE'));
      expect(img.decodeJpg(out), isNotNull);
    },
  );

  test('comments are removed too', () {
    final input = withSegment(
      jpegWithGps(),
      0xFE,
      ascii.encode('taken at 30.2,-97.7'),
    );
    expect(
      latin1.decode(stripImageMetadata(input)),
      isNot(contains('30.2,-97.7')),
    );
  });

  test('a PNG is re-encoded as a metadata-free JPEG', () {
    final png = Uint8List.fromList(
      img.encodePng(img.Image(width: 10, height: 8)),
    );
    final out = stripImageMetadata(png);
    expect(out.sublist(0, 2), [0xFF, 0xD8]);
    expect(img.decodeJpgExif(out)?.isEmpty ?? true, isTrue);
  });

  test('unreadable bytes are refused, never uploaded unchecked', () {
    expect(
      () => stripImageMetadata(Uint8List.fromList([1, 2, 3, 4, 5])),
      throwsA(isA<UnreadableImageException>()),
    );
  });

  test(
    'compressJpeg (live camera path) no longer carries GPS forward',
    () async {
      expect(hasGps(await compressJpeg(jpegWithGps())), isFalse);
    },
  );
}

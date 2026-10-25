// Phase 7C: metadata hidden OUTSIDE the header. Phones append data after a
// JPEG's end-of-image marker — a second "MPF" image (depth map, preview)
// with its own EXIF/GPS, a motion-photo video, vendor trailers — and APPn
// segments can also sit between progressive scans. The lossless stripper
// used to copy everything from the first scan to the end of the file, so
// all of that went into Storage unchanged.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:touchgrass/core/utils/image_metadata.dart';

/// A 64×48 JPEG; with [gps], it carries GPS and the camera make "ProbeCam".
Uint8List jpeg({bool gps = false, int orientation = 1}) {
  final src = img.Image(width: 64, height: 48);
  img.fill(src, color: img.ColorRgb8(30, 140, 60));
  if (gps) {
    src.exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('N');
    src.exif.imageIfd['Make'] = img.IfdValueAscii('ProbeCam');
  }
  if (orientation != 1) src.exif.imageIfd.orientation = orientation;
  return Uint8List.fromList(img.encodeJpg(src));
}

Uint8List cat(List<List<int>> parts) =>
    Uint8List.fromList([for (final p in parts) ...p]);

/// An APP1 segment holding [text].
List<int> app1(String text) {
  final payload = latin1.encode(text);
  final len = payload.length + 2;
  return [0xFF, 0xE1, len >> 8, len & 0xFF, ...payload];
}

String asText(Uint8List b) => latin1.decode(b, allowInvalid: true);

void expectEndsAtEoi(Uint8List out) {
  expect(out.sublist(out.length - 2), [0xFF, 0xD9]);
}

void main() {
  test('a second (MPF) image with GPS appended after EOI is not uploaded', () {
    final primary = jpeg();
    final input = cat([primary, jpeg(gps: true)]);
    expect(asText(input), contains('ProbeCam'), reason: 'fixture sanity');
    final out = stripImageMetadata(input);
    expect(asText(out), isNot(contains('ProbeCam')));
    expect(out.length, lessThanOrEqualTo(primary.length));
    expectEndsAtEoi(out);
    expect(img.decodeJpg(out)!.width, 64);
  });

  test('a motion-photo video / vendor trailer after EOI is not uploaded', () {
    final input = cat([
      jpeg(gps: true),
      latin1.encode('\u0000\u0000\u0000\u0018ftypmp42'),
      latin1.encode('©xyz+30.2672-097.7431/'),
      latin1.encode('SEFHMotion_Photo_Data'),
    ]);
    final out = stripImageMetadata(input);
    final text = asText(out);
    expect(text, isNot(contains('xyz+30.2672')));
    expect(text, isNot(contains('ftypmp42')));
    expect(text, isNot(contains('Motion_Photo')));
    expect(text, isNot(contains('ProbeCam')));
    expectEndsAtEoi(out);
  });

  test('a rotated photo with a trailer: re-encoded, trailer gone', () {
    final input = cat([jpeg(gps: true, orientation: 6), jpeg(gps: true)]);
    final out = stripImageMetadata(input);
    expect(asText(out), isNot(contains('ProbeCam')));
    final decoded = img.decodeJpg(out)!;
    expect((decoded.width, decoded.height), (48, 64));
  });

  test('an APP1 segment after the image data (between scans) is dropped', () {
    final base = jpeg();
    // Insert an EXIF-like APP1 just before the final EOI marker.
    final input = cat([
      base.sublist(0, base.length - 2),
      app1('Exif\u0000\u0000ProbeCam GPS 30.2672,-97.7431'),
      [0xFF, 0xD9],
    ]);
    final out = stripImageMetadata(input);
    expect(asText(out), isNot(contains('ProbeCam')));
    expect(asText(out), isNot(contains('30.2672')));
    expectEndsAtEoi(out);
    expect(img.decodeJpg(out), isNotNull);
  });

  test('image data, stuffed 0xFF00 bytes and restart markers are copied '
      'unchanged up to EOI', () {
    // A minimal, structurally valid JPEG: SOI, SOS (empty header payload),
    // scan bytes containing FF00 and RST0, EOI, then a trailer.
    final scan = [0x12, 0xFF, 0x00, 0x34, 0xFF, 0xD0, 0x56];
    final input = cat([
      [0xFF, 0xD8],
      app1('Exif\u0000\u0000ProbeCam'),
      [0xFF, 0xDA, 0x00, 0x02],
      scan,
      [0xFF, 0xD9],
      latin1.encode('TRAILER-WITH-GPS'),
    ]);
    // Not decodable as a real picture, so only the structural copy is
    // checked here: it must come from the lossless path or be refused.
    try {
      final out = stripImageMetadata(input);
      expect(out, [
        0xFF, 0xD8, 0xFF, 0xDA, 0x00, 0x02, ...scan, 0xFF, 0xD9, //
      ]);
    } on UnreadableImageException {
      fail('a structurally valid JPEG must be copied losslessly');
    }
  });

  test('a JPEG whose scan never reaches EOI is re-encoded or refused — '
      'never copied with whatever follows', () {
    final full = jpeg(gps: true);
    final noEoi = full.sublist(0, full.length - 2);
    try {
      final out = stripImageMetadata(
        cat([noEoi, latin1.encode('ProbeCam-trailer')]),
      );
      expect(asText(out), isNot(contains('ProbeCam')));
    } on UnreadableImageException {
      // Refused: the user is asked for another photo.
    }
  });

  group('profile photos (sanitizeProfilePhoto)', () {
    List<int> chunk(String type, List<int> data) {
      final len = data.length;
      return [
        len >> 24, (len >> 16) & 0xFF, (len >> 8) & 0xFF, len & 0xFF, //
        ...ascii.encode(type), ...data, 0, 0, 0, 0, // CRC isn't checked here
      ];
    }

    /// Inserts [chunks] right after IHDR (8-byte signature + 25-byte IHDR).
    Uint8List pngWith(List<List<int>> chunks, {List<int> trailer = const []}) {
      final png = img.encodePng(img.Image(width: 8, height: 8));
      return cat([png.sublist(0, 33), ...chunks, png.sublist(33), trailer]);
    }

    test('drops eXIf, tEXt, iTXt, zTXt and tIME chunks; keeps the image', () {
      final input = pngWith([
        chunk('eXIf', latin1.encode('MM\u0000*ProbeCam GPS')),
        chunk('tEXt', latin1.encode('Location\u000030.2672,-97.7431')),
        chunk(
          'iTXt',
          latin1.encode(
            'XML:com.adobe.xmp\u0000\u0000\u0000\u0000\u0000<x:xmpmeta GPSLatitude/>',
          ),
        ),
        chunk('zTXt', latin1.encode('Comment\u0000\u0000xx')),
        chunk('tIME', [7, 234, 10, 19, 12, 0, 0]),
        chunk('pHYs', [0, 0, 11, 19, 0, 0, 11, 19, 1]),
      ], trailer: latin1.encode('ProbeCam-after-IEND'));
      final out = sanitizeProfilePhoto(input);
      final text = asText(out);
      for (final leak in [
        'ProbeCam',
        '30.2672',
        'GPSLatitude',
        'tIME',
        'zTXt',
      ]) {
        expect(text, isNot(contains(leak)), reason: leak);
      }
      expect(text, contains('pHYs'), reason: 'harmless display chunk kept');
      expect(out.sublist(out.length - 8, out.length - 4), ascii.encode('IEND'));
      expect(img.decodePng(out)!.width, 8);
    });

    test('a JPEG avatar (with GPS) becomes a metadata-free PNG', () {
      final out = sanitizeProfilePhoto(jpeg(gps: true, orientation: 6));
      expect(out.sublist(1, 4), ascii.encode('PNG'));
      expect(asText(out), isNot(contains('ProbeCam')));
      final decoded = img.decodePng(out)!;
      expect((decoded.width, decoded.height), (48, 64), reason: 'upright');
    });

    test('unreadable bytes are refused', () {
      expect(
        () => sanitizeProfilePhoto(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<UnreadableImageException>()),
      );
    });
  });
}

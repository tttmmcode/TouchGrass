// Phase 7G: the remaining synthetic cases for upload-time metadata removal —
// an EXIF thumbnail (a second, small JPEG inside the EXIF block, which can
// show the photo's content and has carried its own GPS on some phones),
// data after a PNG's IEND, a rotated JPEG used as a profile photo, a HEIC
// file the decoder can't read, and a large photo staying upright and
// complete after cleaning.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:touchgrass/core/utils/image_metadata.dart';

Uint8List _jpeg(int w, int h, {int orientation = 1}) {
  final src = img.Image(width: w, height: h);
  img.fill(src, color: img.ColorRgb8(30, 140, 60));
  src.exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('N');
  if (orientation != 1) src.exif.imageIfd.orientation = orientation;
  return Uint8List.fromList(img.encodeJpg(src));
}

List<int> _le16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> _le32(int v) => [
  v & 0xFF,
  (v >> 8) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 24) & 0xFF,
];

/// An EXIF APP1 segment whose IFD1 embeds [thumbnail] (JPEGInterchangeFormat).
List<int> _exifWithThumbnail(List<int> thumbnail) {
  // TIFF: header (8) | IFD0: 0 entries + next-IFD offset (6) | IFD1: 2 entries (2 + 24 + 4) | thumbnail
  const ifd1At = 8 + 6;
  const thumbAt = ifd1At + 2 + 2 * 12 + 4;
  final tiff = <int>[
    ...latin1.encode('II'), ..._le16(42), ..._le32(8),
    ..._le16(0), ..._le32(ifd1At), // IFD0: no entries, then IFD1
    ..._le16(2),
    ..._le16(0x0201),
    ..._le16(4),
    ..._le32(1),
    ..._le32(thumbAt), // JPEGInterchangeFormat
    ..._le16(0x0202),
    ..._le16(4),
    ..._le32(1),
    ..._le32(thumbnail.length), // …Length
    ..._le32(0),
    ...thumbnail,
  ];
  final payload = [...latin1.encode('Exif\u0000\u0000'), ...tiff];
  final len = payload.length + 2;
  return [0xFF, 0xE1, len >> 8, len & 0xFF, ...payload];
}

bool _contains(List<int> hay, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= hay.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

void main() {
  test(
    'an EXIF thumbnail (a second picture inside the metadata) is removed',
    () {
      final thumbnail = _jpeg(8, 6);
      final main = _jpeg(64, 48);
      // SOI + the thumbnail-carrying EXIF + the rest of the main image.
      final withThumb = Uint8List.fromList([
        ...main.sublist(0, 2),
        ..._exifWithThumbnail(thumbnail),
        ...main.sublist(2),
      ]);
      expect(_contains(withThumb, thumbnail), isTrue, reason: 'fixture sanity');

      final out = stripImageMetadata(withThumb);
      expect(
        _contains(out, thumbnail.sublist(2, 40)),
        isFalse,
        reason: 'thumbnail bytes gone',
      );
      expect(latin1.decode(out, allowInvalid: true), isNot(contains('Exif')));
      final decoded = img.decodeJpg(out)!;
      expect([decoded.width, decoded.height], [64, 48]);
    },
  );

  test('a profile PNG with data after IEND: the trailer is not uploaded', () {
    final src = img.Image(width: 16, height: 16);
    img.fill(src, color: img.ColorRgb8(200, 30, 30));
    final png = img.encodePng(src);
    final trailer = latin1.encode('GPSLatitude=30.2671 hidden-after-IEND');
    final out = sanitizeProfilePhoto(Uint8List.fromList([...png, ...trailer]));
    expect(
      latin1.decode(out, allowInvalid: true),
      isNot(contains('hidden-after-IEND')),
    );
    expect(out.sublist(out.length - 8, out.length - 4), latin1.encode('IEND'));
    expect(img.decodePng(out)!.width, 16);
  });

  test(
    'a rotated JPEG used as a profile photo becomes an upright, metadata-free PNG',
    () {
      final out = sanitizeProfilePhoto(_jpeg(64, 48, orientation: 6));
      expect(out.sublist(1, 4), latin1.encode('PNG'));
      final decoded = img.decodePng(out)!;
      expect(
        [decoded.width, decoded.height],
        [48, 64],
        reason: '90° turn applied to the pixels',
      );
      expect(latin1.decode(out, allowInvalid: true), isNot(contains('Exif')));
    },
  );

  test(
    'a HEIC file (not decodable here) is refused, never uploaded unchecked',
    () {
      final heic = Uint8List.fromList([
        0,
        0,
        0,
        24,
        ...latin1.encode('ftypheic'),
        0,
        0,
        0,
        0,
        ...latin1.encode('mif1heic'),
        ...List.filled(64, 7),
      ]);
      expect(
        () => stripImageMetadata(heic),
        throwsA(isA<UnreadableImageException>()),
      );
      expect(
        () => sanitizeProfilePhoto(heic),
        throwsA(isA<UnreadableImageException>()),
      );
    },
  );

  test('a large rotated photo stays complete and upright after cleaning', () {
    final out = stripImageMetadata(_jpeg(1600, 1200, orientation: 8));
    final decoded = img.decodeJpg(out)!;
    expect([decoded.width, decoded.height], [1200, 1600]);
    expect(out.sublist(out.length - 2), [0xFF, 0xD9]);
    expect(
      latin1.decode(out, allowInvalid: true),
      isNot(contains('GPSLatitude')),
    );
  });
}

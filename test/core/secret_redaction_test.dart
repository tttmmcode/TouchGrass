// Phase 7C: download-token URLs must not reach crash reports or logs — a
// token URL opens the photo for anyone, whatever the Storage rules say.

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/core/utils/secret_redaction.dart';

const _url =
    'https://firebasestorage.googleapis.com/v0/b/touchgrass-today.firebasestorage.app'
    '/o/completion_photos%2Fu1%2F2026-01-01.jpg?alt=media&token=1b2c3d4e-aaaa-4bbb-8ccc-123456789abc';
const _secret = '1b2c3d4e-aaaa-4bbb-8ccc-123456789abc';

void main() {
  test('removes the token, keeps the rest of the URL readable', () {
    final out = redactDownloadTokens('failed: $_url (403)');
    expect(out, isNot(contains(_secret)));
    expect(out, contains('alt=media&token=REDACTED'));
    expect(out, endsWith(' (403)'));
  });

  test('every token, in any position or encoding', () {
    const text =
        '?token=aaa1 &token=bbb2 &amp;token=ccc3 %3Ftoken%3Dddd4 TOKEN=eee5';
    final out = redactDownloadTokens(text);
    for (final s in ['aaa1', 'bbb2', 'ccc3', 'ddd4', 'eee5']) {
      expect(out, isNot(contains(s)), reason: s);
    }
  });

  test('text without a token is returned unchanged; the error object kept', () {
    const plain = 'StorageException: object-not-found';
    expect(redactDownloadTokens(plain), plain);
    final e = Exception(plain);
    expect(identical(redactErrorForReport(e), e), isTrue);
  });

  test(
    "an image-load error's URL is redacted (the real Flutter exception)",
    () {
      final e = NetworkImageLoadException(
        statusCode: 403,
        uri: Uri.parse(_url),
      );
      final r = redactErrorForReport(e);
      expect(r, isA<RedactedError>());
      expect(r.toString(), isNot(contains(_secret)));
      expect(r.toString(), contains('NetworkImageLoadException'));
      expect(r.toString(), contains('403'));
    },
  );

  test('FlutterErrorDetails: exception, context and extra information', () {
    final details = FlutterErrorDetails(
      exception: NetworkImageLoadException(
        statusCode: 404,
        uri: Uri.parse(_url),
      ),
      stack: StackTrace.current,
      library: 'image resource service',
      context: ErrorDescription('resolving an image stream for $_url'),
      informationCollector: () => [
        DiagnosticsProperty<String>('Image provider', 'NetworkImage("$_url")'),
      ],
    );
    final out = redactFlutterErrorDetails(details);
    expect(out.exceptionAsString(), isNot(contains(_secret)));
    expect(out.context.toString(), isNot(contains(_secret)));
    final info = out.informationCollector!().map((n) => n.toString()).join();
    expect(info, isNot(contains(_secret)));
    expect(info, contains('Image provider'));
    expect(out.library, 'image resource service');
    expect(out.stack, details.stack);
  });
}

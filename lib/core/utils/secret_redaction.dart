import 'package:flutter/foundation.dart';

/// Removes Firebase Storage download tokens from text bound for crash
/// reports and logs (Phase 7C).
///
/// A download URL's `token` works like a password for that one photo:
/// anyone holding the URL can open it, whatever the Storage rules say.
/// Flutter's image-load errors include the full URL, so without this an
/// unhandled image error would put a private photo's link into Crashlytics.
String redactDownloadTokens(String text) => text.replaceAllMapped(
  RegExp(
    r'''((?:^|[?&\s;,(]|%3F|%26)token(?:=|%3D))[^&\s"'<>)\]]+''',
    caseSensitive: false,
  ),
  (m) => '${m[1]}REDACTED',
);

/// An error whose text had a download token removed. Keeps the original
/// type name so reports still group sensibly.
class RedactedError implements Exception {
  const RedactedError(this.originalType, this.message);

  final String originalType;
  final String message;

  @override
  String toString() => '$originalType (redacted): $message';
}

/// [error] itself when its text holds no download token; otherwise a
/// [RedactedError] copy.
Object redactErrorForReport(Object error) {
  final text = error.toString();
  final clean = redactDownloadTokens(text);
  return clean == text ? error : RedactedError('${error.runtimeType}', clean);
}

/// [details] with download tokens removed from the exception, the context
/// and the extra information (which, for image errors, names the image
/// provider — including its URL).
FlutterErrorDetails redactFlutterErrorDetails(FlutterErrorDetails details) {
  final collector = details.informationCollector;
  final context = details.context;
  return FlutterErrorDetails(
    exception: redactErrorForReport(details.exception),
    stack: details.stack,
    library: details.library,
    silent: details.silent,
    context: context == null
        ? null
        : ErrorDescription(redactDownloadTokens(context.toDescription())),
    informationCollector: collector == null
        ? null
        : () => [
            for (final node in collector())
              ErrorDescription(redactDownloadTokens(node.toString())),
          ],
  );
}

/// Sealed hierarchy of application-level exceptions.
///
/// All repository methods return [Result<T>] wrapping these types —
/// widgets and providers never receive raw [Exception] or [FirebaseException].
sealed class AppException implements Exception {
  const AppException({required this.message, this.cause});

  final String message;

  /// The underlying platform or library exception that caused this failure.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

// ── Authentication ─────────────────────────────────────────────────────────

final class AuthException extends AppException {
  const AuthException({required super.message, super.cause});

  factory AuthException.cancelled() =>
      const AuthException(message: 'Sign-in was cancelled.');

  factory AuthException.providerError(Object cause) =>
      AuthException(message: 'Authentication provider error.', cause: cause);

  factory AuthException.noUser() =>
      const AuthException(message: 'No authenticated user found.');

  factory AuthException.sessionExpired() =>
      const AuthException(message: 'Your session has expired. Please sign in again.');

  factory AuthException.accountDisabled() =>
      const AuthException(message: 'This account has been disabled.');
}

// ── Data / Firestore ───────────────────────────────────────────────────────

final class DataException extends AppException {
  const DataException({required super.message, super.cause});

  factory DataException.notFound(String resource) =>
      DataException(message: '$resource not found.');

  factory DataException.permissionDenied() =>
      const DataException(message: 'You don\'t have permission to perform this action.');

  factory DataException.unavailable(Object cause) =>
      DataException(message: 'Data service temporarily unavailable.', cause: cause);

  factory DataException.parse(Object cause) =>
      DataException(message: 'Failed to parse server data.', cause: cause);

  factory DataException.alreadyExists(String resource) =>
      DataException(message: '$resource already exists.');
}

// ── Network ────────────────────────────────────────────────────────────────

final class NetworkException extends AppException {
  const NetworkException({required super.message, super.cause});

  factory NetworkException.noConnection() =>
      const NetworkException(message: 'No internet connection.');

  factory NetworkException.timeout() =>
      const NetworkException(message: 'Request timed out. Please try again.');

  factory NetworkException.server(int statusCode) =>
      NetworkException(message: 'Server error ($statusCode). Please try again later.');
}

// ── AI Verification ────────────────────────────────────────────────────────

final class VerificationException extends AppException {
  const VerificationException({required super.message, super.cause});

  factory VerificationException.lowConfidence(double confidence) =>
      VerificationException(
        message:
            'Image didn\'t clearly show the challenge (${(confidence * 100).toStringAsFixed(0)}% match).',
      );

  factory VerificationException.unrelated() =>
      const VerificationException(
        message: 'The image doesn\'t appear to match this challenge.',
      );

  factory VerificationException.apiError(Object cause) =>
      VerificationException(message: 'Verification service error.', cause: cause);

  factory VerificationException.timeout() =>
      const VerificationException(message: 'Verification timed out. Please try again.');
}

// ── Storage ────────────────────────────────────────────────────────────────

final class StorageException extends AppException {
  const StorageException({required super.message, super.cause});

  factory StorageException.uploadFailed(Object cause) =>
      StorageException(message: 'Photo upload failed.', cause: cause);

  factory StorageException.downloadFailed(Object cause) =>
      StorageException(message: 'Failed to load image.', cause: cause);

  factory StorageException.fileTooLarge() =>
      const StorageException(message: 'Photo is too large. Please use a smaller image.');
}

// ── Unexpected ────────────────────────────────────────────────────────────

/// Wraps anything that isn't an [AppException]. Use Crashlytics to log these.
final class UnexpectedException extends AppException {
  const UnexpectedException({required super.message, required Object super.cause});

  factory UnexpectedException.wrap(Object cause) =>
      UnexpectedException(message: 'An unexpected error occurred.', cause: cause);
}

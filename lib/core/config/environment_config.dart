/// Compile-time environment configuration.
///
/// Values are injected via --dart-define at build time, e.g.:
///   flutter build web --dart-define=ENVIRONMENT=production
///
/// Every value here is compiled into the client bundle and is therefore
/// PUBLIC. Never add a secret (API keys with billing, service credentials)
/// here or pass one via --dart-define / --dart-define-from-file: the Gemini
/// key that used to be read here shipped inside the public web bundle
/// (audit D-06). AI calls belong behind a server (Cloud Functions + Secret
/// Manager); tool/check_web_bundle_secrets.mjs guards web builds.
abstract final class EnvironmentConfig {
  /// Web Push certificate key pair's public key, from Firebase Console →
  /// Project Settings → Cloud Messaging → Web Push certificates. Only
  /// meaningful on web (see KNOWN_BUGS.md B4) — empty by default, which
  /// keeps today's safe no-op behavior (NotificationService.getToken()
  /// returns null on web) until a real key is supplied.
  static const String fcmVapidKey = String.fromEnvironment(
    'FCM_VAPID_KEY',
    defaultValue: '',
  );

  static const String _env = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'development',
  );

  static bool get isProduction => _env == 'production';
  static bool get isStaging => _env == 'staging';
  static bool get isDevelopment => !isProduction && !isStaging;

  /// True when a web-push VAPID key has been provided at build time.
  static bool get fcmVapidConfigured => fcmVapidKey.isNotEmpty;
}

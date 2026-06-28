/// Compile-time environment configuration.
///
/// Values are injected via --dart-define at build time:
///   flutter run  --dart-define=GEMINI_API_KEY=AIza...
///   flutter build apk --dart-define=GEMINI_API_KEY=$KEY --dart-define=ENVIRONMENT=production
///
/// In CI/CD, set GEMINI_API_KEY as a secret environment variable and pass it
/// through --dart-define. NEVER hardcode a real key here.
abstract final class EnvironmentConfig {
  static const String geminiApiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  static const String _env =
      String.fromEnvironment('ENVIRONMENT', defaultValue: 'development');

  static bool get isProduction => _env == 'production';
  static bool get isStaging => _env == 'staging';
  static bool get isDevelopment => !isProduction && !isStaging;

  /// True when a Gemini API key has been provided at build time.
  static bool get geminiConfigured => geminiApiKey.isNotEmpty;
}

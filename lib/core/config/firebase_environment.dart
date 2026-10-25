import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import '../../firebase_options_dev.dart';

/// Which Firebase backend this build talks to (Phase 8).
enum FirebaseEnv {
  /// `touchgrass-today` — real users. The only environment with Analytics,
  /// Performance Monitoring and Crashlytics.
  production,

  /// The isolated development project (`touchgrass-dev-n7j3f`): synthetic
  /// data only, no billing, no Analytics.
  development,

  /// The local Firebase Emulator Suite under a `demo-` project id, which
  /// can never reach a real project.
  emulator,
}

/// A build whose environment settings are missing, unknown or unsafe.
/// Startup stops instead of guessing a backend.
class FirebaseEnvironmentError extends Error {
  FirebaseEnvironmentError(this.message);

  final String message;

  @override
  String toString() => 'FirebaseEnvironmentError: $message';
}

/// Selects the Firebase project explicitly, failing closed.
///
/// - `--dart-define=TG_FIREBASE_ENV=production|development|emulator`
/// - `--dart-define=TG_EMULATOR_HOST=<host>` (emulator only; default
///   `localhost`; the Android emulator reaches the host at `10.0.2.2`)
///
/// Without TG_FIREBASE_ENV, a RELEASE build is production (store and web
/// release builds are unchanged) and a debug or profile build uses the
/// emulators — so `flutter run` can no longer write to production by
/// accident (before Phase 8 it always did). A release build can't select
/// the emulators.
abstract final class FirebaseEnvironment {
  static const String _raw = String.fromEnvironment('TG_FIREBASE_ENV');

  static const String emulatorHost = String.fromEnvironment(
    'TG_EMULATOR_HOST',
    defaultValue: 'localhost',
  );

  /// The emulator project id. `demo-` ids are never backed by a real
  /// project, so emulator traffic can't reach one.
  static const String emulatorProjectId = 'demo-touchgrass-dev';

  static const int authPort = 9099;
  static const int firestorePort = 8080;
  static const int storagePort = 9199;
  static const int functionsPort = 5001;

  /// Resolves [raw] (the TG_FIREBASE_ENV value) for a build in
  /// [releaseMode]. Throws [FirebaseEnvironmentError] when it's unknown or
  /// unsafe.
  static FirebaseEnv resolve({
    String raw = _raw,
    bool releaseMode = kReleaseMode,
  }) {
    switch (raw) {
      case '':
        return releaseMode ? FirebaseEnv.production : FirebaseEnv.emulator;
      case 'production':
        return FirebaseEnv.production;
      case 'development':
        return FirebaseEnv.development;
      case 'emulator':
        if (releaseMode) {
          throw FirebaseEnvironmentError(
            'A release build cannot use the emulators (TG_FIREBASE_ENV=emulator).',
          );
        }
        return FirebaseEnv.emulator;
      default:
        throw FirebaseEnvironmentError(
          'Unknown TG_FIREBASE_ENV "$raw": use production, development or emulator.',
        );
    }
  }

  static FirebaseEnv? _current;

  /// This build's environment (resolved once).
  static FirebaseEnv get current => _current ??= resolve();

  /// Analytics, Performance Monitoring and Crashlytics run in production
  /// only: development and emulator activity never reaches the production
  /// dashboards (Phase 8; before, debug runs sent analytics to production).
  static bool get telemetryEnabled => current == FirebaseEnv.production;

  static bool get usesEmulators => current == FirebaseEnv.emulator;

  /// The options for [env] on this platform. Each environment's project id
  /// is checked, so a wrong file can't silently point a build elsewhere.
  static FirebaseOptions optionsFor(FirebaseEnv env) {
    final options = switch (env) {
      FirebaseEnv.production => DefaultFirebaseOptions.currentPlatform,
      FirebaseEnv.development => DevFirebaseOptions.currentPlatform,
      FirebaseEnv.emulator => emulatorOptions,
    };
    final expected = expectedProjectId(env);
    if (options.projectId != expected) {
      throw FirebaseEnvironmentError(
        '$env options name project "${options.projectId}", expected "$expected".',
      );
    }
    return options;
  }

  static String expectedProjectId(FirebaseEnv env) => switch (env) {
    FirebaseEnv.production => 'touchgrass-today',
    FirebaseEnv.development => DevFirebaseOptions.projectId,
    FirebaseEnv.emulator => emulatorProjectId,
  };

  /// Placeholder identifiers: the emulators accept any.
  static const FirebaseOptions emulatorOptions = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: emulatorProjectId,
    authDomain: '$emulatorProjectId.firebaseapp.com',
    storageBucket: '$emulatorProjectId.appspot.com',
  );

  /// Fails closed unless Auth really uses the emulator (Phase 8, found in
  /// the browser run). On web, FlutterFire restores a saved session while
  /// Firebase starts, before the app can point Auth at the emulator. That
  /// restore goes to the real Auth service, and the emulator connection then
  /// fails silently, so every later sign-in would go there too.
  /// [usesEmulator] is the SDK's own answer (null: unknown, e.g. on mobile).
  static void checkAuthEmulatorConnected({required bool? usesEmulator}) {
    if (usesEmulator == false) {
      throw FirebaseEnvironmentError(
        'Auth is not using the emulator: a sign-in saved by an earlier build '
        'was restored first. That sign-in has been cleared; reload the page.',
      );
    }
  }

  /// A short label for non-production builds (shown in a banner), or null.
  static String? get label => switch (current) {
    FirebaseEnv.production => null,
    FirebaseEnv.development => 'DEV',
    FirebaseEnv.emulator => 'EMULATOR',
  };
}

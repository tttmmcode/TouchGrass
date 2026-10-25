import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config/auth_emulator_probe_stub.dart'
    if (dart.library.js_interop) 'core/config/auth_emulator_probe_web.dart';
import 'core/config/firebase_environment.dart';
import 'core/router/app_router.dart';
import 'core/utils/accessibility_prefs.dart';
import 'core/utils/secret_redaction.dart';
import 'providers/auth_providers.dart';
import 'providers/notification_providers.dart';
import 'providers/settings_providers.dart';
import 'providers/user_providers.dart';
import 'services/perf_service.dart';
import 'theme/app_theme.dart';

/// Must be a top-level function — FCM invokes this in a separate isolate
/// when a notification arrives while the app is terminated or backgrounded.
/// The OS shows the notification automatically from the FCM payload.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // No UI code here — this isolate has no Flutter engine context.
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Phase 8: the backend is chosen explicitly and checked; a missing,
  // unknown or unsafe setting stops here instead of guessing a project.
  final FirebaseEnv env;
  try {
    env = FirebaseEnvironment.current;
    FirebaseEnvironment.optionsFor(env);
  } on FirebaseEnvironmentError catch (e) {
    runApp(_ConfigurationErrorApp(message: e.message));
    return;
  } on UnsupportedError catch (e) {
    runApp(_ConfigurationErrorApp(message: '${e.message}'));
    return;
  }

  try {
    await _initFirebase(env);
  } on FirebaseEnvironmentError catch (e) {
    runApp(_ConfigurationErrorApp(message: e.message));
    return;
  }

  // Started only once Firebase Performance is actually available — starting
  // it earlier would throw internally (Performance isn't initialized until
  // Firebase.initializeApp() resolves) and silently never record. This
  // measures the post-Firebase-init, pre-first-frame segment; true cold
  // start time is already captured by Performance Monitoring's own
  // automatic app-start trace.
  final startupTrace = PerfService.startTrace(PerfService.traceStartup);

  // Independent of each other (and both already past the Firebase-init
  // await above), so run concurrently instead of blocking one on the other.
  final orientationFuture = SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  final onboardingComplete = await _resolveOnboardingStatus();
  await orientationFuture;
  await startupTrace?.stop();

  runApp(
    ProviderScope(
      overrides: [
        onboardingCompleteProvider.overrideWith((ref) => onboardingComplete),
      ],
      child: const TouchGrassApp(),
    ),
  );

  // Notification permission is no longer requested here — it triggers a
  // native OS dialog with zero context, and firing it this early meant it
  // could appear before the user had even signed in. It's now requested
  // contextually (with an explanatory primer) from AppShell, once the user
  // has actually reached the main app — see widgets/app_shell.dart.
}

/// Reads (and backfills) the onboarding-complete flag from [SharedPreferences].
///
/// - Already signed-in user with no flag → existing user after app update →
///   backfill [true] so they skip onboarding.
/// - New install with no signed-in user → [false] → show onboarding on first
///   sign-in.
Future<bool> _resolveOnboardingStatus() async {
  final prefs = await SharedPreferences.getInstance();
  if (FirebaseAuth.instance.currentUser != null &&
      !prefs.containsKey(kOnboardingCompleteKey)) {
    // Returning user from before this feature was shipped.
    await prefs.setBool(kOnboardingCompleteKey, true);
  }
  return prefs.getBool(kOnboardingCompleteKey) ?? false;
}

Future<void> _initFirebase(FirebaseEnv env) async {
  try {
    await Firebase.initializeApp(options: FirebaseEnvironment.optionsFor(env));

    if (env == FirebaseEnv.emulator) await _connectEmulators();

    if (!FirebaseEnvironment.telemetryEnabled && !kIsWeb) {
      // Development and emulator activity never reaches production
      // dashboards (Phase 8). AnalyticsService, PerfService and
      // CrashReporter also no-op outside production; on mobile the native
      // SDK would otherwise auto-collect screen views. (On web nothing
      // touches Analytics outside AnalyticsService.)
      try {
        await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(false);
      } catch (_) {} // no Analytics configured for this project
    }

    // Firestore offline persistence is on by default on Android/iOS, but
    // web needs it enabled explicitly (IndexedDB-backed) — without this,
    // previously loaded data (home, journal, leaderboard, etc.) simply
    // isn't there anymore the moment the web build goes offline. Not for
    // the emulators: a cache surviving an emulator reset shows stale data.
    if (kIsWeb && env != FirebaseEnv.emulator) {
      try {
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: true,
        );
      } catch (e) {
        // Fails harmlessly if already set (e.g. hot restart in dev) or if
        // the browser doesn't support IndexedDB — the app still works,
        // just without offline caching on that browser.
        debugPrint('⚠️  Firestore web persistence not enabled: $e');
      }
    }

    // Must be registered before runApp — FCM requires a top-level handler.
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Notification permission request + topic subscription moved to after
    // the first frame (see main()) — it triggers a native OS dialog and
    // shouldn't block startup.

    // Crashlytics is unsupported on web.
    if (!kIsWeb) {
      // Download tokens are removed first: an image-load error names the
      // photo's full URL, which opens the photo for anyone (Phase 7C).
      FlutterError.onError = (details) => FirebaseCrashlytics.instance
          .recordFlutterFatalError(redactFlutterErrorDetails(details));

      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(
          redactErrorForReport(error),
          stack,
          fatal: true,
        );
        return true;
      };

      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        !kDebugMode && FirebaseEnvironment.telemetryEnabled,
      );
    }
  } on FirebaseEnvironmentError {
    rethrow;
  } catch (e) {
    debugPrint('⚠️  Firebase not configured: $e');
    debugPrint('   Run: flutterfire configure --project=<your-project-id>');
  }
}

/// Points every service at the local emulators, before any other use.
/// Any failure stops startup: a half-connected emulator build would send
/// requests to real services.
Future<void> _connectEmulators() async {
  const host = FirebaseEnvironment.emulatorHost;
  try {
    await FirebaseAuth.instance.useAuthEmulator(
      host,
      FirebaseEnvironment.authPort,
    );
    FirebaseFirestore.instance.useFirestoreEmulator(
      host,
      FirebaseEnvironment.firestorePort,
    );
    await FirebaseStorage.instance.useStorageEmulator(
      host,
      FirebaseEnvironment.storagePort,
    );
    FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).useFunctionsEmulator(host, FirebaseEnvironment.functionsPort);
  } catch (e) {
    throw FirebaseEnvironmentError(
      "Couldn't connect to the emulators (${e.runtimeType}).",
    );
  }
  if (!kIsWeb) return;
  // FlutterFire swallows a failed Auth emulator connection on web; check
  // the SDK itself (see checkAuthEmulatorConnected).
  final usesEmulator = authUsesEmulator();
  if (usesEmulator == false) {
    await FirebaseAuth.instance.signOut(); // local only: clears the restore
  }
  FirebaseEnvironment.checkAuthEmulatorConnected(usesEmulator: usesEmulator);
  // Never save the session, so the next load has nothing to restore before
  // the emulator is connected. Emulator builds sign out on reload.
  await FirebaseAuth.instance.setPersistence(Persistence.NONE);
}

class TouchGrassApp extends ConsumerWidget {
  const TouchGrassApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(
      analyticsBootstrapProvider,
    ); // identity, retention, user properties
    ref.watch(fcmTokenSyncProvider); // saves this device's FCM token on sign-in
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final textScale = ref.watch(textScaleProvider);
    final reducedMotion = ref.watch(reducedMotionProvider);
    final highContrast = ref.watch(highContrastProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'TouchGrass',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      builder: (context, child) {
        // Compose with the ambient (real, OS-reactive) MediaQuery instead of
        // replacing it outright — otherwise a user who enabled Dynamic Type,
        // Reduce Motion, or Increase Contrast at the OS level would see none
        // of it unless they *also* separately set the equivalent toggle
        // inside TouchGrass's own Settings screen.
        final ambient = MediaQuery.of(context);
        return MediaQuery(
          data: ambient.copyWith(
            textScaler: TextScaler.linear(
              combinedTextScale(
                systemTextScale: ambient.textScaler.scale(1.0),
                appTextScale: textScale,
              ),
            ),
            disableAnimations: combinedReducedMotion(
              systemReducedMotion: ambient.disableAnimations,
              appReducedMotion: reducedMotion,
            ),
            highContrast: combinedHighContrast(
              systemHighContrast: ambient.highContrast,
              appHighContrast: highContrast,
            ),
          ),
          child: _environmentBanner(wideScreenFrame(context, child!)),
        );
      },
      routerConfig: router,
    );
  }
}

/// The widest the app lays itself out (a large phone). TouchGrass is
/// mobile-first: on a wider window (desktop web) its screens are shown in a
/// centered column this wide instead of being stretched — stretched grids
/// turned into tall, mostly empty cards (Phase 8, found in the browser run).
const double maxAppWidth = 600;

/// Centers the app in a [maxAppWidth] column on wide windows, and tells
/// every screen its real (column) width.
@visibleForTesting
Widget wideScreenFrame(BuildContext context, Widget child) {
  final media = MediaQuery.of(context);
  if (media.size.width <= maxAppWidth) return child;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return ColoredBox(
    color: dark ? const Color(0xFF0E1A12) : const Color(0xFFDCEFD8),
    child: Center(
      child: SizedBox(
        width: maxAppWidth,
        child: MediaQuery(
          data: media.copyWith(size: Size(maxAppWidth, media.size.height)),
          child: ClipRect(child: child),
        ),
      ),
    ),
  );
}

/// Marks development and emulator builds unmistakably (Phase 8); a
/// production build is unchanged.
Widget _environmentBanner(Widget child) {
  final label = FirebaseEnvironment.label;
  if (label == null) return child;
  return Banner(
    message: label,
    location: BannerLocation.topEnd,
    color: Colors.deepOrange,
    child: child,
  );
}

/// Shown instead of the app when the build's Firebase environment is
/// missing, unknown or unsafe (Phase 8). It contacts nothing.
class _ConfigurationErrorApp extends StatelessWidget {
  const _ConfigurationErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              "TouchGrass can't start: this build's configuration is "
              'invalid.\n\n$message',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/router/app_router.dart';
import 'core/utils/accessibility_prefs.dart';
import 'firebase_options.dart';
import 'providers/auth_providers.dart';
import 'providers/settings_providers.dart';
import 'providers/user_providers.dart';
import 'services/notification_service.dart';
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

  await _initFirebase();

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

  runApp(ProviderScope(
    overrides: [
      onboardingCompleteProvider.overrideWith((ref) => onboardingComplete),
    ],
    child: const TouchGrassApp(),
  ));

  // Requesting notification permission triggers a native OS dialog — defer
  // it until after the first frame renders so it never blocks (or precedes)
  // the user's first view of the app.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    NotificationService().initialize();
  });
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

Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Must be registered before runApp — FCM requires a top-level handler.
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Notification permission request + topic subscription moved to after
    // the first frame (see main()) — it triggers a native OS dialog and
    // shouldn't block startup.

    // Crashlytics is unsupported on web.
    if (!kIsWeb) {
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;

      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };

      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        !kDebugMode,
      );
    }
  } catch (e) {
    debugPrint('⚠️  Firebase not configured: $e');
    debugPrint('   Run: flutterfire configure --project=<your-project-id>');
  }
}

class TouchGrassApp extends ConsumerWidget {
  const TouchGrassApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(analyticsBootstrapProvider); // identity, retention, user properties
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
            textScaler: TextScaler.linear(combinedTextScale(
              systemTextScale: ambient.textScaler.scale(1.0),
              appTextScale: textScale,
            )),
            disableAnimations: combinedReducedMotion(
              systemReducedMotion: ambient.disableAnimations,
              appReducedMotion: reducedMotion,
            ),
            highContrast: combinedHighContrast(
              systemHighContrast: ambient.highContrast,
              appHighContrast: highContrast,
            ),
          ),
          child: child!,
        );
      },
      routerConfig: router,
    );
  }
}

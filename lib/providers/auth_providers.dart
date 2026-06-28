import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// SharedPreferences key for the onboarding-complete flag.
const kOnboardingCompleteKey = 'onboarding_complete';

/// Whether the current user has completed the onboarding flow.
///
/// Initialised before [runApp] from [SharedPreferences] so the router can
/// redirect synchronously. Flipped to [true] by [OnboardingScreen] on finish.
final onboardingCompleteProvider = StateProvider<bool>((ref) => true);

/// Reactive stream of the Firebase authenticated user.
///
/// Emits null when signed out, a [User] when signed in.
/// The router and UI both watch this to react to auth changes.
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

/// A [ChangeNotifier] that notifies whenever the Firebase auth state changes.
///
/// Passed to [GoRouter.refreshListenable] so the router re-evaluates its
/// redirect logic automatically on sign-in or sign-out.
final routerRefreshProvider = Provider<RouterRefreshNotifier>((ref) {
  final notifier = RouterRefreshNotifier(
    FirebaseAuth.instance.authStateChanges(),
  );
  ref.onDispose(notifier.dispose);
  return notifier;
});

class RouterRefreshNotifier extends ChangeNotifier {
  RouterRefreshNotifier(Stream<dynamic> stream) {
    // Notify immediately so the router evaluates on first build.
    notifyListeners();
    _subscription = stream.listen(
      (_) => notifyListeners(),
      onError: (_) => notifyListeners(),
    );
  }

  late final StreamSubscription<dynamic> _subscription;

  /// Manually triggers a router re-evaluation (e.g. when onboarding completes).
  void refresh() => notifyListeners();

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/achievements/screens/achievements_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/camera/screens/camera_screen.dart';
import '../../features/challenges/screens/challenge_detail_screen.dart';
import '../../features/companions/screens/companion_select_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/leaderboard/screens/leaderboard_screen.dart';
import '../../features/map/screens/map_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/streak/screens/streak_calendar_screen.dart';
import '../../models/completion_model.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/error_retry_view.dart';
import '../constants/route_names.dart';

/// The single [GoRouter] instance for the app.
///
/// Watches [routerRefreshProvider] to re-evaluate the [redirect] callback
/// whenever Firebase auth state changes. This means sign-in/sign-out
/// immediately navigates to the correct screen without any manual
/// [context.go] calls in the UI layer.
final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = ref.watch(routerRefreshProvider);

  // Re-evaluate redirect when onboarding status is updated by OnboardingScreen.
  ref.listen<bool>(onboardingCompleteProvider, (_, _) {
    refreshNotifier.refresh();
  });

  return GoRouter(
    initialLocation: RouteNames.login,
    debugLogDiagnostics: false,
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final isLoggedIn = user != null;
      final location = state.matchedLocation;

      // Redirect bare '/' to login.
      if (location == RouteNames.splash) return RouteNames.login;

      // Not signed in: force to login page.
      if (!isLoggedIn) {
        final isPreAuthRoute =
            location == RouteNames.login || location == RouteNames.onboarding;
        return isPreAuthRoute ? null : RouteNames.login;
      }

      // Signed in: redirect away from login — new users go to onboarding.
      if (location == RouteNames.login) {
        final onboardingDone = ref.read(onboardingCompleteProvider);
        return onboardingDone ? RouteNames.home : RouteNames.onboarding;
      }

      return null;
    },
    routes: [
      // ── Pre-auth ──────────────────────────────────────────────────────────
      GoRoute(
        path: RouteNames.login,
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: RouteNames.onboarding,
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),

      // ── Full-screen routes (no bottom nav) ───────────────────────────────
      GoRoute(
        path: RouteNames.camera,
        name: 'camera',
        builder: (context, state) => const CameraScreen(),
      ),
      GoRoute(
        path: '/challenge/:id',
        name: 'challengeDetail',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final completion = state.extra as CompletionModel?;
          return ChallengeDetailScreen(challengeId: id, completion: completion);
        },
      ),

      // ── Authenticated shell ──────────────────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          // Tab 0 — Home / challenge path
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.home,
                name: 'home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),

          // Tab 1 — Map
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.map,
                name: 'map',
                builder: (context, state) => const MapScreen(),
              ),
            ],
          ),

          // Tab 2 — Leaderboard
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.leaderboard,
                name: 'leaderboard',
                builder: (context, state) => const LeaderboardScreen(),
              ),
            ],
          ),

          // Tab 3 — Profile
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.profile,
                name: 'profile',
                builder: (context, state) => const ProfileScreen(),
                routes: [
                  GoRoute(
                    path: 'settings',
                    name: 'settings',
                    builder: (context, state) => const SettingsScreen(),
                  ),
                  GoRoute(
                    path: 'streak',
                    name: 'streakCalendar',
                    builder: (context, state) => const StreakCalendarScreen(),
                  ),
                ],
              ),
            ],
          ),

          // Tab 4 — Achievements / Badges
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.achievements,
                name: 'achievements',
                builder: (context, state) => const AchievementsScreen(),
                routes: [
                  GoRoute(
                    path: 'companion',
                    name: 'companionSelect',
                    builder: (context, state) => const CompanionSelectScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => _RouteErrorScreen(error: state.error),
  );
});

// ── Error screen ──────────────────────────────────────────────────────────────

class _RouteErrorScreen extends StatelessWidget {
  const _RouteErrorScreen({this.error});

  final Exception? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ErrorRetryView(
        title: 'Page not found',
        message: "The page you're looking for doesn't exist.",
        onRetry: () => context.go(RouteNames.home),
        retryLabel: 'Go Home',
      ),
    );
  }
}

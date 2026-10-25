/// All route path strings in one place.
abstract final class RouteNames {
  // ── Pre-shell ─────────────────────────────────────────────────────────────
  static const String splash = '/';
  static const String login = '/login';
  static const String onboarding = '/onboarding';

  // ── Main tabs (shell roots) ────────────────────────────────────────────────
  static const String home = '/home';
  static const String map = '/map';
  static const String leaderboard = '/leaderboard';
  static const String profile = '/profile';
  static const String achievements = '/achievements';

  // ── Full-screen routes (top-level, no bottom nav) ─────────────────────────
  static const String camera = '/camera';
  static String challengeDetail(String id) => '/challenge/$id';

  // ── Profile sub-routes ────────────────────────────────────────────────────
  static const String settings = '/profile/settings';
  static const String streakCalendar = '/profile/streak';

  // ── Achievements sub-routes ───────────────────────────────────────────────
  static const String companionSelect = '/achievements/companion';
}

/// In-app routes a push notification may deep-link to (audit S-10).
const _notificationRoutes = {
  RouteNames.home,
  RouteNames.map,
  RouteNames.leaderboard,
  RouteNames.profile,
  RouteNames.achievements,
  RouteNames.camera,
  RouteNames.settings,
  RouteNames.streakCalendar,
  RouteNames.companionSelect,
};

final _challengeRoute = RegExp(r'^/challenge/[A-Za-z0-9_-]{1,64}$');

/// The route to open for a notification's `route` data value: the value
/// itself if it is a known in-app route (or a well-formed challenge
/// detail), otherwise Home. Anything else — unknown paths, query strings,
/// external URLs, sign-in or splash routes — is ignored rather than handed
/// to the router.
String safeNotificationRoute(Object? raw) {
  if (raw is! String) return RouteNames.home;
  if (_notificationRoutes.contains(raw) || _challengeRoute.hasMatch(raw)) {
    return raw;
  }
  return RouteNames.home;
}

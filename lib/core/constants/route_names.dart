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
  static const String leagues = '/profile/leagues';
  static const String streakCalendar = '/profile/streak';

  // ── Achievements sub-routes ───────────────────────────────────────────────
  static const String companionSelect = '/achievements/companion';
}

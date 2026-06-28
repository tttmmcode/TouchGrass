import '../config/environment_config.dart';

/// App-wide constants. Never scatter magic numbers through the codebase —
/// all values with a meaning belong here.
abstract final class AppConstants {
  // ── Identity ──────────────────────────────────────────────────────────────
  static const String appName = 'TouchGrass';
  static const String appPackageId = 'com.touchgrass.app';

  // ── XP System ─────────────────────────────────────────────────────────────
  static const int xpEasy = 25;
  static const int xpMedium = 50;
  static const int xpHard = 100;

  /// Number of XP points per level.
  static const int xpPerLevel = 100;

  /// level = floor(xp / xpPerLevel) + 1
  static int levelForXp(int xp) => (xp ~/ xpPerLevel) + 1;

  /// XP needed to reach [level] (0-indexed threshold).
  static int xpThresholdForLevel(int level) => (level - 1) * xpPerLevel;

  /// Progress within the current level: a value in [0.0, 1.0].
  static double levelProgress(int xp) {
    final remainder = xp % xpPerLevel;
    return remainder / xpPerLevel;
  }

  // ── AI Verification ───────────────────────────────────────────────────────
  static const double aiConfidenceThreshold = 0.6;
  static const int aiVerificationTimeoutSeconds = 30;
  static const int aiGenerationTimeoutSeconds = 20;
  static const int aiMaxRetries = 2;

  // Injected at build time: flutter run --dart-define=GEMINI_API_KEY=AIza...
  // Do NOT hardcode a real key here — use a Cloud Function proxy in production.
  static const String geminiApiKey = EnvironmentConfig.geminiApiKey;

  // ── Challenge System ──────────────────────────────────────────────────────
  /// Days back we look when avoiding duplicate challenge assignments.
  static const int challengeDedupeWindowDays = 14;

  /// Current challenge generation prompt version.
  /// Increment when the Gemini prompt changes significantly.
  static const int challengeCurrentVersion = 1;

  // ── Difficulty timing bounds ───────────────────────────────────────────────
  static const int minutesEasyMin = 5;
  static const int minutesEasyMax = 10;
  static const int minutesMediumMin = 10;
  static const int minutesMediumMax = 20;
  static const int minutesHardMin = 20;
  static const int minutesHardMax = 40;

  // ── Streak / Rainy Days ───────────────────────────────────────────────────
  /// Starting number of Rainy Days every new user receives.
  static const int rainyDaysInitial = 3;

  /// Streak length at which the user earns 1 Rainy Day.
  static const int rainyDayEarnStreak7 = 7;

  /// Streak length at which the user earns 2 Rainy Days.
  static const int rainyDayEarnStreak30 = 30;

  /// XP cost to purchase an extra Rainy Day (shop, future use).
  static const int streakFreezeCostXp = 200;

  // ── Pagination ────────────────────────────────────────────────────────────
  static const int defaultPageSize = 20;
  static const int mapHistoryLimit = 100;
  static const int challengeHistoryPageSize = 30;

  // ── Leaderboard ───────────────────────────────────────────────────────────
  /// Max entries per league leaderboard page.
  static const int leaderboardPageSize = 30;

  /// Top N shown in promotion zone (highlighted green).
  static const int promotionZoneCount = 5;

  /// Bottom N shown in demotion zone (highlighted red).
  static const int demotionZoneCount = 5;

  // ── Weekly reset ──────────────────────────────────────────────────────────

  /// Next Monday midnight UTC — used as the weeklyXp reset boundary.
  static DateTime nextMondayMidnightUtc() {
    final now = DateTime.now().toUtc();
    // weekday: Mon=1 … Sun=7
    final daysUntilMonday = (DateTime.monday - now.weekday + 7) % 7;
    final days = daysUntilMonday == 0 ? 7 : daysUntilMonday;
    return DateTime.utc(now.year, now.month, now.day + days);
  }

  /// Human-readable countdown to the next Monday midnight UTC.
  static String weeklyResetLabel() {
    final now = DateTime.now().toUtc();
    final next = nextMondayMidnightUtc();
    final diff = next.difference(now);
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final minutes = diff.inMinutes % 60;
    if (days > 0) return '${days}d ${hours}h';
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  // ── Image ─────────────────────────────────────────────────────────────────
  static const int imageMaxWidthPx = 1080;
  static const int imageMaxHeightPx = 1080;
  static const int imageQualityPercent = 85;

  // ── Firestore collection names ────────────────────────────────────────────
  static const String colUsers = 'users';

  /// Subcollection under users/{uid}/challenges/{date}
  static const String colUserChallenges = 'challenges';

  /// Subcollection under users/{uid}/memories/{memoryId}
  static const String colUserMemories = 'memories';

  static const String colCompletions = 'completions';
  static const String colAchievements = 'achievements';

  // ── Firebase Storage paths ────────────────────────────────────────────────
  static const String storageCompletionPhotos = 'completion_photos';
  static const String storageUserAvatars = 'user_avatars';

  // ── FCM topics & channels ─────────────────────────────────────────────────
  static const String fcmTopicDaily = 'daily_challenge';
  static const String fcmTopicStreakWarning = 'streak_warning';
  static const String fcmTopicLeague = 'league_ending';
  static const String fcmTopicAchievement = 'achievement';
  static const String notifChannelGeneral = 'tg_general';
  static const String notifChannelChallenge = 'tg_challenge';
  static const String notifChannelAchievement = 'tg_achievement';

  // ── Firestore — support collections ──────────────────────────────────────
  static const String colFeedback = 'feedback';
}

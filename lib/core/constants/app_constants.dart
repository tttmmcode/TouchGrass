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

  /// Retry budget for quota-exceeded (429) responses from Gemini, with
  /// exponential backoff starting at [aiRetryBaseMs].
  static const int aiMaxRetries = 3;
  static const int aiRetryBaseMs = 2000;

  /// Single deterministic fallback used everywhere caption-prompt generation
  /// is skipped or fails, so the user never sees inconsistent wording
  /// depending on which failure path they happened to hit.
  static const String defaultCaptionPrompt =
      'What did you discover on your adventure today?';

  // Injected at build time: flutter run --dart-define=GEMINI_API_KEY=AIza...
  // Do NOT hardcode a real key here — use a Cloud Function proxy in production.
  static const String geminiApiKey = EnvironmentConfig.geminiApiKey;

  // ── Web push ──────────────────────────────────────────────────────────────
  // Injected at build time: flutter build web --dart-define=FCM_VAPID_KEY=...
  static const String fcmVapidKey = EnvironmentConfig.fcmVapidKey;
  static bool get fcmVapidConfigured => EnvironmentConfig.fcmVapidConfigured;

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

  /// Page size for cursor-paginated adventure memory queries (map + journal).
  /// Replaces the old hard `mapHistoryLimit` cap — history now loads
  /// incrementally instead of stopping after a fixed number of memories.
  static const int memoryPageSize = 50;

  // ── Leaderboard ───────────────────────────────────────────────────────────
  /// Max entries per league leaderboard page.
  static const int leaderboardPageSize = 30;

  /// Top N highlighted as this week's leading performers on the leaderboard.
  /// Presentational only — TouchGrass leagues are XP-tier based (see
  /// [LeagueDef.forXp]); there is no separate weekly-rank promotion/demotion
  /// transaction, so this does not affect league placement.
  static const int promotionZoneCount = 5;

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

  /// Must stay in sync with the size caps in storage.rules.
  static const int maxCompletionPhotoBytes = 10 * 1024 * 1024;
  static const int maxProfilePhotoBytes = 5 * 1024 * 1024;

  // ── Network ───────────────────────────────────────────────────────────────
  /// Ceiling for Storage/Firestore calls so a dropped connection mid-request
  /// surfaces as a friendly timeout instead of hanging the UI indefinitely.
  static const int networkTimeoutSeconds = 30;

  // ── Firestore collection names ────────────────────────────────────────────
  static const String colUsers = 'users';

  /// Public mirror of the safe-to-share subset of a user's document
  /// (displayName, username, photoUrl, xp, weeklyXp, streak, currentLeague).
  /// Leaderboard/league queries read from here instead of [colUsers] so
  /// no client can read another user's private fields (e.g. email).
  static const String colLeaderboardPublic = 'leaderboard_public';

  /// Username-claim registry: doc ID is the lowercase username, data is
  /// `{'uid': <owner>}`. Enforces uniqueness via a transaction in
  /// UserRepository — never written to directly.
  static const String colUsernames = 'usernames';

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

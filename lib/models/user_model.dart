import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import 'entitlement.dart';

/// Immutable representation of a TouchGrass user.
///
/// [level] is derived from [xp] and never stored independently —
/// this avoids inconsistency if the level formula changes.
/// When writing to Firestore we also persist the computed level so
/// Cloud Functions can run range queries without recalculating it.
@immutable
class UserModel {
  const UserModel({
    required this.uid,
    required this.email,
    required this.username,
    required this.displayName,
    this.photoUrl,
    required this.xp,
    required this.weeklyXp,
    required this.weeklyXpResetDate,
    required this.streak,
    required this.longestStreak,
    required this.totalCompletions,
    required this.totalPhotosUploaded,
    required this.rainyDayCount,
    required this.currentLeague,
    required this.createdAt,
    required this.lastActiveDate,
    required this.achievements,
    this.achievementTimestamps = const {},
    required this.settings,
    this.frozenDates = const [],
    this.entitlementTier = EntitlementTier.free,
  });

  final String uid;
  final String email;

  /// Unique handle (e.g. "jane_doe_a3f2"). Always lowercase.
  final String username;
  final String displayName;
  final String? photoUrl;
  final int xp;

  /// XP earned since the last weekly reset (Monday midnight UTC).
  final int weeklyXp;

  /// UTC timestamp of the next Monday midnight when [weeklyXp] resets.
  final DateTime weeklyXpResetDate;

  final int streak;

  /// All-time highest streak, updated whenever [streak] exceeds it.
  final int longestStreak;
  final int totalCompletions;
  final int totalPhotosUploaded;

  /// Total number of Rainy Days (streak freezes) consumed lifetime.
  final int rainyDayCount;

  /// League identifier: 'seedling', 'sprout', 'wildflower', 'forest',
  /// 'mountain', or 'summit'.
  final String currentLeague;

  final DateTime createdAt;
  final DateTime lastActiveDate;

  /// IDs of unlocked achievements, e.g. "first_touch", "streak_7".
  final List<String> achievements;

  /// UTC timestamps of when each achievement was earned, keyed by achievement ID.
  /// Only populated for achievements earned after this feature was released.
  final Map<String, DateTime> achievementTimestamps;

  final UserSettings settings;

  /// Calendar dates ("yyyy-MM-dd", local to the user at the time) on which a
  /// Rainy Day freeze absorbed a missed day, so the streak calendar can
  /// render a truthful "frozen" state instead of guessing from streak
  /// counters alone. Small and append-only — see
  /// [UserRepository.awardCompletionRewards].
  final List<String> frozenDates;

  /// Defaults to [EntitlementTier.free] when absent from the document
  /// (every user today, since nothing writes this field yet). Deliberately
  /// NOT written by [toFirestore] — see entitlement.dart's doc comment for
  /// why the client must never be able to set this itself.
  final EntitlementTier entitlementTier;

  // ── Computed properties ────────────────────────────────────────────────────

  int get level => AppConstants.levelForXp(xp);
  double get levelProgress => AppConstants.levelProgress(xp);
  int get xpInCurrentLevel => xp % AppConstants.xpPerLevel;

  /// Rainy Days (streak freezes) currently available.
  int get rainyDaysAvailable => settings.streakFreezesOwned;

  /// Rainy Days consumed lifetime (same as rainyDayCount).
  int get rainyDaysUsed => rainyDayCount;

  bool hasAchievement(String id) => achievements.contains(id);

  // ── Constructors ───────────────────────────────────────────────────────────

  factory UserModel.initial({
    required String uid,
    required String displayName,
    String? photoUrl,
    String? email,
  }) {
    final username = _defaultUsername(displayName, uid);
    return UserModel(
      uid: uid,
      email: email ?? '',
      username: username,
      displayName: displayName,
      photoUrl: photoUrl,
      xp: 0,
      weeklyXp: 0,
      weeklyXpResetDate: AppConstants.nextMondayMidnightUtc(),
      streak: 0,
      longestStreak: 0,
      totalCompletions: 0,
      totalPhotosUploaded: 0,
      rainyDayCount: 0,
      currentLeague: 'seedling',
      createdAt: DateTime.now().toUtc(),
      lastActiveDate: DateTime.now().toUtc(),
      achievements: const [],
      achievementTimestamps: const {},
      settings: UserSettings.defaults(),
      frozenDates: const [],
    );
  }

  factory UserModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;

    final rawTimestamps =
        data['achievementTimestamps'] as Map<String, dynamic>? ?? {};
    final achievementTimestamps = rawTimestamps.map(
      (k, v) => MapEntry(
        k,
        v is Timestamp ? v.toDate().toUtc() : DateTime.now().toUtc(),
      ),
    );

    return UserModel(
      uid: doc.id,
      email: data['email'] as String? ?? '',
      username: data['username'] as String? ?? '',
      displayName: data['displayName'] as String? ?? 'Explorer',
      photoUrl: data['photoUrl'] as String?,
      xp: data['xp'] as int? ?? 0,
      weeklyXp: data['weeklyXp'] as int? ?? 0,
      // Default to epoch so first XP award after deploy triggers a reset.
      weeklyXpResetDate: _tsToDate(
        data['weeklyXpResetDate'],
        fallback: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ),
      streak: data['streak'] as int? ?? 0,
      longestStreak: data['longestStreak'] as int? ?? 0,
      totalCompletions: data['totalCompletions'] as int? ?? 0,
      totalPhotosUploaded: data['totalPhotosUploaded'] as int? ?? 0,
      rainyDayCount: data['rainyDayCount'] as int? ?? 0,
      currentLeague: data['currentLeague'] as String? ?? 'seedling',
      createdAt: _tsToDate(data['createdAt']),
      lastActiveDate: _tsToDate(data['lastActiveDate']),
      achievements: List<String>.from(data['achievements'] as List? ?? []),
      achievementTimestamps: achievementTimestamps,
      settings: UserSettings.fromMap(
        data['settings'] as Map<String, dynamic>? ?? {},
      ),
      frozenDates: List<String>.from(data['frozenDates'] as List? ?? []),
      entitlementTier: EntitlementTierX.fromString(
        data['entitlementTier'] as String?,
      ),
    );
  }

  // ── Serialisation ──────────────────────────────────────────────────────────

  Map<String, dynamic> toFirestore() => {
    'uid': uid,
    'email': email,
    'username': username,
    'displayName': displayName,
    'photoUrl': photoUrl,
    'xp': xp,
    'weeklyXp': weeklyXp,
    'weeklyXpResetDate': Timestamp.fromDate(weeklyXpResetDate),
    'level': level, // stored for Cloud Functions query efficiency
    'streak': streak,
    'longestStreak': longestStreak,
    'totalCompletions': totalCompletions,
    'totalPhotosUploaded': totalPhotosUploaded,
    'rainyDayCount': rainyDayCount,
    'currentLeague': currentLeague,
    'createdAt': Timestamp.fromDate(createdAt),
    'lastActiveDate': Timestamp.fromDate(lastActiveDate),
    'achievements': achievements,
    'settings': settings.toMap(),
    'frozenDates': frozenDates,
    // achievementTimestamps is omitted — entries are written individually
    // using 'achievementTimestamps.{id}' field notation.
  };

  // ── Mutation ───────────────────────────────────────────────────────────────

  UserModel copyWith({
    String? email,
    String? username,
    String? displayName,
    String? photoUrl,
    bool clearPhoto = false,
    int? xp,
    int? weeklyXp,
    DateTime? weeklyXpResetDate,
    int? streak,
    int? longestStreak,
    int? totalCompletions,
    int? totalPhotosUploaded,
    int? rainyDayCount,
    String? currentLeague,
    DateTime? lastActiveDate,
    List<String>? achievements,
    Map<String, DateTime>? achievementTimestamps,
    UserSettings? settings,
    List<String>? frozenDates,
  }) => UserModel(
    uid: uid,
    email: email ?? this.email,
    username: username ?? this.username,
    displayName: displayName ?? this.displayName,
    photoUrl: clearPhoto ? null : (photoUrl ?? this.photoUrl),
    xp: xp ?? this.xp,
    weeklyXp: weeklyXp ?? this.weeklyXp,
    weeklyXpResetDate: weeklyXpResetDate ?? this.weeklyXpResetDate,
    streak: streak ?? this.streak,
    longestStreak: longestStreak ?? this.longestStreak,
    totalCompletions: totalCompletions ?? this.totalCompletions,
    totalPhotosUploaded: totalPhotosUploaded ?? this.totalPhotosUploaded,
    rainyDayCount: rainyDayCount ?? this.rainyDayCount,
    currentLeague: currentLeague ?? this.currentLeague,
    createdAt: createdAt,
    lastActiveDate: lastActiveDate ?? this.lastActiveDate,
    achievements: achievements ?? this.achievements,
    achievementTimestamps: achievementTimestamps ?? this.achievementTimestamps,
    settings: settings ?? this.settings,
    frozenDates: frozenDates ?? this.frozenDates,
    // No override parameter, deliberately — see entitlement.dart.
    entitlementTier: entitlementTier,
  );

  // ── Equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserModel &&
          uid == other.uid &&
          xp == other.xp &&
          streak == other.streak &&
          totalCompletions == other.totalCompletions &&
          achievements.length == other.achievements.length;

  @override
  int get hashCode => Object.hash(uid, xp, streak, totalCompletions);

  // ── Helpers ────────────────────────────────────────────────────────────────

  static DateTime _tsToDate(Object? value, {DateTime? fallback}) {
    if (value is Timestamp) return value.toDate().toUtc();
    return fallback ?? DateTime.now().toUtc();
  }

  /// Generates a stable, unique-ish username from displayName + uid suffix.
  static String _defaultUsername(String displayName, String uid) {
    final base = displayName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final suffix = uid.length >= 4 ? uid.substring(0, 4).toLowerCase() : uid;
    return '${base.isEmpty ? 'user' : base}_$suffix';
  }
}

// ── UserSettings ──────────────────────────────────────────────────────────────

@immutable
class UserSettings {
  const UserSettings({
    required this.notificationsEnabled,
    required this.streakFreezesOwned,
    required this.locationEnabled,
    required this.profilePublic,
    this.companionType = 'sprout',
    this.preferredCategories = const [],
  });

  factory UserSettings.defaults() => const UserSettings(
    notificationsEnabled: true,
    streakFreezesOwned: AppConstants.rainyDaysInitial,
    locationEnabled: true,
    profilePublic: true,
    companionType: 'sprout',
    preferredCategories: [],
  );

  factory UserSettings.fromMap(Map<String, dynamic> map) => UserSettings(
    notificationsEnabled: map['notificationsEnabled'] as bool? ?? true,
    streakFreezesOwned: map['streakFreezesOwned'] as int? ?? 0,
    locationEnabled: map['locationEnabled'] as bool? ?? true,
    profilePublic: map['profilePublic'] as bool? ?? true,
    companionType: map['companionType'] as String? ?? 'sprout',
    preferredCategories:
        (map['preferredCategories'] as List<dynamic>?)
            ?.cast<String>()
            .toList() ??
        const [],
  );

  final bool notificationsEnabled;
  final int streakFreezesOwned;

  /// Whether the user has consented to saving GPS location with completions.
  final bool locationEnabled;

  /// Whether the user's profile appears in leaderboards and leagues.
  final bool profilePublic;

  /// The user's chosen companion: 'sprout', 'pebble', 'sunny', or 'leafy'.
  final String companionType;

  /// [ChallengeCategory.name] values the user wants their daily challenges
  /// drawn from. An empty list means no preference — every category is
  /// eligible. Stored as raw strings (not the enum) so an old client never
  /// chokes on a category name it doesn't recognize yet; unrecognized names
  /// are simply ignored by the filter rather than causing an error — see
  /// ChallengeSeedLibrary.selectSeed's preferredCategories handling.
  final List<String> preferredCategories;

  Map<String, dynamic> toMap() => {
    'notificationsEnabled': notificationsEnabled,
    'streakFreezesOwned': streakFreezesOwned,
    'locationEnabled': locationEnabled,
    'profilePublic': profilePublic,
    'companionType': companionType,
    'preferredCategories': preferredCategories,
  };

  UserSettings copyWith({
    bool? notificationsEnabled,
    int? streakFreezesOwned,
    bool? locationEnabled,
    bool? profilePublic,
    String? companionType,
    List<String>? preferredCategories,
  }) => UserSettings(
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    streakFreezesOwned: streakFreezesOwned ?? this.streakFreezesOwned,
    locationEnabled: locationEnabled ?? this.locationEnabled,
    profilePublic: profilePublic ?? this.profilePublic,
    companionType: companionType ?? this.companionType,
    preferredCategories: preferredCategories ?? this.preferredCategories,
  );
}

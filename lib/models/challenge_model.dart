import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show Alignment, Color, HSLColor, LinearGradient;

import '../core/constants/app_constants.dart';
import '../theme/app_colors.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum ChallengeCategory {
  nature,
  observation,
  exercise,
  exploration,
  photography,
  mindfulness,
  environmental,
  microAdventure;

  String get displayName => switch (this) {
    ChallengeCategory.nature => 'Nature',
    ChallengeCategory.observation => 'Observation',
    ChallengeCategory.exercise => 'Exercise',
    ChallengeCategory.exploration => 'Exploration',
    ChallengeCategory.photography => 'Photography',
    ChallengeCategory.mindfulness => 'Mindfulness',
    ChallengeCategory.environmental => 'Environment',
    ChallengeCategory.microAdventure => 'Micro Adventure',
  };

  String get emoji => switch (this) {
    ChallengeCategory.nature => '🌿',
    ChallengeCategory.observation => '🔭',
    ChallengeCategory.exercise => '🏃',
    ChallengeCategory.exploration => '🗺️',
    ChallengeCategory.photography => '📷',
    ChallengeCategory.mindfulness => '🧘',
    ChallengeCategory.environmental => '♻️',
    ChallengeCategory.microAdventure => '⚡',
  };

  /// Centralized category color — the single source of truth for any widget
  /// that needs to color-code a challenge by category (Daily Challenge card,
  /// challenge detail header, etc.), instead of each widget hardcoding its
  /// own ad hoc mapping. [ChallengeCategory.fromString]'s fallback to
  /// [ChallengeCategory.nature] for unrecognized raw values means an unknown
  /// category always still resolves to a valid color here, never a crash.
  Color get color => switch (this) {
    ChallengeCategory.nature => AppColors.categoryNature,
    ChallengeCategory.observation => AppColors.categoryObservation,
    ChallengeCategory.exercise => AppColors.categoryExercise,
    ChallengeCategory.exploration => AppColors.categoryExploration,
    ChallengeCategory.photography => AppColors.categoryPhotography,
    ChallengeCategory.mindfulness => AppColors.categoryMindfulness,
    ChallengeCategory.environmental => AppColors.categoryEnvironmental,
    ChallengeCategory.microAdventure => AppColors.categoryMicroAdventure,
  };

  /// Two-stop gradient (base [color] → a ~14%-darker shade of it) in the
  /// same topLeft-to-bottomRight style as AppColors.gradientForest/gradientGold/
  /// etc., so a category-colored card reads as "on brand" rather than a flat
  /// color dropped into a gradient-styled app.
  LinearGradient get gradient {
    final hsl = HSLColor.fromColor(color);
    final darker = hsl
        .withLightness((hsl.lightness - 0.14).clamp(0.0, 1.0))
        .toColor();
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [color, darker],
    );
  }

  static ChallengeCategory fromString(String? value) {
    return switch (value) {
      'nature' => ChallengeCategory.nature,
      'observation' => ChallengeCategory.observation,
      'exercise' || 'social' => ChallengeCategory.exercise,
      'exploration' || 'urban' => ChallengeCategory.exploration,
      'photography' || 'water' => ChallengeCategory.photography,
      'mindfulness' => ChallengeCategory.mindfulness,
      'environmental' => ChallengeCategory.environmental,
      'microAdventure' || 'micro_adventure' => ChallengeCategory.microAdventure,
      'sky' => ChallengeCategory.observation,
      _ => ChallengeCategory.nature,
    };
  }
}

enum ChallengeDifficulty {
  easy,
  medium,
  hard;

  String get displayName => switch (this) {
    ChallengeDifficulty.easy => 'Easy',
    ChallengeDifficulty.medium => 'Medium',
    ChallengeDifficulty.hard => 'Hard',
  };

  String get emoji => switch (this) {
    ChallengeDifficulty.easy => '🟢',
    ChallengeDifficulty.medium => '🟡',
    ChallengeDifficulty.hard => '🔴',
  };

  int get xpReward => switch (this) {
    ChallengeDifficulty.easy => AppConstants.xpEasy,
    ChallengeDifficulty.medium => AppConstants.xpMedium,
    ChallengeDifficulty.hard => AppConstants.xpHard,
  };

  int get minMinutes => switch (this) {
    ChallengeDifficulty.easy => AppConstants.minutesEasyMin,
    ChallengeDifficulty.medium => AppConstants.minutesMediumMin,
    ChallengeDifficulty.hard => AppConstants.minutesHardMin,
  };

  int get maxMinutes => switch (this) {
    ChallengeDifficulty.easy => AppConstants.minutesEasyMax,
    ChallengeDifficulty.medium => AppConstants.minutesMediumMax,
    ChallengeDifficulty.hard => AppConstants.minutesHardMax,
  };

  static ChallengeDifficulty fromString(String? value) =>
      ChallengeDifficulty.values.firstWhere(
        (e) => e.name == value,
        orElse: () => ChallengeDifficulty.medium,
      );
}

// ── ChallengeModel ────────────────────────────────────────────────────────────

/// The primary challenge entity for the Phase 3 engine.
///
/// Stored in Firestore at: `users/{uid}/challenges/{yyyy-MM-dd}`
///
/// This single model replaces the old `ChallengeModel` + `DailyAssignmentModel`
/// pair. It carries everything from generation metadata through completion status,
/// enabling permanent per-user challenge history.
@immutable
class ChallengeModel {
  const ChallengeModel({
    required this.challengeId,
    required this.userId,
    required this.dayNumber,
    required this.title,
    required this.description,
    required this.objective,
    required this.successCriteria,
    required this.difficulty,
    required this.estimatedMinutes,
    required this.xpReward,
    required this.challengeCategory,
    required this.emoji,
    required this.generatedAt,
    required this.expiresAt,
    required this.challengeVersion,
    this.isCompleted = false,
    this.completionDate,
    this.rerollCount = 0,
    this.aiGenerated = true,
    this.challengeSeed,
  });

  /// Document ID in Firestore — always `yyyy-MM-dd` in the user's local timezone.
  final String challengeId;
  final String userId;

  /// 1-based day counter since the user's account creation date.
  final int dayNumber;

  final String title;

  /// Vivid one-sentence summary: what to do and why it's interesting.
  final String description;

  /// Single clear action-verb instruction for the user.
  final String objective;

  /// What the AI photo verifier should look for to approve this challenge.
  final String successCriteria;

  final ChallengeDifficulty difficulty;
  final int estimatedMinutes;
  final int xpReward;
  final ChallengeCategory challengeCategory;
  final String emoji;

  /// When Gemini created this challenge.
  final DateTime generatedAt;

  /// When this challenge expires (local midnight → stored as UTC).
  final DateTime expiresAt;

  /// Incremented when the generation prompt template changes significantly.
  final int challengeVersion;

  final bool isCompleted;
  final DateTime? completionDate;

  /// How many times the user has rerolled today's challenge.
  final int rerollCount;

  /// True when generated by Gemini; false for synthetic seed fallbacks.
  final bool aiGenerated;

  /// The seed parameters passed to Gemini, e.g. `"nature|insects|easy"`.
  final String? challengeSeed;

  // ── Computed ───────────────────────────────────────────────────────────────

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  // ── Validation ─────────────────────────────────────────────────────────────

  bool get isValid =>
      title.isNotEmpty &&
      description.isNotEmpty &&
      objective.isNotEmpty &&
      successCriteria.isNotEmpty &&
      xpReward > 0 &&
      estimatedMinutes > 0;

  // ── Firestore ──────────────────────────────────────────────────────────────

  factory ChallengeModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return ChallengeModel(
      challengeId: doc.id,
      userId: data['userId'] as String? ?? '',
      dayNumber: (data['dayNumber'] as num?)?.toInt() ?? 1,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      objective: data['objective'] as String? ?? '',
      successCriteria: data['successCriteria'] as String? ?? '',
      difficulty: ChallengeDifficulty.fromString(data['difficulty'] as String?),
      estimatedMinutes: (data['estimatedMinutes'] as num?)?.toInt() ?? 10,
      xpReward: (data['xpReward'] as num?)?.toInt() ?? AppConstants.xpMedium,
      challengeCategory: ChallengeCategory.fromString(
        data['challengeCategory'] as String?,
      ),
      emoji: data['emoji'] as String? ?? '🌿',
      generatedAt: _tsToDate(data['generatedAt']),
      expiresAt: _tsToDate(data['expiresAt']),
      challengeVersion:
          (data['challengeVersion'] as num?)?.toInt() ??
          AppConstants.challengeCurrentVersion,
      isCompleted: data['isCompleted'] as bool? ?? false,
      completionDate: data['completionDate'] != null
          ? _tsToDate(data['completionDate'])
          : null,
      rerollCount: (data['rerollCount'] as num?)?.toInt() ?? 0,
      aiGenerated: data['aiGenerated'] as bool? ?? true,
      challengeSeed: data['challengeSeed'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'challengeId': challengeId,
    'userId': userId,
    'dayNumber': dayNumber,
    'title': title,
    'description': description,
    'objective': objective,
    'successCriteria': successCriteria,
    'difficulty': difficulty.name,
    'estimatedMinutes': estimatedMinutes,
    'xpReward': xpReward,
    'challengeCategory': challengeCategory.name,
    'emoji': emoji,
    'generatedAt': Timestamp.fromDate(generatedAt),
    'expiresAt': Timestamp.fromDate(expiresAt),
    'challengeVersion': challengeVersion,
    'isCompleted': isCompleted,
    if (completionDate != null)
      'completionDate': Timestamp.fromDate(completionDate!),
    'rerollCount': rerollCount,
    'aiGenerated': aiGenerated,
    if (challengeSeed != null) 'challengeSeed': challengeSeed,
  };

  // ── Mutation ───────────────────────────────────────────────────────────────

  ChallengeModel copyWith({
    int? dayNumber,
    String? title,
    String? description,
    String? objective,
    String? successCriteria,
    ChallengeDifficulty? difficulty,
    int? estimatedMinutes,
    int? xpReward,
    ChallengeCategory? challengeCategory,
    String? emoji,
    DateTime? generatedAt,
    bool? isCompleted,
    DateTime? completionDate,
    int? rerollCount,
    bool? aiGenerated,
    String? challengeSeed,
  }) => ChallengeModel(
    challengeId: challengeId,
    userId: userId,
    dayNumber: dayNumber ?? this.dayNumber,
    title: title ?? this.title,
    description: description ?? this.description,
    objective: objective ?? this.objective,
    successCriteria: successCriteria ?? this.successCriteria,
    difficulty: difficulty ?? this.difficulty,
    estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
    xpReward: xpReward ?? this.xpReward,
    challengeCategory: challengeCategory ?? this.challengeCategory,
    emoji: emoji ?? this.emoji,
    generatedAt: generatedAt ?? this.generatedAt,
    expiresAt: expiresAt,
    challengeVersion: challengeVersion,
    isCompleted: isCompleted ?? this.isCompleted,
    completionDate: completionDate ?? this.completionDate,
    rerollCount: rerollCount ?? this.rerollCount,
    aiGenerated: aiGenerated ?? this.aiGenerated,
    challengeSeed: challengeSeed ?? this.challengeSeed,
  );

  // ── Equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChallengeModel &&
          challengeId == other.challengeId &&
          userId == other.userId &&
          rerollCount == other.rerollCount &&
          isCompleted == other.isCompleted;

  @override
  int get hashCode =>
      Object.hash(challengeId, userId, rerollCount, isCompleted);

  // ── Helpers ────────────────────────────────────────────────────────────────

  static DateTime _tsToDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    return DateTime.now();
  }

  /// Returns today's document ID in local timezone: `yyyy-MM-dd`.
  static String todayDocId() {
    final now = DateTime.now();
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    return '${now.year}-$mm-$dd';
  }

  /// Returns the document ID for a given date in local timezone.
  static String docIdForDate(DateTime date) {
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    return '${date.year}-$mm-$dd';
  }
}

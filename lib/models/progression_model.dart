import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import 'user_model.dart';

/// Single source of truth for all progression data in the UI.
///
/// Computed from [UserModel] — never stored independently in Firestore.
/// Screens read this instead of reaching into [UserModel] directly for
/// progression concerns, keeping the calculation logic in one place.
@immutable
class ProgressionModel {
  const ProgressionModel({
    required this.userId,
    required this.totalXP,
    required this.currentLevel,
    required this.currentLevelXP,
    required this.xpRequiredForNextLevel,
    required this.currentStreak,
    required this.longestStreak,
    required this.rainyDaysAvailable,
    required this.rainyDaysUsed,
    required this.lastChallengeCompletionDate,
    required this.totalChallengesCompleted,
    required this.levelUpCount,
  });

  final String userId;

  /// Lifetime XP accumulated.
  final int totalXP;

  /// Current level (1-indexed).
  final int currentLevel;

  /// XP earned within the current level (resets at each level boundary).
  final int currentLevelXP;

  /// XP needed to complete the current level (constant: [AppConstants.xpPerLevel]).
  final int xpRequiredForNextLevel;

  final int currentStreak;
  final int longestStreak;

  /// Rainy Days (streak freezes) currently available.
  final int rainyDaysAvailable;

  /// Total Rainy Days consumed lifetime.
  final int rainyDaysUsed;

  /// Date of the last successful challenge completion (local time).
  final DateTime? lastChallengeCompletionDate;

  final int totalChallengesCompleted;

  /// Number of times the user has levelled up (= currentLevel - 1).
  final int levelUpCount;

  // ── Computed ────────────────────────────────────────────────────────────────

  /// Progress within the current level as a fraction in [0.0, 1.0].
  double get levelProgressFraction =>
      currentLevelXP / xpRequiredForNextLevel.clamp(1, double.maxFinite);

  /// XP still needed to reach the next level.
  int get xpToNextLevel => xpRequiredForNextLevel - currentLevelXP;

  /// Human-readable level title shown in profiles / level-up screens.
  String get levelTitle {
    if (currentLevel >= 50) return 'Legend';
    if (currentLevel >= 30) return 'Master Explorer';
    if (currentLevel >= 20) return 'Trailblazer';
    if (currentLevel >= 10) return 'Explorer';
    if (currentLevel >= 5) return 'Adventurer';
    return 'Seedling';
  }

  // ── Factory ─────────────────────────────────────────────────────────────────

  factory ProgressionModel.fromUser(UserModel user) {
    return ProgressionModel(
      userId: user.uid,
      totalXP: user.xp,
      currentLevel: user.level,
      currentLevelXP: user.xpInCurrentLevel,
      xpRequiredForNextLevel: AppConstants.xpPerLevel,
      currentStreak: user.streak,
      longestStreak: user.longestStreak,
      rainyDaysAvailable: user.rainyDaysAvailable,
      rainyDaysUsed: user.rainyDaysUsed,
      lastChallengeCompletionDate: user.lastActiveDate.toLocal(),
      totalChallengesCompleted: user.totalCompletions,
      levelUpCount: (user.level - 1).clamp(0, double.maxFinite.toInt()),
    );
  }

  // ── Validation ───────────────────────────────────────────────────────────────

  bool get isValid =>
      totalXP >= 0 &&
      currentLevel >= 1 &&
      currentLevelXP >= 0 &&
      currentLevelXP < xpRequiredForNextLevel &&
      currentStreak >= 0 &&
      longestStreak >= currentStreak &&
      rainyDaysAvailable >= 0;

  // ── Equality ────────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProgressionModel &&
          userId == other.userId &&
          totalXP == other.totalXP &&
          currentStreak == other.currentStreak &&
          rainyDaysAvailable == other.rainyDaysAvailable;

  @override
  int get hashCode => Object.hash(userId, totalXP, currentStreak);
}

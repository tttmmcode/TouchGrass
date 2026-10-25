import 'package:flutter/foundation.dart';

import 'user_model.dart';

@immutable
class CompletionReward {
  const CompletionReward({
    required this.updatedUser,
    required this.xpAwarded,
    required this.newStreak,
    required this.previousStreak,
    required this.leveledUp,
    required this.newLevel,
    required this.rainyDaysAvailable,
    required this.previousLeague,
    this.newAchievements = const [],
    this.rainyDayConsumed = false,
    this.rainyDayEarned = 0,
  });

  final UserModel updatedUser;
  final int xpAwarded;
  final int newStreak;

  /// Streak value before this completion — lets callers show "Streak
  /// extended!" only when it's actually true instead of guessing from
  /// [newStreak] alone (which stays the same on a Rainy Day save).
  final int previousStreak;
  final bool leveledUp;
  final int newLevel;
  final List<String> newAchievements;

  /// True when a Rainy Day was automatically spent to prevent a streak reset.
  final bool rainyDayConsumed;

  /// Number of Rainy Days earned as a milestone reward this completion.
  final int rainyDayEarned;

  /// Current Rainy Days available after this completion.
  final int rainyDaysAvailable;

  /// League ID the user was in before this completion.
  final String previousLeague;

  /// True when the user moved into a higher league as a result of this completion.
  bool get leaguePromoted => updatedUser.currentLeague != previousLeague;

  /// True when this completion actually grew the streak (vs. holding it
  /// steady on a same-day resubmission or Rainy Day save).
  bool get streakIncreased => newStreak > previousStreak;

  // Backward-compatible alias.
  bool get freezeConsumed => rainyDayConsumed;
}

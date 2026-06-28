import 'package:flutter/foundation.dart';

import 'user_model.dart';

@immutable
class CompletionReward {
  const CompletionReward({
    required this.updatedUser,
    required this.xpAwarded,
    required this.newStreak,
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
  bool get leaguePromoted =>
      updatedUser.currentLeague != previousLeague;

  // Backward-compatible alias.
  bool get freezeConsumed => rainyDayConsumed;
}

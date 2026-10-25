// Unit tests for CompletionReward's pure comparison getters — the derived
// booleans the success screen uses to decide whether to show a
// league-promotion or "streak extended" notification after a challenge
// completion, without recomputing those decisions itself.

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/models/completion_reward.dart';
import 'package:touchgrass/models/user_model.dart';

void main() {
  UserModel userWithLeague(String league) => UserModel.initial(
    uid: 'u1',
    displayName: 'Explorer',
  ).copyWith(currentLeague: league);

  CompletionReward rewardWith({
    String league = 'sprout',
    String previousLeague = 'sprout',
    int newStreak = 2,
    int previousStreak = 1,
  }) => CompletionReward(
    updatedUser: userWithLeague(league),
    xpAwarded: 25,
    newStreak: newStreak,
    previousStreak: previousStreak,
    leveledUp: false,
    newLevel: 1,
    rainyDaysAvailable: 0,
    previousLeague: previousLeague,
  );

  group('CompletionReward.leaguePromoted', () {
    test('is false when the league is unchanged', () {
      final reward = rewardWith(league: 'sprout', previousLeague: 'sprout');
      expect(reward.leaguePromoted, isFalse);
    });

    test('is true when the completion moved the user into a new league', () {
      final reward = rewardWith(league: 'wildflower', previousLeague: 'sprout');
      expect(reward.leaguePromoted, isTrue);
    });
  });

  group('CompletionReward.streakIncreased', () {
    test('is true when newStreak grew past previousStreak', () {
      final reward = rewardWith(previousStreak: 4, newStreak: 5);
      expect(reward.streakIncreased, isTrue);
    });

    test('is false when a Rainy Day held the streak steady', () {
      final reward = rewardWith(previousStreak: 5, newStreak: 5);
      expect(reward.streakIncreased, isFalse);
    });

    test('is false on a same-day resubmission (streak unchanged)', () {
      final reward = rewardWith(previousStreak: 3, newStreak: 3);
      expect(reward.streakIncreased, isFalse);
    });
  });
}

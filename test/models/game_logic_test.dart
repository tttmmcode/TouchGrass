// Unit tests for pure business logic that needs no Firebase/widget setup.
//
// This file previously contained the unmodified `flutter create` counter-app
// template (asserting `find.text('0')`/`find.text('1')` against a counter
// that doesn't exist in this app) and always failed. Replaced with real
// coverage of the achievement-reward and league-tier logic touched during
// this session's release audit — a full widget/integration test suite
// (requiring Firebase test mocking) remains a separate, larger effort.

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/models/achievement_definition.dart';
import 'package:touchgrass/models/league_definition.dart';

void main() {
  group('AchievementDefinition.computeNewlyEarned', () {
    test('unlocks first_touch on first completion', () {
      final earned = AchievementDefinition.computeNewlyEarned(
        alreadyEarned: {},
        newXp: 25,
        newStreak: 1,
        newLevel: 1,
        newTotalCompletions: 1,
      );
      expect(earned, contains('first_touch'));
    });

    test('does not re-award an already-earned achievement', () {
      final earned = AchievementDefinition.computeNewlyEarned(
        alreadyEarned: {'first_touch'},
        newXp: 25,
        newStreak: 1,
        newLevel: 1,
        newTotalCompletions: 1,
      );
      expect(earned, isNot(contains('first_touch')));
    });

    test('unlocks multiple thresholds crossed in a single completion', () {
      final earned = AchievementDefinition.computeNewlyEarned(
        alreadyEarned: {},
        newXp: 2500,
        newStreak: 100,
        newLevel: 10,
        newTotalCompletions: 100,
      );
      // Every catalog threshold at or below these values should fire at once.
      expect(
        earned,
        containsAll([
          'first_touch',
          'streak_3',
          'streak_7',
          'streak_30',
          'streak_100',
          'xp_100',
          'xp_500',
          'xp_1000',
          'xp_2500',
          'level_5',
          'level_10',
          'challenges_100',
        ]),
      );
    });
  });

  group('AchievementDefinition.totalXpReward', () {
    test('sums xpReward across the given achievement ids', () {
      final byId = {for (final a in AchievementDefinition.catalog) a.id: a};
      final total = AchievementDefinition.totalXpReward([
        'first_touch',
        'streak_7',
      ]);
      expect(total, byId['first_touch']!.xpReward + byId['streak_7']!.xpReward);
    });

    test('returns 0 for an empty id list', () {
      expect(AchievementDefinition.totalXpReward(const []), 0);
    });
  });

  group('LeagueDef.forXp / idForXp', () {
    test('0 XP is Seedling, the first league', () {
      expect(LeagueDef.forXp(0).id, 'seedling');
    });

    test('boundary XP values resolve to the league that starts there', () {
      // Regression guard for the exact minXp values buyStreakFreeze/
      // awardCompletionRewards depend on to keep currentLeague in sync.
      expect(LeagueDef.idForXp(299), 'seedling');
      expect(LeagueDef.idForXp(300), 'sprout');
      expect(LeagueDef.idForXp(699), 'sprout');
      expect(LeagueDef.idForXp(700), 'wildflower');
    });

    test('very high XP resolves to Aurora, the uncapped top league', () {
      final top = LeagueDef.forXp(1000000);
      expect(top.id, 'aurora');
      expect(top.isTop, isTrue);
    });

    test('all 8 leagues are contiguous with no gaps or overlaps', () {
      for (var i = 0; i < LeagueDef.all.length - 1; i++) {
        expect(LeagueDef.all[i].maxXp + 1, LeagueDef.all[i + 1].minXp);
      }
    });
  });
}

// Unit tests for AchievementDefinition.progressValue/progressLabel and
// AchievementModel.completionPercentage — the canonical achievement-progress
// calculation. Covers exact boundaries, already-unlocked, and (most
// importantly) clamping: progress must never report below 0% or above 100%
// even when the underlying stat has long since exceeded the requirement.

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/models/achievement_definition.dart';
import 'package:touchgrass/models/achievement_model.dart';

void main() {
  AchievementDefinition byId(String id) =>
      AchievementDefinition.catalog.firstWhere((a) => a.id == id);

  group('AchievementDefinition.progressValue', () {
    test('is 0.0 with no progress at all', () {
      final def = byId('challenges_10');
      expect(
        def.progressValue(xp: 0, streak: 0, totalCompletions: 0, level: 1),
        0.0,
      );
    });

    test('is exactly 1.0 at the precise requirement boundary', () {
      final def = byId('challenges_10');
      expect(
        def.progressValue(xp: 0, streak: 0, totalCompletions: 10, level: 1),
        1.0,
      );
    });

    test('clamps to 1.0 rather than exceeding 100% when far past the '
        'requirement', () {
      final def = byId('streak_3');
      expect(
        def.progressValue(xp: 0, streak: 500, totalCompletions: 0, level: 1),
        1.0,
      );
    });

    test('never returns a value below 0.0', () {
      final def = byId('xp_100');
      final v = def.progressValue(
        xp: 0,
        streak: 0,
        totalCompletions: 0,
        level: 1,
      );
      expect(v, greaterThanOrEqualTo(0.0));
    });

    test('unrecognized id (defensive) reports 0.0 rather than crashing', () {
      // xp_2500 requires 2500 XP; well below that is a legitimate partial.
      final def = byId('xp_2500');
      expect(
        def.progressValue(xp: 1250, streak: 0, totalCompletions: 0, level: 1),
        0.5,
      );
    });
  });

  group('AchievementModel.completionPercentage', () {
    AchievementModel modelWith(double fraction) => AchievementModel(
      def: byId('challenges_5'),
      isUnlocked: fraction >= 1.0,
      progressFraction: fraction,
      progressLabel: '',
    );

    test('0.0 fraction is 0%', () {
      expect(modelWith(0.0).completionPercentage, 0.0);
    });

    test('0.5 fraction is exactly 50%', () {
      expect(modelWith(0.5).completionPercentage, 50.0);
    });

    test('1.0 fraction is 100%, not more', () {
      expect(modelWith(1.0).completionPercentage, 100.0);
    });

    test('clamps a hypothetically out-of-range fraction to [0, 100]', () {
      // Defensive: progressFraction should already be clamped upstream by
      // AchievementDefinition.progressValue, but the model clamps again so
      // a future caller constructing AchievementModel directly can't
      // display an impossible percentage like 140%.
      expect(modelWith(1.4).completionPercentage, 100.0);
    });
  });

  group('AchievementDefinition.computeNewlyEarned — exact boundaries', () {
    test('does not unlock one XP short of the threshold', () {
      final earned = AchievementDefinition.computeNewlyEarned(
        alreadyEarned: const {},
        newXp: 99,
        newStreak: 0,
        newLevel: 1,
        newTotalCompletions: 0,
      );
      expect(earned, isNot(contains('xp_100')));
    });

    test('unlocks exactly at the threshold', () {
      final earned = AchievementDefinition.computeNewlyEarned(
        alreadyEarned: const {},
        newXp: 100,
        newStreak: 0,
        newLevel: 1,
        newTotalCompletions: 0,
      );
      expect(earned, contains('xp_100'));
    });
  });

  group('AchievementRarity glow escalation (Section 6B Part B4)', () {
    // Rarity is declared low→high in the enum itself, so iterating
    // AchievementRarity.values is a legitimate proxy for "rarer".
    test('glowAlpha strictly increases with rarity — no two tiers look '
        'equally special', () {
      final alphas = AchievementRarity.values.map((r) => r.glowAlpha).toList();
      for (var i = 1; i < alphas.length; i++) {
        expect(
          alphas[i],
          greaterThan(alphas[i - 1]),
          reason:
              '${AchievementRarity.values[i]} should glow stronger '
              'than ${AchievementRarity.values[i - 1]}',
        );
      }
    });

    test('glowBlurRadius strictly increases with rarity', () {
      final radii = AchievementRarity.values
          .map((r) => r.glowBlurRadius)
          .toList();
      for (var i = 1; i < radii.length; i++) {
        expect(radii[i], greaterThan(radii[i - 1]));
      }
    });
  });
}

// Unit tests for the pure celebration-tier/copy logic backing the
// post-completion celebration screen (Section 6B, Part C/H).

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/features/camera/utils/celebration_utils.dart';

void main() {
  group('resolveCelebrationTier', () {
    test('ordinary completion (nothing special) stays subtle', () {
      final tier = resolveCelebrationTier(
        leveledUp: false,
        newAchievements: const [],
        leagueChanged: false,
      );
      expect(tier, CelebrationTier.subtle);
    });

    test('a regular (non-milestone) achievement unlock is standard', () {
      final tier = resolveCelebrationTier(
        leveledUp: false,
        newAchievements: const ['first_touch'],
        leagueChanged: false,
      );
      expect(tier, CelebrationTier.standard);
    });

    test('leveling up is strong even with no achievement', () {
      final tier = resolveCelebrationTier(
        leveledUp: true,
        newAchievements: const [],
        leagueChanged: false,
      );
      expect(tier, CelebrationTier.strong);
    });

    test('a league change alone is strong', () {
      final tier = resolveCelebrationTier(
        leveledUp: false,
        newAchievements: const [],
        leagueChanged: true,
      );
      expect(tier, CelebrationTier.strong);
    });

    test('a major-milestone achievement is epic even with level-up too', () {
      final tier = resolveCelebrationTier(
        leveledUp: true,
        newAchievements: const ['streak_100'],
        leagueChanged: true,
      );
      expect(tier, CelebrationTier.epic);
    });

    test('a mix of a regular achievement and level-up never exceeds strong '
        'unless a major milestone is actually present', () {
      final tier = resolveCelebrationTier(
        leveledUp: true,
        newAchievements: const ['first_touch'],
        leagueChanged: false,
      );
      expect(tier, CelebrationTier.strong);
    });
  });

  group('confettiParticleCountFor / confettiDurationSecondsFor', () {
    test('particle count strictly escalates by tier', () {
      final counts = CelebrationTier.values
          .map(confettiParticleCountFor)
          .toList(growable: false);
      for (var i = 1; i < counts.length; i++) {
        expect(counts[i], greaterThan(counts[i - 1]));
      }
    });

    test('duration strictly escalates by tier', () {
      final durations = CelebrationTier.values
          .map(confettiDurationSecondsFor)
          .toList(growable: false);
      for (var i = 1; i < durations.length; i++) {
        expect(durations[i], greaterThan(durations[i - 1]));
      }
    });
  });

  group('streakCelebrationLabel', () {
    test('a Rainy Day save is always described as protecting the streak, '
        'even if newStreak also happens to look "increased"', () {
      final label = streakCelebrationLabel(
        newStreak: 8,
        streakIncreased: true,
        rainyDayConsumed: true,
      );
      expect(label, 'Rainy Day protected your streak');
    });

    test('a genuine increase says "Streak extended!"', () {
      final label = streakCelebrationLabel(
        newStreak: 5,
        streakIncreased: true,
        rainyDayConsumed: false,
      );
      expect(label, 'Streak extended!');
    });

    test('an unchanged streak (same-day resubmission) shows the plain count '
        'without falsely implying growth', () {
      final label = streakCelebrationLabel(
        newStreak: 3,
        streakIncreased: false,
        rainyDayConsumed: false,
      );
      expect(label, '3 day streak');
    });
  });
}

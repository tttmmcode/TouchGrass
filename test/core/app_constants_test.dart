// Unit tests for AppConstants' canonical XP/level formulas — the single
// source of truth every screen (home trail bar, profile hero, level-up
// celebration) reads from instead of recomputing level math locally.

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/core/constants/app_constants.dart';

void main() {
  group('AppConstants.levelForXp', () {
    test('0 XP is level 1', () {
      expect(AppConstants.levelForXp(0), 1);
    });

    test('99 XP is still level 1 (one short of the boundary)', () {
      expect(AppConstants.levelForXp(99), 1);
    });

    test('100 XP is exactly level 2', () {
      expect(AppConstants.levelForXp(100), 2);
    });

    test('199 XP is still level 2', () {
      expect(AppConstants.levelForXp(199), 2);
    });

    test('200 XP is exactly level 3', () {
      expect(AppConstants.levelForXp(200), 3);
    });

    test('500 XP is level 6', () {
      expect(AppConstants.levelForXp(500), 6);
    });

    test('large XP values scale linearly with no overflow/rounding drift', () {
      expect(AppConstants.levelForXp(999999), 10000);
    });
  });

  group('AppConstants.levelProgress', () {
    test('0 XP is 0% through the level', () {
      expect(AppConstants.levelProgress(0), 0.0);
    });

    test('99 XP is 99% through level 1', () {
      expect(AppConstants.levelProgress(99), closeTo(0.99, 0.0001));
    });

    test('100 XP resets to 0% — the start of level 2, not 100% of level 1', () {
      expect(AppConstants.levelProgress(100), 0.0);
    });

    test('150 XP is exactly 50% through level 2', () {
      expect(AppConstants.levelProgress(150), 0.5);
    });
  });

  group('AppConstants.xpThresholdForLevel', () {
    test('level 1 requires 0 XP', () {
      expect(AppConstants.xpThresholdForLevel(1), 0);
    });

    test('level 2 requires 100 XP', () {
      expect(AppConstants.xpThresholdForLevel(2), 100);
    });

    test('level 6 requires 500 XP — consistent with levelForXp(500) == 6', () {
      expect(AppConstants.xpThresholdForLevel(6), 500);
      expect(AppConstants.levelForXp(500), 6);
    });
  });

  group('AppConstants.weeklyResetLabel', () {
    test('never returns a negative or empty countdown string', () {
      final label = AppConstants.weeklyResetLabel();
      expect(label, isNotEmpty);
      expect(label, isNot(contains('-')));
    });
  });

  group('AppConstants.nextMondayMidnightUtc', () {
    test('is always strictly in the future relative to now', () {
      final next = AppConstants.nextMondayMidnightUtc();
      expect(next.isAfter(DateTime.now().toUtc()), isTrue);
    });

    test('always lands exactly on a Monday at midnight UTC', () {
      final next = AppConstants.nextMondayMidnightUtc();
      expect(next.weekday, DateTime.monday);
      expect(next.hour, 0);
      expect(next.minute, 0);
      expect(next.second, 0);
    });
  });
}

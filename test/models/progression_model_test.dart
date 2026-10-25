// Unit tests for ProgressionModel.fromUser — the single source of truth
// progression UI reads from instead of reaching into UserModel's raw xp/
// streak fields directly. Covers level/XP derivation consistency and the
// isValid() invariant checks.

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/models/progression_model.dart';
import 'package:touchgrass/models/user_model.dart';

void main() {
  UserModel userWith({
    required int xp,
    int streak = 0,
    int longestStreak = 0,
    int rainyDayCount = 0,
  }) => UserModel(
    uid: 'u1',
    email: 'a@b.com',
    username: 'explorer_ab12',
    displayName: 'Explorer',
    xp: xp,
    weeklyXp: 0,
    weeklyXpResetDate: DateTime.utc(2026, 3, 16),
    streak: streak,
    longestStreak: longestStreak,
    totalCompletions: 12,
    totalPhotosUploaded: 12,
    rainyDayCount: rainyDayCount,
    currentLeague: 'seedling',
    createdAt: DateTime.utc(2026, 1, 1),
    lastActiveDate: DateTime.utc(2026, 3, 10),
    achievements: const [],
    settings: UserSettings.defaults(),
  );

  group('ProgressionModel.fromUser', () {
    test('derives level and in-level XP consistently with UserModel', () {
      final user = userWith(xp: 250);
      final p = ProgressionModel.fromUser(user);
      expect(p.currentLevel, 3); // floor(250/100)+1
      expect(p.currentLevelXP, 50); // 250 % 100
      expect(p.totalXP, 250);
    });

    test(
      'levelProgressFraction matches currentLevelXP / xpRequiredForNextLevel',
      () {
        final user = userWith(xp: 250);
        final p = ProgressionModel.fromUser(user);
        expect(p.levelProgressFraction, 0.5);
      },
    );

    test('xpToNextLevel is the remaining distance to the next boundary', () {
      final user = userWith(xp: 250);
      final p = ProgressionModel.fromUser(user);
      expect(p.xpToNextLevel, 50);
    });

    test('levelUpCount is level minus one, never negative', () {
      expect(ProgressionModel.fromUser(userWith(xp: 0)).levelUpCount, 0);
      expect(ProgressionModel.fromUser(userWith(xp: 500)).levelUpCount, 5);
    });

    test('isValid is true for a well-formed user', () {
      final p = ProgressionModel.fromUser(
        userWith(xp: 250, streak: 5, longestStreak: 10),
      );
      expect(p.isValid, isTrue);
    });

    test('a freshly-created user (0 XP, 0 streak) is still valid', () {
      final p = ProgressionModel.fromUser(userWith(xp: 0));
      expect(p.isValid, isTrue);
      expect(p.currentLevel, 1);
      expect(p.currentLevelXP, 0);
    });
  });
}

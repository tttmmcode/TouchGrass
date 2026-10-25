// Unit tests for UserModel.frozenDates — the per-calendar-date record of
// when a Rainy Day freeze absorbed a missed day (added so the streak
// calendar can render a truthful "frozen" state instead of guessing from
// the lifetime streak-freeze counter alone). Covers serialization and, most
// importantly, backward compatibility: existing users' Firestore documents
// predate this field entirely.

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/models/user_model.dart';

void main() {
  UserModel baseUser({List<String> frozenDates = const []}) => UserModel(
    uid: 'u1',
    email: 'a@b.com',
    username: 'explorer_ab12',
    displayName: 'Explorer',
    xp: 100,
    weeklyXp: 20,
    weeklyXpResetDate: DateTime.utc(2026, 3, 16),
    streak: 5,
    longestStreak: 10,
    totalCompletions: 20,
    totalPhotosUploaded: 20,
    rainyDayCount: 1,
    currentLeague: 'sprout',
    createdAt: DateTime.utc(2026, 1, 1),
    lastActiveDate: DateTime.utc(2026, 3, 10),
    achievements: const [],
    settings: UserSettings.defaults(),
    frozenDates: frozenDates,
  );

  group('UserModel.frozenDates', () {
    test('UserModel.initial starts with an empty list', () {
      final user = UserModel.initial(uid: 'u1', displayName: 'Explorer');
      expect(user.frozenDates, isEmpty);
    });

    test('toFirestore round-trips through fromFirestore unchanged', () {
      final user = baseUser(frozenDates: const ['2026-02-14', '2026-03-01']);
      final data = user.toFirestore();
      expect(data['frozenDates'], ['2026-02-14', '2026-03-01']);
    });

    test('copyWith updates frozenDates without touching other fields', () {
      final user = baseUser(frozenDates: const ['2026-02-14']);
      final updated = user.copyWith(
        frozenDates: [...user.frozenDates, '2026-03-01'],
      );
      expect(updated.frozenDates, ['2026-02-14', '2026-03-01']);
      expect(updated.streak, user.streak);
    });

    test('copyWith without frozenDates preserves the existing list', () {
      final user = baseUser(frozenDates: const ['2026-02-14']);
      final updated = user.copyWith(streak: 6);
      expect(updated.frozenDates, ['2026-02-14']);
    });
  });
}

// Unit tests for the pure streak-transition decision extracted from
// UserRepository.awardCompletionRewards (see resolveStreakOutcome). The
// surrounding Firestore read/write can't be exercised without a Firestore
// fake, but this decision logic — the actual streak rules — can be tested
// directly.

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/repositories/user_repository.dart';

void main() {
  final today = DateTime(2026, 3, 10);
  final yesterday = DateTime(2026, 3, 9);
  final twoDaysAgo = DateTime(2026, 3, 8);
  final aWeekAgo = DateTime(2026, 3, 3);

  group('resolveStreakOutcome', () {
    test('same-day re-completion keeps streak unchanged (idempotent)', () {
      final outcome = resolveStreakOutcome(
        today: today,
        lastActiveDay: today,
        currentStreak: 5,
        freezesOwned: 0,
      );
      expect(outcome, const StreakOutcome(newStreak: 5, rainyDayConsumed: false));
    });

    test('next-day completion increments the streak', () {
      final outcome = resolveStreakOutcome(
        today: today,
        lastActiveDay: yesterday,
        currentStreak: 5,
        freezesOwned: 0,
      );
      expect(outcome, const StreakOutcome(newStreak: 6, rainyDayConsumed: false));
    });

    test('one missed day with a freeze available consumes the freeze and '
        'preserves the streak', () {
      final outcome = resolveStreakOutcome(
        today: today,
        lastActiveDay: twoDaysAgo,
        currentStreak: 5,
        freezesOwned: 1,
      );
      expect(outcome, const StreakOutcome(newStreak: 5, rainyDayConsumed: true));
    });

    test('one missed day with no freeze available resets the streak to 1', () {
      final outcome = resolveStreakOutcome(
        today: today,
        lastActiveDay: twoDaysAgo,
        currentStreak: 5,
        freezesOwned: 0,
      );
      expect(outcome, const StreakOutcome(newStreak: 1, rainyDayConsumed: false));
    });

    test('a multi-day gap resets the streak even with freezes available — '
        'a freeze only ever covers a single missed day', () {
      final outcome = resolveStreakOutcome(
        today: today,
        lastActiveDay: aWeekAgo,
        currentStreak: 5,
        freezesOwned: 3,
      );
      expect(outcome, const StreakOutcome(newStreak: 1, rainyDayConsumed: false));
    });

    test('first-ever completion (streak 0, no prior activity) starts at 1', () {
      final outcome = resolveStreakOutcome(
        today: today,
        lastActiveDay: aWeekAgo,
        currentStreak: 0,
        freezesOwned: 0,
      );
      expect(outcome, const StreakOutcome(newStreak: 1, rainyDayConsumed: false));
    });
  });

  group('UserRepository.dateKeyForCalendarDay', () {
    test('formats as zero-padded yyyy-MM-dd', () {
      expect(UserRepository.dateKeyForCalendarDay(DateTime(2026, 3, 5)), '2026-03-05');
    });

    test('pads single-digit months and days', () {
      expect(UserRepository.dateKeyForCalendarDay(DateTime(2026, 1, 9)), '2026-01-09');
    });

    test('matches the streak calendar\'s own key format — the two must stay '
        'in sync since one writes frozenDates and the other reads it', () {
      // Mirrors dateKeyForDay in streak_calendar_screen.dart without
      // importing it here (avoids a test-only cross-feature dependency);
      // this pins the exact string format both sides must agree on.
      final day = DateTime(2026, 7, 4);
      expect(UserRepository.dateKeyForCalendarDay(day), '2026-07-04');
    });
  });
}

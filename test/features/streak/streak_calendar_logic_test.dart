// Unit tests for resolveCalendarDayState — the streak calendar's per-cell
// state resolution. Covers the bug the previous audit flagged ("frozen day
// state is never rendered") and the DST-safety requirement established in
// Section 4 (calendar-field arithmetic, not Duration subtraction, for
// day-boundary comparisons). `now`/`userCreatedAt` are passed in explicitly
// so these tests are deterministic regardless of when they run.

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/features/streak/screens/streak_calendar_screen.dart';

void main() {
  final now = DateTime(2026, 3, 15); // a Sunday, arbitrary fixed "today"

  group('resolveCalendarDayState', () {
    test('a day with a completion is completed', () {
      final state = resolveCalendarDayState(
        day: DateTime(2026, 3, 10),
        now: now,
        completedDates: {dateKeyForDay(DateTime(2026, 3, 10))},
        frozenDates: const {},
      );
      expect(state, CalendarDayState.completed);
    });

    test('today with no completion yet is today, not missed', () {
      final state = resolveCalendarDayState(
        day: now,
        now: now,
        completedDates: const {},
        frozenDates: const {},
      );
      expect(state, CalendarDayState.today);
    });

    test(
      'today with a completion is completed, taking priority over today',
      () {
        final state = resolveCalendarDayState(
          day: now,
          now: now,
          completedDates: {dateKeyForDay(now)},
          frozenDates: const {},
        );
        expect(state, CalendarDayState.completed);
      },
    );

    test('a day after today is future', () {
      final state = resolveCalendarDayState(
        day: DateTime(2026, 3, 20),
        now: now,
        completedDates: const {},
        frozenDates: const {},
      );
      expect(state, CalendarDayState.future);
    });

    test(
      'a past day with neither a completion nor a frozen-date entry is missed',
      () {
        final state = resolveCalendarDayState(
          day: DateTime(2026, 3, 12),
          now: now,
          completedDates: const {},
          frozenDates: const {},
        );
        expect(state, CalendarDayState.missed);
      },
    );

    test(
      'a past day recorded in frozenDates renders as rainyDay, not missed',
      () {
        final frozenDay = DateTime(2026, 3, 12);
        final state = resolveCalendarDayState(
          day: frozenDay,
          now: now,
          completedDates: const {},
          frozenDates: {dateKeyForDay(frozenDay)},
        );
        expect(state, CalendarDayState.rainyDay);
      },
    );

    test('a completion takes priority over a stale frozen-date entry for the '
        'same day', () {
      final day = DateTime(2026, 3, 12);
      final state = resolveCalendarDayState(
        day: day,
        now: now,
        completedDates: {dateKeyForDay(day)},
        frozenDates: {dateKeyForDay(day)},
      );
      expect(state, CalendarDayState.completed);
    });

    test('a day before the user account existed is future, not missed', () {
      final state = resolveCalendarDayState(
        day: DateTime(2026, 3, 1),
        now: now,
        completedDates: const {},
        frozenDates: const {},
        userCreatedAt: DateTime(2026, 3, 5),
      );
      expect(state, CalendarDayState.future);
    });

    test('DST-safety: a frozen day just after a spring-forward boundary is '
        'still matched correctly', () {
      // US spring-forward 2026-03-08. A completion/freeze recorded for
      // 2026-03-09 must still match when looked up via calendar-field
      // construction, the same arithmetic style used to build the key here.
      final day = DateTime(2026, 3, 9);
      final state = resolveCalendarDayState(
        day: day,
        now: DateTime(2026, 3, 15),
        completedDates: const {},
        frozenDates: {dateKeyForDay(DateTime(2026, 3, 9))},
      );
      expect(state, CalendarDayState.rainyDay);
    });
  });

  group('dateKeyForDay', () {
    test('formats as zero-padded yyyy-M-d components', () {
      expect(dateKeyForDay(DateTime(2026, 3, 5)), '2026-03-05');
    });

    test('is stable across DateTime instances representing the same day', () {
      final a = dateKeyForDay(DateTime(2026, 3, 5, 8, 30));
      final b = dateKeyForDay(DateTime(2026, 3, 5, 23, 59));
      expect(a, b);
    });
  });
}

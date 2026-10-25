// Day-boundary regression tests for calendarDateProvider and
// todaysChallengeProvider (audit D-11: today's challenge stayed on
// yesterday's document after midnight while the app was open).
//
// testWidgets runs in fake async time, so the midnight Timer fires when
// the test pumps; the wall clock it reads is injected via wallClockProvider
// and moved in step. DST transitions aren't simulated: the test process's
// time zone can't be changed, and the provider uses calendar-field
// arithmetic (DateTime(y, m, d + 1)) rather than +24h.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/models/challenge_model.dart';
import 'package:touchgrass/providers/auth_providers.dart';
import 'package:touchgrass/providers/challenge_providers.dart';
import 'package:touchgrass/repositories/challenge_repository.dart';

class _FakeClock {
  _FakeClock(this.now);
  DateTime now;

  /// Moves the wall clock to [to] and fake time forward by [elapsed]
  /// (defaults to the same distance), firing any timers that fall due.
  Future<void> advance(
    WidgetTester tester,
    Duration elapsed, {
    DateTime? to,
  }) async {
    now = to ?? now.add(elapsed);
    await tester.pump(elapsed);
  }
}

class _FakeUser implements User {
  @override
  String get uid => 'alice';
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Records which day's challenge document each subscription targets.
class _RecordingChallengeRepository implements ChallengeRepository {
  final docIds = <String>[];
  @override
  Stream<ChallengeModel?> watchChallengeForDate(String uid, DateTime date) {
    docIds.add(ChallengeModel.docIdForDate(date));
    return Stream.value(null);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  ProviderContainer containerAt(
    _FakeClock clock, {
    List<Override> extra = const [],
  }) => ProviderContainer(
    overrides: [wallClockProvider.overrideWithValue(() => clock.now), ...extra],
  );

  group('calendarDateProvider', () {
    testWidgets('starts on the local calendar date, time stripped', (
      tester,
    ) async {
      final clock = _FakeClock(DateTime(2026, 3, 10, 14, 30));
      final c = containerAt(clock);
      expect(c.read(calendarDateProvider), DateTime(2026, 3, 10));
      c.dispose();
    });

    testWidgets('does not change one second before midnight', (tester) async {
      final clock = _FakeClock(DateTime(2026, 3, 10, 23, 59, 30));
      final c = containerAt(clock);
      c.read(calendarDateProvider);
      await clock.advance(tester, const Duration(seconds: 29));
      expect(c.read(calendarDateProvider), DateTime(2026, 3, 10));
      c.dispose();
    });

    testWidgets('rolls over exactly at midnight, and again the next midnight', (
      tester,
    ) async {
      final clock = _FakeClock(DateTime(2026, 3, 10, 23, 59, 30));
      final c = containerAt(clock);
      final seen = <DateTime>[];
      c.listen(
        calendarDateProvider,
        (_, next) => seen.add(next),
        fireImmediately: true,
      );

      await clock.advance(tester, const Duration(seconds: 30));
      expect(c.read(calendarDateProvider), DateTime(2026, 3, 11));

      await clock.advance(tester, const Duration(hours: 24));
      expect(c.read(calendarDateProvider), DateTime(2026, 3, 12));
      expect(seen, [
        DateTime(2026, 3, 10),
        DateTime(2026, 3, 11),
        DateTime(2026, 3, 12),
      ]);
      c.dispose();
    });

    for (final (label, start, next) in [
      ('month end', DateTime(2026, 2, 28, 23, 59), DateTime(2026, 3, 1)),
      ('year end', DateTime(2026, 12, 31, 23, 59), DateTime(2027, 1, 1)),
      ('leap day', DateTime(2028, 2, 28, 23, 59), DateTime(2028, 2, 29)),
    ]) {
      testWidgets('rolls over across a $label', (tester) async {
        final clock = _FakeClock(start);
        final c = containerAt(clock);
        c.read(calendarDateProvider);
        await clock.advance(tester, const Duration(minutes: 1));
        expect(c.read(calendarDateProvider), next);
        c.dispose();
      });
    }

    testWidgets(
      'a timer that fires early keeps the date and re-arms for midnight',
      (tester) async {
        final clock = _FakeClock(DateTime(2026, 3, 10, 23, 59, 30));
        final c = containerAt(clock);
        c.read(calendarDateProvider);

        // The timer is due after 30 s, but the wall clock only reached 23:59:59.5.
        await clock.advance(
          tester,
          const Duration(seconds: 30),
          to: DateTime(2026, 3, 10, 23, 59, 59, 500),
        );
        expect(c.read(calendarDateProvider), DateTime(2026, 3, 10));

        await clock.advance(tester, const Duration(milliseconds: 500));
        expect(c.read(calendarDateProvider), DateTime(2026, 3, 11));
        c.dispose();
      },
    );

    testWidgets(
      'a timer that fires late (device asleep) lands on the real date',
      (tester) async {
        final clock = _FakeClock(DateTime(2026, 3, 10, 23, 59, 30));
        final c = containerAt(clock);
        c.read(calendarDateProvider);
        await clock.advance(
          tester,
          const Duration(seconds: 30),
          to: DateTime(2026, 3, 11, 7, 15),
        );
        expect(c.read(calendarDateProvider), DateTime(2026, 3, 11));
        c.dispose();
      },
    );
  });

  group('todaysChallengeProvider (D-11)', () {
    testWidgets('switches to the new day\'s challenge document at midnight', (
      tester,
    ) async {
      final clock = _FakeClock(DateTime(2026, 3, 10, 23, 59, 30));
      final repo = _RecordingChallengeRepository();
      final c = containerAt(
        clock,
        extra: [
          authStateProvider.overrideWith((ref) => Stream.value(_FakeUser())),
          challengeRepositoryProvider.overrideWithValue(repo),
        ],
      );
      final sub = c.listen(todaysChallengeProvider, (_, _) {});
      // Let the signed-in user arrive and the provider subscribe.
      await clock.advance(tester, const Duration(milliseconds: 1));
      await clock.advance(tester, const Duration(milliseconds: 1));
      expect(repo.docIds.last, '2026-03-10');

      // Exactly midnight, then 1 ms for the provider to resubscribe.
      await clock.advance(
        tester,
        const Duration(seconds: 29, milliseconds: 998),
      );
      await clock.advance(tester, const Duration(milliseconds: 1));
      expect(repo.docIds.last, '2026-03-11');
      expect(repo.docIds, isNot(contains('2026-03-12')));
      sub.close();
      c.dispose();
    });
  });
}

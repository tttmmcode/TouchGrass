import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/features/profile/utils/member_since.dart';

void main() {
  group('memberSinceDuration', () {
    test('same day returns Today', () {
      final now = DateTime(2026, 8, 10, 18, 0);
      expect(
        memberSinceDuration(createdAt: DateTime(2026, 8, 10, 6, 0), now: now),
        'Today',
      );
    });

    test('exactly 1 day uses singular "day"', () {
      final now = DateTime(2026, 8, 10);
      expect(
        memberSinceDuration(createdAt: DateTime(2026, 8, 9), now: now),
        '1 day',
      );
    });

    test('under 30 days uses plural "days"', () {
      final now = DateTime(2026, 8, 10);
      expect(
        memberSinceDuration(createdAt: DateTime(2026, 7, 25), now: now),
        '16 days',
      );
    });

    test('exactly 1 month uses singular "month"', () {
      final now = DateTime(2026, 9, 10);
      expect(
        memberSinceDuration(createdAt: DateTime(2026, 8, 10), now: now),
        '1 month',
      );
    });

    test('a few months uses plural "months"', () {
      final now = DateTime(2026, 11, 10);
      expect(
        memberSinceDuration(createdAt: DateTime(2026, 8, 10), now: now),
        '3 months',
      );
    });

    test(
      'month boundary not yet reached (day-of-month not passed) stays in the previous month count',
      () {
        final now = DateTime(2026, 11, 5);
        // Joined Aug 10; by Nov 5 only 2 full months have elapsed (the Nov 10
        // anniversary hasn't happened yet), not 3.
        expect(
          memberSinceDuration(createdAt: DateTime(2026, 8, 10), now: now),
          '2 months',
        );
      },
    );

    test('exactly 1 year uses singular "year"', () {
      final now = DateTime(2027, 8, 10);
      expect(
        memberSinceDuration(createdAt: DateTime(2026, 8, 10), now: now),
        '1 year',
      );
    });

    test('multiple years uses plural "years"', () {
      final now = DateTime(2029, 3, 1);
      expect(
        memberSinceDuration(createdAt: DateTime(2026, 8, 10), now: now),
        '2 years',
      );
    });

    test(
      'year boundary not yet reached stays in months, not a premature year',
      () {
        final now = DateTime(2027, 8, 5);
        // Joined Aug 10 2026; by Aug 5 2027 the anniversary hasn't happened
        // yet (day 5 < day 10), so this should still read in months.
        expect(
          memberSinceDuration(createdAt: DateTime(2026, 8, 10), now: now),
          '11 months',
        );
      },
    );

    test(
      'never returns a negative duration for a clock-skewed createdAt in the future',
      () {
        final now = DateTime(2026, 8, 10);
        expect(
          memberSinceDuration(createdAt: DateTime(2026, 8, 15), now: now),
          'Today',
        );
      },
    );
  });
}

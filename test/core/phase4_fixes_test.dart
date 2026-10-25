// Regression tests for the Phase 4 audit fixes: D-17 (DST-safe day counts),
// S-10 (notification deep links), D-20 (profile-photo picker errors) and
// D-21 (one-off analytics events). D-14 is covered in
// test/providers/location_privacy_test.dart; S-9 in camera_providers_test.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/core/constants/route_names.dart';
import 'package:touchgrass/core/utils/calendar_days.dart';
import 'package:touchgrass/features/profile/utils/member_since.dart';
import 'package:touchgrass/features/settings/screens/settings_screen.dart';
import 'package:touchgrass/providers/user_providers.dart';

void main() {
  group('D-17 calendarDaysBetween', () {
    test(
      'every consecutive local day of 2026 counts as exactly 1 day (DST included)',
      () {
        var day = DateTime(2026, 1, 1);
        for (var i = 1; i <= 365; i++) {
          final next = DateTime(2026, 1, 1 + i);
          expect(calendarDaysBetween(day, next), 1, reason: '$day → $next');
          expect(calendarDaysBetween(DateTime(2026, 1, 1), next), i);
          day = next;
        }
      },
    );

    test('ignores the time of day and the UTC flag of the inputs', () {
      expect(
        calendarDaysBetween(
          DateTime(2026, 3, 7, 23, 59),
          DateTime(2026, 3, 8, 0, 1),
        ),
        1,
      );
      expect(
        calendarDaysBetween(DateTime.utc(2026, 3, 7), DateTime.utc(2026, 3, 9)),
        2,
      );
      expect(
        calendarDaysBetween(DateTime(2026, 3, 9), DateTime(2026, 3, 8)),
        -1,
      );
    });

    test(
      'where this machine observes DST, the old inDays method is one short',
      () {
        // US spring-forward 2026 is 8 March; in a DST zone that local day has
        // 23 hours. Only asserts the old bug where it can actually happen.
        final from = DateTime(2026, 3, 8);
        final to = DateTime(2026, 3, 9);
        if (to.difference(from).inHours == 23) {
          expect(
            to.difference(from).inDays,
            0,
            reason: 'the old, buggy method',
          );
        }
        expect(calendarDaysBetween(from, to), 1);
      },
    );

    test('Member Since counts across a spring-forward night', () {
      expect(
        memberSinceDuration(
          createdAt: DateTime(2026, 3, 7, 10),
          now: DateTime(2026, 3, 9, 10),
        ),
        '2 days',
      );
    });
  });

  group('S-10 safeNotificationRoute', () {
    test('known in-app routes are followed', () {
      for (final r in [
        RouteNames.home,
        RouteNames.map,
        RouteNames.leaderboard,
        RouteNames.profile,
        RouteNames.achievements,
        RouteNames.camera,
        RouteNames.settings,
        RouteNames.streakCalendar,
        RouteNames.companionSelect,
        RouteNames.challengeDetail('2026-10-17'),
      ]) {
        expect(safeNotificationRoute(r), r);
      }
    });

    test('anything else falls back to Home', () {
      for (final r in <Object?>[
        null,
        42,
        '',
        'home',
        '/unknown',
        '/login',
        '/',
        '/onboarding',
        'https://evil.example/phish',
        '//evil.example',
        'javascript:alert(1)',
        '/home?redirect=https://evil.example',
        '/challenge/../profile/settings',
        '/challenge/',
        '/challenge/${'x' * 65}',
        '/profile/settings/../../login',
      ]) {
        expect(safeNotificationRoute(r), RouteNames.home, reason: '$r');
      }
    });
  });

  group('D-20 profilePhotoPickErrorMessage', () {
    test('denied camera or photo access explains how to allow it', () {
      expect(
        profilePhotoPickErrorMessage(
          PlatformException(code: 'camera_access_denied'),
        ),
        contains('allow camera access'),
      );
      expect(
        profilePhotoPickErrorMessage(
          PlatformException(code: 'photo_access_denied'),
        ),
        contains('allow photo access'),
      );
    });
    test('anything else is a short retry message with no raw error text', () {
      final msg = profilePhotoPickErrorMessage(
        PlatformException(
          code: 'unknown',
          message: 'java.lang.SecurityException: uid 10123',
        ),
      );
      expect(msg, "Couldn't open that photo. Please try again.");
      expect(
        profilePhotoPickErrorMessage(StateError('boom')),
        isNot(contains('boom')),
      );
    });
  });

  group('D-21 claimSessionEvent', () {
    setUp(resetSessionEventsForTest);
    test('a one-off event is claimed once per session, per key', () {
      expect(claimSessionEvent('retention:u1:7'), isTrue);
      expect(
        claimSessionEvent('retention:u1:7'),
        isFalse,
        reason: 'profile updated again',
      );
      expect(
        claimSessionEvent('retention:u2:7'),
        isTrue,
        reason: 'another account',
      );
    });
  });
}

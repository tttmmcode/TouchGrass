import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/core/utils/sunrise_sunset.dart';
import 'package:touchgrass/models/app_theme_mode.dart';

void main() {
  group('isDaytime', () {
    // A representative day: sunrise 6:30am, sunset 8:15pm.
    final sunrise = DateTime(2026, 6, 15, 6, 30);
    final sunset = DateTime(2026, 6, 15, 20, 15);

    test('before sunrise is night', () {
      expect(
        isDaytime(
          now: DateTime(2026, 6, 15, 5, 0),
          sunrise: sunrise,
          sunset: sunset,
        ),
        isFalse,
      );
    });

    test('exactly at sunrise is not yet day (exclusive boundary)', () {
      expect(
        isDaytime(now: sunrise, sunrise: sunrise, sunset: sunset),
        isFalse,
      );
    });

    test('just after sunrise is day', () {
      expect(
        isDaytime(
          now: DateTime(2026, 6, 15, 6, 31),
          sunrise: sunrise,
          sunset: sunset,
        ),
        isTrue,
      );
    });

    test('midday is day', () {
      expect(
        isDaytime(
          now: DateTime(2026, 6, 15, 12, 0),
          sunrise: sunrise,
          sunset: sunset,
        ),
        isTrue,
      );
    });

    test('just before sunset is day', () {
      expect(
        isDaytime(
          now: DateTime(2026, 6, 15, 20, 14),
          sunrise: sunrise,
          sunset: sunset,
        ),
        isTrue,
      );
    });

    test('exactly at sunset is not day anymore (exclusive boundary)', () {
      expect(isDaytime(now: sunset, sunrise: sunrise, sunset: sunset), isFalse);
    });

    test('after sunset is night', () {
      expect(
        isDaytime(
          now: DateTime(2026, 6, 15, 21, 0),
          sunrise: sunrise,
          sunset: sunset,
        ),
        isFalse,
      );
    });

    test('midnight (start of the cached day) is night', () {
      expect(
        isDaytime(
          now: DateTime(2026, 6, 15, 0, 0),
          sunrise: sunrise,
          sunset: sunset,
        ),
        isFalse,
      );
    });

    test('midnight crossing into the next day (before that day\'s real '
        'sunrise) still reads as night even against yesterday\'s cached '
        'sunrise/sunset', () {
      expect(
        isDaytime(
          now: DateTime(2026, 6, 16, 0, 30),
          sunrise: sunrise,
          sunset: sunset,
        ),
        isFalse,
      );
    });

    test('data stale by more than a day reads as night, not a crash or a '
        'guess — once now has passed the cached sunset, it can never be '
        '"before sunset" again until the cache actually refreshes with a '
        'new day\'s values', () {
      // now is 2026-06-16 noon, but sunrise/sunset are still 06-15's values
      // — comparing full timestamps (not bare times-of-day) means this
      // correctly falls outside [sunrise, sunset) even though the time-of-
      // day (noon) would normally be daytime; a stale cache degrades to
      // "always dark" rather than silently assuming the wrong thing. In
      // practice this window is brief since weatherProvider (which supplies
      // these values) refetches on every app foreground/open plus every 30
      // minutes while active.
      expect(
        isDaytime(
          now: DateTime(2026, 6, 16, 12, 0),
          sunrise: sunrise,
          sunset: sunset,
        ),
        isFalse,
      );
    });

    test('handles a high-latitude short-day case (sunrise and sunset both '
        'in the afternoon) without throwing', () {
      final shortDaySunrise = DateTime(2026, 12, 21, 15, 0);
      final shortDaySunset = DateTime(2026, 12, 21, 15, 45);
      expect(
        isDaytime(
          now: DateTime(2026, 12, 21, 15, 20),
          sunrise: shortDaySunrise,
          sunset: shortDaySunset,
        ),
        isTrue,
      );
      expect(
        isDaytime(
          now: DateTime(2026, 12, 21, 10, 0),
          sunrise: shortDaySunrise,
          sunset: shortDaySunset,
        ),
        isFalse,
      );
    });
  });

  group('resolveEffectiveThemeMode', () {
    final sunrise = DateTime(2026, 6, 15, 6, 30);
    final sunset = DateTime(2026, 6, 15, 20, 15);

    test('system mode always returns ThemeMode.system regardless of time or '
        'sunrise/sunset', () {
      expect(
        resolveEffectiveThemeMode(
          appMode: AppThemeMode.system,
          now: DateTime(2026, 6, 15, 12, 0),
          sunrise: sunrise,
          sunset: sunset,
        ),
        ThemeMode.system,
      );
    });

    test('light mode always returns ThemeMode.light even at night', () {
      expect(
        resolveEffectiveThemeMode(
          appMode: AppThemeMode.light,
          now: DateTime(2026, 6, 15, 23, 0),
        ),
        ThemeMode.light,
      );
    });

    test('dark mode always returns ThemeMode.dark even at midday', () {
      expect(
        resolveEffectiveThemeMode(
          appMode: AppThemeMode.dark,
          now: DateTime(2026, 6, 15, 12, 0),
        ),
        ThemeMode.dark,
      );
    });

    test('automatic mode resolves to light during the day', () {
      expect(
        resolveEffectiveThemeMode(
          appMode: AppThemeMode.automatic,
          now: DateTime(2026, 6, 15, 12, 0),
          sunrise: sunrise,
          sunset: sunset,
        ),
        ThemeMode.light,
      );
    });

    test('automatic mode resolves to dark at night', () {
      expect(
        resolveEffectiveThemeMode(
          appMode: AppThemeMode.automatic,
          now: DateTime(2026, 6, 15, 23, 0),
          sunrise: sunrise,
          sunset: sunset,
        ),
        ThemeMode.dark,
      );
    });

    test('automatic mode falls back to system when sunrise/sunset are '
        'unavailable — missing location permission or a not-yet-resolved '
        'weather fetch, never a crash or a guess', () {
      expect(
        resolveEffectiveThemeMode(
          appMode: AppThemeMode.automatic,
          now: DateTime(2026, 6, 15, 12, 0),
          sunrise: null,
          sunset: null,
        ),
        ThemeMode.system,
      );
    });

    test('automatic mode falls back to system when only one of '
        'sunrise/sunset is available (malformed API response)', () {
      expect(
        resolveEffectiveThemeMode(
          appMode: AppThemeMode.automatic,
          now: DateTime(2026, 6, 15, 12, 0),
          sunrise: sunrise,
          sunset: null,
        ),
        ThemeMode.system,
      );
    });

    test('automatic mode with invalid data (sunset before sunrise) degrades '
        'to always-dark rather than throwing or producing a nonsensical '
        'result', () {
      final invertedSunrise = DateTime(2026, 6, 15, 20, 0);
      final invertedSunset = DateTime(2026, 6, 15, 6, 0);
      expect(
        () => resolveEffectiveThemeMode(
          appMode: AppThemeMode.automatic,
          now: DateTime(2026, 6, 15, 12, 0),
          sunrise: invertedSunrise,
          sunset: invertedSunset,
        ),
        returnsNormally,
      );
      expect(
        resolveEffectiveThemeMode(
          appMode: AppThemeMode.automatic,
          now: DateTime(2026, 6, 15, 12, 0),
          sunrise: invertedSunrise,
          sunset: invertedSunset,
        ),
        ThemeMode.dark,
      );
    });
  });
}

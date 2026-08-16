import 'package:flutter/material.dart';

import '../../models/app_theme_mode.dart';

/// Whether [now] falls between [sunrise] and [sunset] — the pure decision
/// behind "Automatic (Sunrise/Sunset)" theme mode, extracted so it's directly
/// testable without a real clock, GPS fix, or network call.
///
/// [sunrise]/[sunset] are real [DateTime]s for a specific calendar day (not
/// bare times-of-day) so the boundaries are unambiguous, but this means the
/// result is only meaningful for the same day the values were fetched for:
/// once [now] moves past a cached [sunset], every later time reads as
/// "night" — including the *next* day's actual daytime — until the cache is
/// refreshed with a fresh day's sunrise/sunset. That's a deliberate,
/// conservative degradation (dark, not a crash or a wrong guess) for the
/// brief window before a refresh, not a claim that stale data stays broadly
/// accurate — see the test file for the exact boundary cases this covers.
bool isDaytime({
  required DateTime now,
  required DateTime sunrise,
  required DateTime sunset,
}) {
  return now.isAfter(sunrise) && now.isBefore(sunset);
}

/// The full decision behind [themeModeProvider] in settings_providers.dart,
/// extracted as a pure function so every branch — including the fallback
/// paths — is directly unit-testable without a Riverpod [ProviderContainer]
/// or a real weather fetch.
///
/// Falls back to [ThemeMode.system] whenever [appMode] is
/// [AppThemeMode.automatic] but [sunrise]/[sunset] aren't available (no
/// location permission, weather hasn't resolved yet, or the API response
/// simply didn't include them) — this is the "handle location permission
/// denial gracefully" / "sensible fallback behavior" requirement. Malformed
/// data where [sunset] isn't after [sunrise] degrades safely too: [isDaytime]
/// can then never be true, so it just always resolves to dark rather than
/// producing a nonsensical or crashing result.
ThemeMode resolveEffectiveThemeMode({
  required AppThemeMode appMode,
  required DateTime now,
  DateTime? sunrise,
  DateTime? sunset,
}) {
  switch (appMode) {
    case AppThemeMode.system:
      return ThemeMode.system;
    case AppThemeMode.light:
      return ThemeMode.light;
    case AppThemeMode.dark:
      return ThemeMode.dark;
    case AppThemeMode.automatic:
      if (sunrise == null || sunset == null) return ThemeMode.system;
      return isDaytime(now: now, sunrise: sunrise, sunset: sunset)
          ? ThemeMode.light
          : ThemeMode.dark;
  }
}

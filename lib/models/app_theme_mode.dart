import 'package:flutter/material.dart';

/// The user's theme preference — a superset of Flutter's own [ThemeMode]
/// (which only has system/light/dark) adding [automatic], which resolves to
/// light or dark based on local sunrise/sunset rather than the OS setting.
///
/// Declared in the same order as [ThemeMode.system]/[ThemeMode.light]/
/// [ThemeMode.dark] (indices 0/1/2) so existing persisted preference values
/// (stored as a plain int index) keep meaning exactly what they always did —
/// [automatic] only ever appears as a new index 3 for users who explicitly
/// pick it going forward.
enum AppThemeMode { system, light, dark, automatic }

extension AppThemeModeX on AppThemeMode {
  String get displayName => switch (this) {
    AppThemeMode.system => 'System',
    AppThemeMode.light => 'Light',
    AppThemeMode.dark => 'Dark',
    AppThemeMode.automatic => 'Automatic',
  };

  IconData get icon => switch (this) {
    AppThemeMode.system => Icons.brightness_auto_rounded,
    AppThemeMode.light => Icons.light_mode_outlined,
    AppThemeMode.dark => Icons.dark_mode_outlined,
    AppThemeMode.automatic => Icons.wb_twilight_rounded,
  };
}

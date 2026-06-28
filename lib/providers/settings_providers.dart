import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../services/auth_service.dart';
import 'user_providers.dart';

// ── State ─────────────────────────────────────────────────────────────────────

@immutable
class SettingsState {
  const SettingsState({
    this.dailyNotifications = true,
    this.streakNotifications = true,
    this.leagueNotifications = true,
    this.achievementNotifications = true,
    this.themeMode = ThemeMode.system,
    this.textScale = 1.0,
    this.reducedMotion = false,
    this.highContrast = false,
    this.preferredCategories = const [],
  });

  final bool dailyNotifications;
  final bool streakNotifications;
  final bool leagueNotifications;
  final bool achievementNotifications;
  final ThemeMode themeMode;
  final double textScale;
  final bool reducedMotion;
  final bool highContrast;

  /// Empty list means "all categories" (no filter).
  final List<String> preferredCategories;

  SettingsState copyWith({
    bool? dailyNotifications,
    bool? streakNotifications,
    bool? leagueNotifications,
    bool? achievementNotifications,
    ThemeMode? themeMode,
    double? textScale,
    bool? reducedMotion,
    bool? highContrast,
    List<String>? preferredCategories,
  }) =>
      SettingsState(
        dailyNotifications: dailyNotifications ?? this.dailyNotifications,
        streakNotifications: streakNotifications ?? this.streakNotifications,
        leagueNotifications: leagueNotifications ?? this.leagueNotifications,
        achievementNotifications:
            achievementNotifications ?? this.achievementNotifications,
        themeMode: themeMode ?? this.themeMode,
        textScale: textScale ?? this.textScale,
        reducedMotion: reducedMotion ?? this.reducedMotion,
        highContrast: highContrast ?? this.highContrast,
        preferredCategories: preferredCategories ?? this.preferredCategories,
      );

  static const _keyDaily = 'pref_daily_notifications';
  static const _keyStreak = 'pref_streak_notifications';
  static const _keyLeague = 'pref_league_notifications';
  static const _keyAchievement = 'pref_achievement_notifications';
  static const _keyThemeMode = 'pref_theme_mode';
  static const _keyTextScale = 'pref_text_scale';
  static const _keyReducedMotion = 'pref_reduced_motion';
  static const _keyHighContrast = 'pref_high_contrast';
  static const _keyCategories = 'pref_preferred_categories';

  static SettingsState fromPrefs(SharedPreferences prefs) => SettingsState(
        dailyNotifications: prefs.getBool(_keyDaily) ?? true,
        streakNotifications: prefs.getBool(_keyStreak) ?? true,
        leagueNotifications: prefs.getBool(_keyLeague) ?? true,
        achievementNotifications: prefs.getBool(_keyAchievement) ?? true,
        themeMode: ThemeMode.values[prefs.getInt(_keyThemeMode) ?? 0],
        textScale: prefs.getDouble(_keyTextScale) ?? 1.0,
        reducedMotion: prefs.getBool(_keyReducedMotion) ?? false,
        highContrast: prefs.getBool(_keyHighContrast) ?? false,
        preferredCategories: prefs.getStringList(_keyCategories) ?? const [],
      );

  Future<void> persist(SharedPreferences prefs) async {
    await Future.wait([
      prefs.setBool(_keyDaily, dailyNotifications),
      prefs.setBool(_keyStreak, streakNotifications),
      prefs.setBool(_keyLeague, leagueNotifications),
      prefs.setBool(_keyAchievement, achievementNotifications),
      prefs.setInt(_keyThemeMode, themeMode.index),
      prefs.setDouble(_keyTextScale, textScale),
      prefs.setBool(_keyReducedMotion, reducedMotion),
      prefs.setBool(_keyHighContrast, highContrast),
      prefs.setStringList(_keyCategories, preferredCategories),
    ]);
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class SettingsNotifier extends StateNotifier<AsyncValue<SettingsState>> {
  SettingsNotifier({required AuthService authService})
      : _auth = authService,
        super(const AsyncValue.loading());

  final AuthService _auth;
  SharedPreferences? _prefs;

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      state = AsyncValue.data(SettingsState.fromPrefs(_prefs!));
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<void> toggleDailyNotifications() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final next =
        current.copyWith(dailyNotifications: !current.dailyNotifications);
    state = AsyncValue.data(next);
    final p = _prefs;
    if (p != null) await next.persist(p);
    if (!kIsWeb) {
      if (next.dailyNotifications) {
        await FirebaseMessaging.instance
            .subscribeToTopic(AppConstants.fcmTopicDaily);
      } else {
        await FirebaseMessaging.instance
            .unsubscribeFromTopic(AppConstants.fcmTopicDaily);
      }
    }
  }

  Future<void> toggleStreakNotifications() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final next =
        current.copyWith(streakNotifications: !current.streakNotifications);
    state = AsyncValue.data(next);
    final p = _prefs;
    if (p != null) await next.persist(p);
    if (!kIsWeb) {
      if (next.streakNotifications) {
        await FirebaseMessaging.instance
            .subscribeToTopic(AppConstants.fcmTopicStreakWarning);
      } else {
        await FirebaseMessaging.instance
            .unsubscribeFromTopic(AppConstants.fcmTopicStreakWarning);
      }
    }
  }

  Future<void> toggleLeagueNotifications() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final next =
        current.copyWith(leagueNotifications: !current.leagueNotifications);
    state = AsyncValue.data(next);
    final p = _prefs;
    if (p != null) await next.persist(p);
    if (!kIsWeb) {
      if (next.leagueNotifications) {
        await FirebaseMessaging.instance
            .subscribeToTopic(AppConstants.fcmTopicLeague);
      } else {
        await FirebaseMessaging.instance
            .unsubscribeFromTopic(AppConstants.fcmTopicLeague);
      }
    }
  }

  Future<void> toggleAchievementNotifications() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = current.copyWith(
        achievementNotifications: !current.achievementNotifications);
    state = AsyncValue.data(next);
    final p = _prefs;
    if (p != null) await next.persist(p);
    if (!kIsWeb) {
      if (next.achievementNotifications) {
        await FirebaseMessaging.instance
            .subscribeToTopic(AppConstants.fcmTopicAchievement);
      } else {
        await FirebaseMessaging.instance
            .unsubscribeFromTopic(AppConstants.fcmTopicAchievement);
      }
    }
  }

  Future<void> toggleReducedMotion() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = current.copyWith(reducedMotion: !current.reducedMotion);
    state = AsyncValue.data(next);
    final p = _prefs;
    if (p != null) await next.persist(p);
  }

  Future<void> toggleHighContrast() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = current.copyWith(highContrast: !current.highContrast);
    state = AsyncValue.data(next);
    final p = _prefs;
    if (p != null) await next.persist(p);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = current.copyWith(themeMode: mode);
    state = AsyncValue.data(next);
    final p = _prefs;
    if (p != null) await next.persist(p);
  }

  Future<void> setTextScale(double scale) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = current.copyWith(textScale: scale);
    state = AsyncValue.data(next);
    final p = _prefs;
    if (p != null) await next.persist(p);
  }

  Future<void> setPreferredCategories(List<String> categories) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = current.copyWith(preferredCategories: List.unmodifiable(categories));
    state = AsyncValue.data(next);
    final p = _prefs;
    if (p != null) await next.persist(p);
  }

  Future<void> signOut() => _auth.signOut();
}

// ── Provider ──────────────────────────────────────────────────────────────────

final settingsProvider = StateNotifierProvider.autoDispose<SettingsNotifier,
    AsyncValue<SettingsState>>((ref) {
  final notifier = SettingsNotifier(
    authService: ref.watch(authServiceProvider),
  );
  notifier.init();
  return notifier;
});

/// Exposes the persisted [ThemeMode] to the root widget tree.
final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(settingsProvider).valueOrNull?.themeMode ?? ThemeMode.system;
});

/// Exposes the persisted text scale factor to the root widget tree.
final textScaleProvider = Provider<double>((ref) {
  return ref.watch(settingsProvider).valueOrNull?.textScale ?? 1.0;
});

/// Whether the user has enabled reduced motion.
final reducedMotionProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).valueOrNull?.reducedMotion ?? false;
});

/// Whether the user has enabled high contrast mode.
final highContrastProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).valueOrNull?.highContrast ?? false;
});

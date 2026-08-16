import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/accessibility_prefs.dart';
import '../core/utils/sunrise_sunset.dart';
import '../models/app_theme_mode.dart';
import '../repositories/user_repository.dart';
import '../services/auth_service.dart';
import 'user_providers.dart';
import 'weather_providers.dart';

// ── State ─────────────────────────────────────────────────────────────────────

@immutable
class SettingsState {
  const SettingsState({
    this.dailyNotifications = true,
    this.streakNotifications = true,
    this.leagueNotifications = true,
    this.achievementNotifications = true,
    this.themeMode = AppThemeMode.system,
    this.textScale = 1.0,
    this.reducedMotion = false,
    this.highContrast = false,
  });

  final bool dailyNotifications;
  final bool streakNotifications;
  final bool leagueNotifications;
  final bool achievementNotifications;
  final AppThemeMode themeMode;
  final double textScale;
  final bool reducedMotion;
  final bool highContrast;

  SettingsState copyWith({
    bool? dailyNotifications,
    bool? streakNotifications,
    bool? leagueNotifications,
    bool? achievementNotifications,
    AppThemeMode? themeMode,
    double? textScale,
    bool? reducedMotion,
    bool? highContrast,
  }) => SettingsState(
    dailyNotifications: dailyNotifications ?? this.dailyNotifications,
    streakNotifications: streakNotifications ?? this.streakNotifications,
    leagueNotifications: leagueNotifications ?? this.leagueNotifications,
    achievementNotifications:
        achievementNotifications ?? this.achievementNotifications,
    themeMode: themeMode ?? this.themeMode,
    textScale: textScale ?? this.textScale,
    reducedMotion: reducedMotion ?? this.reducedMotion,
    highContrast: highContrast ?? this.highContrast,
  );

  static const _keyDaily = 'pref_daily_notifications';
  static const _keyStreak = 'pref_streak_notifications';
  static const _keyLeague = 'pref_league_notifications';
  static const _keyAchievement = 'pref_achievement_notifications';
  static const _keyThemeMode = 'pref_theme_mode';
  static const _keyTextScale = 'pref_text_scale';
  static const _keyReducedMotion = 'pref_reduced_motion';
  static const _keyHighContrast = 'pref_high_contrast';

  static SettingsState fromPrefs(SharedPreferences prefs) => SettingsState(
    dailyNotifications: prefs.getBool(_keyDaily) ?? true,
    streakNotifications: prefs.getBool(_keyStreak) ?? true,
    leagueNotifications: prefs.getBool(_keyLeague) ?? true,
    achievementNotifications: prefs.getBool(_keyAchievement) ?? true,
    themeMode: AppThemeMode.values[prefs.getInt(_keyThemeMode) ?? 0],
    textScale: prefs.getDouble(_keyTextScale) ?? 1.0,
    reducedMotion: prefs.getBool(_keyReducedMotion) ?? false,
    highContrast: prefs.getBool(_keyHighContrast) ?? false,
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
    ]);
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class SettingsNotifier extends StateNotifier<AsyncValue<SettingsState>> {
  SettingsNotifier({
    required AuthService authService,
    required UserRepository userRepository,
  }) : _auth = authService,
       _users = userRepository,
       super(const AsyncValue.loading());

  final AuthService _auth;
  final UserRepository _users;
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
    final next = current.copyWith(
      dailyNotifications: !current.dailyNotifications,
    );
    state = AsyncValue.data(next);
    final p = _prefs;
    if (p != null) await next.persist(p);
    if (!kIsWeb) {
      if (next.dailyNotifications) {
        await FirebaseMessaging.instance.subscribeToTopic(
          AppConstants.fcmTopicDaily,
        );
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic(
          AppConstants.fcmTopicDaily,
        );
      }
    }
  }

  Future<void> toggleStreakNotifications() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = current.copyWith(
      streakNotifications: !current.streakNotifications,
    );
    state = AsyncValue.data(next);
    final p = _prefs;
    if (p != null) await next.persist(p);
    if (!kIsWeb) {
      if (next.streakNotifications) {
        await FirebaseMessaging.instance.subscribeToTopic(
          AppConstants.fcmTopicStreakWarning,
        );
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic(
          AppConstants.fcmTopicStreakWarning,
        );
      }
    }
  }

  Future<void> toggleLeagueNotifications() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = current.copyWith(
      leagueNotifications: !current.leagueNotifications,
    );
    state = AsyncValue.data(next);
    final p = _prefs;
    if (p != null) await next.persist(p);
    if (!kIsWeb) {
      if (next.leagueNotifications) {
        await FirebaseMessaging.instance.subscribeToTopic(
          AppConstants.fcmTopicLeague,
        );
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic(
          AppConstants.fcmTopicLeague,
        );
      }
    }
  }

  Future<void> toggleAchievementNotifications() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = current.copyWith(
      achievementNotifications: !current.achievementNotifications,
    );
    state = AsyncValue.data(next);
    final p = _prefs;
    if (p != null) await next.persist(p);
    if (!kIsWeb) {
      if (next.achievementNotifications) {
        await FirebaseMessaging.instance.subscribeToTopic(
          AppConstants.fcmTopicAchievement,
        );
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic(
          AppConstants.fcmTopicAchievement,
        );
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

  Future<void> setThemeMode(AppThemeMode mode) async {
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

  /// Clears the device's FCM token association before signing out — left in
  /// place, this would keep a signed-out device targetable by per-user push
  /// (KNOWN_BUGS.md A2 captures the token; nothing previously cleared it).
  /// Must happen while still authenticated, since the write needs
  /// `isOwner(uid)`; best-effort (a failure here shouldn't block sign-out).
  Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      await _users.updateUserFields(uid, {'fcmToken': ''});
    }
    await _auth.signOut();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final settingsProvider =
    StateNotifierProvider.autoDispose<
      SettingsNotifier,
      AsyncValue<SettingsState>
    >((ref) {
      final notifier = SettingsNotifier(
        authService: ref.watch(authServiceProvider),
        userRepository: ref.watch(userRepositoryProvider),
      );
      notifier.init();
      return notifier;
    });

/// The user's raw theme preference (what's actually selected in Settings —
/// System/Light/Dark/Automatic). Use this to render the selector's current
/// choice; use [themeModeProvider] for the real [ThemeMode] to hand to
/// [MaterialApp].
final appThemeModeProvider = Provider<AppThemeMode>((ref) {
  return ref.watch(settingsProvider).valueOrNull?.themeMode ??
      AppThemeMode.system;
});

/// The effective [ThemeMode] MaterialApp should actually render.
///
/// Resolves [AppThemeMode.automatic] using the same sunrise/sunset data
/// Automatic-mode weather already fetches (no separate location poll — see
/// weather_service.dart's `daily=sunrise,sunset` params) via [isDaytime].
/// Falls back to [ThemeMode.system] whenever sunrise/sunset isn't available
/// yet (location denied/unavailable, or weather hasn't resolved on a cold
/// start) rather than guessing — this is what "handle location permission
/// denial gracefully" and "sensible fallback behavior" mean in practice.
///
/// Automatic mode updates on the same ~30-minute cadence as [weatherProvider]
/// rather than a dedicated timer — sunrise/sunset only moves by a couple of
/// minutes a day, so finer-grained polling would just be wasted work, and
/// this cadence naturally satisfies "avoid rapid theme changes around
/// sunrise/sunset" without extra logic to debounce it.
final themeModeProvider = Provider<ThemeMode>((ref) {
  final weather = ref.watch(weatherProvider).valueOrNull;
  return resolveEffectiveThemeMode(
    appMode: ref.watch(appThemeModeProvider),
    now: DateTime.now(),
    sunrise: weather?.sunrise,
    sunset: weather?.sunset,
  );
});

/// Exposes the persisted text scale factor to the root widget tree.
final textScaleProvider = Provider<double>((ref) {
  return ref.watch(settingsProvider).valueOrNull?.textScale ?? 1.0;
});

/// Bridges Flutter's OS-level "Reduce Motion" accessibility signal into
/// Riverpod. Providers have no BuildContext/MediaQuery of their own — this
/// is the one place that reads [WidgetsBinding.platformDispatcher] directly
/// and re-runs whenever the OS setting changes, so every consumer of
/// [reducedMotionProvider] below picks it up automatically instead of each
/// needing its own MediaQuery lookup.
final osReducedMotionProvider = Provider<bool>((ref) {
  final dispatcher = WidgetsBinding.instance.platformDispatcher;
  final previous = dispatcher.onAccessibilityFeaturesChanged;
  dispatcher.onAccessibilityFeaturesChanged = () {
    previous?.call();
    ref.invalidateSelf();
  };
  ref.onDispose(() => dispatcher.onAccessibilityFeaturesChanged = previous);
  return dispatcher.accessibilityFeatures.disableAnimations;
});

/// Whether motion should be reduced — true if *either* TouchGrass's own
/// in-app "Reduce Motion" toggle is on, or the OS-level accessibility
/// setting is (a user who enabled it system-wide shouldn't also have to
/// find TouchGrass's own Settings screen for it to take effect). This is
/// the app-root `MediaQuery.disableAnimations` composition
/// (`combinedReducedMotion` in accessibility_prefs.dart) applied here too,
/// so the ~30 call sites across the app that read this provider directly
/// (animation controllers, `ref.read`/`ref.watch` outside a widget with a
/// live MediaQuery) get the same guarantee as the ambient MediaQuery tree.
final reducedMotionProvider = Provider<bool>((ref) {
  final appSetting =
      ref.watch(settingsProvider).valueOrNull?.reducedMotion ?? false;
  final osSetting = ref.watch(osReducedMotionProvider);
  return combinedReducedMotion(
    systemReducedMotion: osSetting,
    appReducedMotion: appSetting,
  );
});

/// Whether the user has enabled high contrast mode.
final highContrastProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).valueOrNull?.highContrast ?? false;
});

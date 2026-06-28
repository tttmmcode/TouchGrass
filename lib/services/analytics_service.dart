import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

// ── Analytics ─────────────────────────────────────────────────────────────────

abstract final class AnalyticsService {
  static final _a = FirebaseAnalytics.instance;

  // ── Identity ─────────────────────────────────────────────────────────────────

  static void setUserId(String uid) {
    unawaited(_safe(() => _a.setUserId(id: uid)));
  }

  static void setUserProperty(String name, String value) {
    unawaited(_safe(() => _a.setUserProperty(name: name, value: value)));
  }

  // ── Auth ──────────────────────────────────────────────────────────────────────

  static void logSignIn(String method) {
    unawaited(_safe(() => _a.logLogin(loginMethod: method)));
  }

  static void logSignUp(String method) {
    unawaited(_safe(() => _a.logSignUp(signUpMethod: method)));
  }

  // ── Challenges ────────────────────────────────────────────────────────────────

  static void logChallengeViewed({
    required String challengeId,
    required String category,
  }) {
    unawaited(_safe(() => _a.logEvent(
          name: 'challenge_viewed',
          parameters: {'challenge_id': challengeId, 'category': category},
        )));
  }

  static void logChallengeComplete({
    required String challengeId,
    required String category,
    required int xpAwarded,
  }) {
    unawaited(_safe(() => _a.logEvent(
          name: 'challenge_complete',
          parameters: {
            'challenge_id': challengeId,
            'category': category,
            'xp_awarded': xpAwarded,
          },
        )));
  }

  static void logChallengeRerolled() {
    unawaited(_safe(() => _a.logEvent(name: 'challenge_reroll')));
  }

  // Keep old name as alias so existing callers still compile.
  static void logReroll() => logChallengeRerolled();

  // ── Photo & verification ──────────────────────────────────────────────────────

  static void logPhotoUploaded({required String challengeId}) {
    unawaited(_safe(() => _a.logEvent(
          name: 'photo_uploaded',
          parameters: {'challenge_id': challengeId},
        )));
  }

  static void logVerificationPassed({
    required String challengeId,
    required double confidence,
  }) {
    unawaited(_safe(() => _a.logEvent(
          name: 'verification_passed',
          parameters: {
            'challenge_id': challengeId,
            'confidence': confidence.toStringAsFixed(2),
          },
        )));
  }

  static void logVerificationOverridden({required String challengeId}) {
    unawaited(_safe(() => _a.logEvent(
          name: 'verification_overridden',
          parameters: {'challenge_id': challengeId},
        )));
  }

  // ── Progression ───────────────────────────────────────────────────────────────

  static void logLevelUp(int newLevel) {
    unawaited(_safe(() => _a.logLevelUp(level: newLevel)));
  }

  static void logAchievementUnlocked(String id) {
    unawaited(_safe(() => _a.logUnlockAchievement(id: id)));
  }

  static void logLeaguePromotion({
    required String fromLeague,
    required String toLeague,
  }) {
    unawaited(_safe(() => _a.logEvent(
          name: 'league_promotion',
          parameters: {'from_league': fromLeague, 'to_league': toLeague},
        )));
  }

  // ── Retention ─────────────────────────────────────────────────────────────────

  /// Fires once on day 1, 7, and 30 since account creation.
  static void logRetentionMilestone(int dayNumber) {
    unawaited(_safe(() => _a.logEvent(
          name: 'retention_day_$dayNumber',
          parameters: {'day_number': dayNumber},
        )));
  }

  /// Fired when a user with prior completions has streak == 0 on app open.
  static void logStreakAbandoned({required int totalCompletions}) {
    unawaited(_safe(() => _a.logEvent(
          name: 'streak_abandoned',
          parameters: {'total_completions': totalCompletions},
        )));
  }

  // ── Internal ──────────────────────────────────────────────────────────────────

  static Future<void> _safe(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      debugPrint('[Analytics] error: $e');
    }
  }
}

// ── Crash reporting ───────────────────────────────────────────────────────────

abstract final class CrashReporter {
  static final _crashlytics = FirebaseCrashlytics.instance;

  static void setUserId(String uid) {
    if (!kIsWeb) {
      _crashlytics.setUserIdentifier(uid).ignore();
    }
  }

  static void log(String message) {
    if (!kIsWeb) {
      _crashlytics.log(message);
    }
  }

  /// Records a non-fatal error with an optional human-readable [reason].
  static void recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) {
    if (kIsWeb) {
      debugPrint('[CrashReporter] ${reason ?? ''} $error');
      return;
    }
    _crashlytics
        .recordError(error, stack, reason: reason, fatal: fatal)
        .ignore();
  }
}

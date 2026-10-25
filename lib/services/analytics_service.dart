import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../core/config/firebase_environment.dart';
import '../core/utils/secret_redaction.dart';

// ── Analytics ─────────────────────────────────────────────────────────────────

abstract final class AnalyticsService {
  static final _a = FirebaseAnalytics.instance;

  // ── Identity ─────────────────────────────────────────────────────────────────

  static void setUserId(String uid) {
    unawaited(_safe(() => _a.setUserId(id: uid)));
  }

  /// Stops attributing events to the signed-out user (Phase 6, P6-A2).
  static void clearUserId() {
    unawaited(_safe(() => _a.setUserId(id: null)));
  }

  /// After the account was deleted: also clears this device's analytics
  /// data and app-instance ID, so nothing collected later on this device
  /// links back to the deleted account. Data Google already received is
  /// kept for the project's configured retention period.
  static void resetAfterAccountDeletion() {
    unawaited(
      _safe(() async {
        await _a.setUserId(id: null);
        await _a.resetAnalyticsData();
      }),
    );
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
    unawaited(
      _safe(
        () => _a.logEvent(
          name: 'challenge_viewed',
          parameters: {'challenge_id': challengeId, 'category': category},
        ),
      ),
    );
  }

  static void logChallengeComplete({
    required String challengeId,
    required String category,
    required int xpAwarded,
  }) {
    unawaited(
      _safe(
        () => _a.logEvent(
          name: 'challenge_complete',
          parameters: {
            'challenge_id': challengeId,
            'category': category,
            'xp_awarded': xpAwarded,
          },
        ),
      ),
    );
  }

  static void logChallengeRerolled() {
    unawaited(_safe(() => _a.logEvent(name: 'challenge_reroll')));
  }

  // Keep old name as alias so existing callers still compile.
  static void logReroll() => logChallengeRerolled();

  // ── Photo & verification ──────────────────────────────────────────────────────

  static void logPhotoUploaded({required String challengeId}) {
    unawaited(
      _safe(
        () => _a.logEvent(
          name: 'photo_uploaded',
          parameters: {'challenge_id': challengeId},
        ),
      ),
    );
  }

  static void logVerificationPassed({
    required String challengeId,
    required double confidence,
  }) {
    unawaited(
      _safe(
        () => _a.logEvent(
          name: 'verification_passed',
          parameters: {
            'challenge_id': challengeId,
            'confidence': confidence.toStringAsFixed(2),
          },
        ),
      ),
    );
  }

  static void logVerificationOverridden({required String challengeId}) {
    unawaited(
      _safe(
        () => _a.logEvent(
          name: 'verification_overridden',
          parameters: {'challenge_id': challengeId},
        ),
      ),
    );
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
    unawaited(
      _safe(
        () => _a.logEvent(
          name: 'league_promotion',
          parameters: {'from_league': fromLeague, 'to_league': toLeague},
        ),
      ),
    );
  }

  // ── Retention ─────────────────────────────────────────────────────────────────

  /// Fires once on day 1, 7, and 30 since account creation.
  static void logRetentionMilestone(int dayNumber) {
    unawaited(
      _safe(
        () => _a.logEvent(
          name: 'retention_day_$dayNumber',
          parameters: {'day_number': dayNumber},
        ),
      ),
    );
  }

  /// Fired when a user with prior completions has streak == 0 on app open.
  static void logStreakAbandoned({required int totalCompletions}) {
    unawaited(
      _safe(
        () => _a.logEvent(
          name: 'streak_abandoned',
          parameters: {'total_completions': totalCompletions},
        ),
      ),
    );
  }

  // ── Internal ──────────────────────────────────────────────────────────────────

  static Future<void> _safe(Future<void> Function() fn) async {
    // Production only: development and emulator builds never send events
    // to the production Analytics property (Phase 8).
    if (!FirebaseEnvironment.telemetryEnabled) return;
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
    if (kIsWeb || !FirebaseEnvironment.telemetryEnabled) return;
    try {
      _crashlytics.setUserIdentifier(uid).ignore();
    } catch (_) {} // Firebase not initialised (tests)
  }

  /// Detaches crash reports from the signed-out or deleted user.
  static void clearUserId() => setUserId('');

  static void log(String message) {
    if (!kIsWeb && FirebaseEnvironment.telemetryEnabled) {
      _crashlytics.log(redactDownloadTokens(message));
    }
  }

  /// Records a non-fatal error with an optional human-readable [reason].
  /// Never throws: a crash report must not break the flow it reports on
  /// (e.g. when Firebase isn't initialised, as in unit tests). Photo
  /// download tokens are removed from both first (Phase 7C).
  static void recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) {
    final safeError = redactErrorForReport(error);
    final safeReason = reason == null ? null : redactDownloadTokens(reason);
    if (kIsWeb || !FirebaseEnvironment.telemetryEnabled) {
      debugPrint('[CrashReporter] ${safeReason ?? ''} $safeError');
      return;
    }
    try {
      _crashlytics
          .recordError(safeError, stack, reason: safeReason, fatal: fatal)
          .ignore();
    } catch (e) {
      debugPrint('[CrashReporter] unavailable: $e');
    }
  }
}

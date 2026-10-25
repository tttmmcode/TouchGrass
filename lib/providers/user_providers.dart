import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/calendar_days.dart';
import '../models/user_model.dart';
import '../repositories/feedback_repository.dart';
import '../repositories/user_repository.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';
import 'auth_providers.dart';

// ── Service providers ──────────────────────────────────────────────────────

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final firestoreServiceProvider = Provider<FirestoreService>(
  (ref) => FirestoreService(),
);

final storageServiceProvider = Provider<StorageService>(
  (ref) => StorageService(),
);

// ── Repository providers ───────────────────────────────────────────────────

/// Write-only feedback / bug-report submissions (audit N-1).
final feedbackRepositoryProvider = Provider<FeedbackRepository>(
  (ref) => FeedbackRepository(),
);

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(
    authService: ref.watch(authServiceProvider),
    firestoreService: ref.watch(firestoreServiceProvider),
    storageService: ref.watch(storageServiceProvider),
  );
});

// ── User data providers ────────────────────────────────────────────────────

/// Real-time stream of the signed-in user's [UserModel].
///
/// Emits null when unauthenticated. Used by home, profile, and stats widgets.
final currentUserProvider = StreamProvider<UserModel?>((ref) async* {
  final authState = ref.watch(authStateProvider);
  final uid = authState.valueOrNull?.uid;

  if (uid == null) {
    yield null;
    return;
  }

  yield* ref.watch(userRepositoryProvider).watchUser(uid);
});

// ── Analytics & retention bootstrap ───────────────────────────────────────────

/// Events already logged in this app session (audit D-21): the bootstrap
/// below re-runs on every change to the profile document (each XP or streak
/// update), so one-off events are claimed here first.
final _sessionEvents = <String>{};

/// True the first time [key] is claimed in this app session.
@visibleForTesting
bool claimSessionEvent(String key) => _sessionEvents.add(key);

@visibleForTesting
void resetSessionEventsForTest() => _sessionEvents.clear();

enum AnalyticsIdentityAction { none, identify, clear }

/// What to do with the analytics/crash-report user ID when the signed-in
/// user changes from [previous] to [current] (Phase 6, P6-A2): identify a
/// new user, clear it once on sign-out or deletion, otherwise nothing.
@visibleForTesting
AnalyticsIdentityAction analyticsIdentityAction(
  String? previous,
  String? current,
) {
  if (current != null) {
    return current == previous
        ? AnalyticsIdentityAction.none
        : AnalyticsIdentityAction.identify;
  }
  return previous == null
      ? AnalyticsIdentityAction.none
      : AnalyticsIdentityAction.clear;
}

String? _identifiedUid;

/// Watches the current user and wires up analytics identity, user properties,
/// and one-time retention milestone events.
///
/// Watch this from your root widget or shell so it stays alive while the user
/// is signed in.
final analyticsBootstrapProvider = Provider<void>((ref) {
  final userAsync = ref.watch(currentUserProvider);
  final user = userAsync.valueOrNull;

  // ── Identity ──────────────────────────────────────────────────────────────
  switch (analyticsIdentityAction(_identifiedUid, user?.uid)) {
    case AnalyticsIdentityAction.identify:
      AnalyticsService.setUserId(user!.uid);
      CrashReporter.setUserId(user.uid);
    case AnalyticsIdentityAction.clear:
      AnalyticsService.clearUserId();
      CrashReporter.clearUserId();
    case AnalyticsIdentityAction.none:
      break;
  }
  _identifiedUid = user?.uid;
  if (user == null) return;

  // ── User properties for segmentation ─────────────────────────────────────
  AnalyticsService.setUserProperty('league', user.currentLeague);
  AnalyticsService.setUserProperty(
    'level',
    AppConstants.levelForXp(user.xp).toString(),
  );
  AnalyticsService.setUserProperty('streak', user.streak.toString());

  // ── Retention milestones (fire once per app session per milestone) ────────
  // createdAt is stored in UTC: compare local calendar days (audit D-17).
  final dayNumber =
      calendarDaysBetween(user.createdAt.toLocal(), DateTime.now()) + 1;

  if ((dayNumber == 1 || dayNumber == 7 || dayNumber == 30) &&
      claimSessionEvent('retention:${user.uid}:$dayNumber')) {
    AnalyticsService.logRetentionMilestone(dayNumber);
  }

  // ── Streak abandonment (once per session) ─────────────────────────────────
  if (user.streak == 0 &&
      user.totalCompletions > 0 &&
      claimSessionEvent('streak_abandoned:${user.uid}')) {
    AnalyticsService.logStreakAbandoned(
      totalCompletions: user.totalCompletions,
    );
  }

  // ── Completion rate user property ─────────────────────────────────────────
  if (dayNumber > 0) {
    final rate = (user.totalCompletions / dayNumber).clamp(0.0, 1.0);
    AnalyticsService.setUserProperty(
      'completion_rate',
      rate.toStringAsFixed(2),
    );
  }
});

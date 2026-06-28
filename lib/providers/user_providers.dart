import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../models/user_model.dart';
import '../repositories/user_repository.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';
import 'auth_providers.dart';

// ── Service providers ──────────────────────────────────────────────────────

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(),
);

final firestoreServiceProvider = Provider<FirestoreService>(
  (ref) => FirestoreService(),
);

final storageServiceProvider = Provider<StorageService>(
  (ref) => StorageService(),
);

// ── Repository providers ───────────────────────────────────────────────────

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

/// Watches the current user and wires up analytics identity, user properties,
/// and one-time retention milestone events.
///
/// Watch this from your root widget or shell so it stays alive while the user
/// is signed in.
final analyticsBootstrapProvider = Provider<void>((ref) {
  final userAsync = ref.watch(currentUserProvider);
  final user = userAsync.valueOrNull;
  if (user == null) return;

  // ── Identity ──────────────────────────────────────────────────────────────
  AnalyticsService.setUserId(user.uid);
  CrashReporter.setUserId(user.uid);

  // ── User properties for segmentation ─────────────────────────────────────
  AnalyticsService.setUserProperty('league', user.currentLeague);
  AnalyticsService.setUserProperty(
      'level', AppConstants.levelForXp(user.xp).toString());
  AnalyticsService.setUserProperty('streak', user.streak.toString());

  // ── Retention milestones (fire once per app session per milestone) ────────
  final now = DateTime.now();
  final joinDate = DateTime(
    user.createdAt.year,
    user.createdAt.month,
    user.createdAt.day,
  );
  final today = DateTime(now.year, now.month, now.day);
  final dayNumber = today.difference(joinDate).inDays + 1;

  if (dayNumber == 1 || dayNumber == 7 || dayNumber == 30) {
    AnalyticsService.logRetentionMilestone(dayNumber);
  }

  // ── Streak abandonment ────────────────────────────────────────────────────
  if (user.streak == 0 && user.totalCompletions > 0) {
    AnalyticsService.logStreakAbandoned(
        totalCompletions: user.totalCompletions);
  }

  // ── Completion rate user property ─────────────────────────────────────────
  if (dayNumber > 0) {
    final rate = (user.totalCompletions / dayNumber).clamp(0.0, 1.0);
    AnalyticsService.setUserProperty(
        'completion_rate', rate.toStringAsFixed(2));
  }
});

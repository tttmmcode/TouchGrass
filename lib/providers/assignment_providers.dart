import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/calendar_days.dart';
import '../models/challenge_model.dart';
import '../services/analytics_service.dart';
import '../services/assignment_service.dart';
import '../services/challenge_generation_service.dart';
import 'auth_providers.dart';
import 'challenge_providers.dart';
import 'user_providers.dart';

/// Converts the raw preference strings on [UserSettings.preferredCategories]
/// into real enum values, silently dropping any name that isn't a current
/// [ChallengeCategory] (e.g. a category removed in a future update) rather
/// than throwing — an empty result correctly falls back to "no preference".
Set<ChallengeCategory> _parsePreferredCategories(List<String> raw) {
  final names = raw.toSet();
  return ChallengeCategory.values.where((c) => names.contains(c.name)).toSet();
}

// ── Reroll notifier (capped at AppConstants.maxRerollsPerDay) ──────────────

class RerollNotifier extends StateNotifier<AsyncValue<void>> {
  RerollNotifier({
    required this.ref,
    required AssignmentService assignmentService,
  }) : _service = assignmentService,
       super(const AsyncValue.data(null));

  final Ref ref;
  final AssignmentService _service;

  Future<void> reroll() async {
    final challenge = ref.read(todaysChallengeProvider).valueOrNull;
    if (challenge == null) return;

    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;

    final preferredCategories = _parsePreferredCategories(
      ref.read(currentUserProvider).valueOrNull?.settings.preferredCategories ??
          const [],
    );

    state = const AsyncValue.loading();
    try {
      await _service.rerollChallenge(
        uid,
        challenge,
        preferredCategories: preferredCategories,
      );
      AnalyticsService.logReroll();
      state = const AsyncValue.data(null);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }
}

final rerollProvider =
    StateNotifierProvider.autoDispose<RerollNotifier, AsyncValue<void>>((ref) {
      return RerollNotifier(
        ref: ref,
        assignmentService: ref.watch(assignmentServiceProvider),
      );
    });

final assignmentServiceProvider = Provider<AssignmentService>((ref) {
  return AssignmentService(
    challengeRepository: ref.watch(challengeRepositoryProvider),
    challengeGenerationService: const ChallengeGenerationService(),
  );
});

/// Triggers daily challenge assignment on login AND at midnight when the app
/// stays open across a day boundary.
///
/// Watch this in HomeScreen. The [todaysChallengeProvider] stream updates
/// automatically when the Firestore doc is written.
final assignmentInitProvider = FutureProvider<void>((ref) async {
  ref.watch(calendarDateProvider);
  final user = await ref.watch(authStateProvider.future);
  if (user == null) return;

  final currentUser = await ref.read(currentUserProvider.future);
  // createdAt is stored in UTC: compare the user's local calendar days
  // (audit D-17), DST-safe.
  final createdAt = (currentUser?.createdAt ?? DateTime.now()).toLocal();
  final dayNumber = calendarDaysBetween(createdAt, DateTime.now()) + 1;
  final preferredCategories = _parsePreferredCategories(
    currentUser?.settings.preferredCategories ?? const [],
  );

  await ref
      .read(assignmentServiceProvider)
      .ensureTodaysChallenge(
        user.uid,
        dayNumber: dayNumber,
        preferredCategories: preferredCategories,
      );
});

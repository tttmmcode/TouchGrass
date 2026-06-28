import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/analytics_service.dart';
import '../services/assignment_service.dart';
import '../services/challenge_generation_service.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import 'auth_providers.dart';
import 'challenge_providers.dart';
import 'user_providers.dart';

// ── Reroll notifier (unlimited rerolls) ───────────────────────────────────────

class RerollNotifier extends StateNotifier<AsyncValue<void>> {
  RerollNotifier({required this.ref, required AssignmentService assignmentService})
      : _service = assignmentService,
        super(const AsyncValue.data(null));

  final Ref ref;
  final AssignmentService _service;

  Future<void> reroll() async {
    final challenge = ref.read(todaysChallengeProvider).valueOrNull;
    if (challenge == null) return;

    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;

    state = const AsyncValue.loading();
    try {
      await _service.rerollChallenge(uid, challenge);
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
    challengeGenerationService: ChallengeGenerationService(),
    weatherService: WeatherService(),
    locationService: LocationService(),
  );
});

// Tracks the current calendar date (time stripped). Re-schedules itself at
// each midnight so assignmentInitProvider re-runs when the day rolls over.
class _CalendarDate extends Notifier<DateTime> {
  Timer? _timer;

  @override
  DateTime build() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _scheduleMidnight(today);
    ref.onDispose(() => _timer?.cancel());
    return today;
  }

  void _scheduleMidnight(DateTime current) {
    final midnight = current.add(const Duration(days: 1));
    final delay = midnight.difference(DateTime.now());
    _timer?.cancel();
    _timer = Timer(delay, () {
      final now = DateTime.now();
      state = DateTime(now.year, now.month, now.day);
      _scheduleMidnight(state);
    });
  }
}

final _calendarDateProvider =
    NotifierProvider<_CalendarDate, DateTime>(_CalendarDate.new);

/// Triggers daily challenge assignment on login AND at midnight when the app
/// stays open across a day boundary.
///
/// Watch this in HomeScreen. The [todaysChallengeProvider] stream updates
/// automatically when the Firestore doc is written.
final assignmentInitProvider = FutureProvider<void>((ref) async {
  ref.watch(_calendarDateProvider);
  final user = await ref.watch(authStateProvider.future);
  if (user == null) return;

  final currentUser = await ref.read(currentUserProvider.future);
  final createdAt = currentUser?.createdAt ?? DateTime.now();
  final today = DateTime.now();
  final todayDate = DateTime(today.year, today.month, today.day);
  final joinDate = DateTime(createdAt.year, createdAt.month, createdAt.day);
  final dayNumber = todayDate.difference(joinDate).inDays + 1;

  await ref.read(assignmentServiceProvider).ensureTodaysChallenge(
    user.uid,
    dayNumber: dayNumber,
  );
});

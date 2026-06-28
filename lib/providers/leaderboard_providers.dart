import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../models/leaderboard_entry_model.dart';
import '../models/league_definition.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../services/leaderboard_service.dart';
import 'auth_providers.dart';
import 'user_providers.dart';

// ── Service ───────────────────────────────────────────────────────────────────

final leaderboardServiceProvider = Provider<LeaderboardService>(
  (_) => const LeaderboardService(),
);

// ── League leaderboard (primary) ──────────────────────────────────────────────

/// Real-time leaderboard for a specific league, ranked by weekly XP.
///
/// Sorting is done client-side to avoid requiring a deployed composite index.
/// Once `firebase deploy --only firestore:indexes` has been run, you can
/// restore server-side ordering by adding `orderByField: 'weeklyXp'` and
/// `descending: true` to watchCollection and removing the manual sort below.
final leagueBoardProvider = StreamProvider.autoDispose.family<List<LeaderboardEntryModel>, String>(
  (ref, leagueId) {
    final firestore = ref.watch(firestoreServiceProvider);
    final service = ref.watch(leaderboardServiceProvider);
    return firestore
        .watchCollection(
          collection: AppConstants.colUsers,
          filters: [QueryFilter(field: 'currentLeague', isEqualTo: leagueId)],
          limit: AppConstants.leaderboardPageSize,
        )
        .map((snap) {
          final users = snap.docs.map(UserModel.fromFirestore).toList()
            ..sort((a, b) => b.weeklyXp.compareTo(a.weeklyXp));
          return service.buildEntries(users);
        });
  },
);

// ── Current user helpers ──────────────────────────────────────────────────────

/// UID of the currently signed-in user (null when signed out).
final currentUidProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider).valueOrNull?.uid;
});

/// The [LeagueDef] the current user belongs to, derived from their total XP.
final currentUserLeagueProvider = Provider<LeagueDef?>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return null;
  return LeagueDef.forXp(user.xp);
});

// ── Weekly reset countdown ────────────────────────────────────────────────────

/// A ticking string showing how long until the next weekly reset.
/// Updates every 30 seconds.
final weeklyResetCountdownProvider = StreamProvider<String>((ref) {
  final controller = StreamController<String>();
  controller.add(AppConstants.weeklyResetLabel());
  final timer = Timer.periodic(
    const Duration(seconds: 30),
    (_) {
      if (!controller.isClosed) {
        controller.add(AppConstants.weeklyResetLabel());
      }
    },
  );
  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });
  return controller.stream;
});

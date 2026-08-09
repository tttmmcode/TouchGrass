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
/// Sorting is done client-side to avoid requiring a deployed composite index
/// (a matching `currentLeague ASC, weeklyXp DESC` index is already defined
/// in firestore.indexes.json but its deployment status can't be verified
/// from the client — see the pending-deployment note in the final report).
/// Once confirmed deployed, this can add `orderByField: 'weeklyXp'` /
/// `descending: true` directly to the query for server-side ordering.
///
/// Deliberately does NOT pass `limit` to the Firestore query itself —
/// Firestore would apply that limit BEFORE the client-side sort below,
/// returning an arbitrary (roughly doc-ID-ordered) 30 members rather than
/// the true top 30 by weekly XP whenever a league has more than
/// [AppConstants.leaderboardPageSize] members. The page-size cap is applied
/// after sorting instead.
final leagueBoardProvider = StreamProvider.autoDispose.family<List<LeaderboardEntryModel>, String>(
  (ref, leagueId) {
    final firestore = ref.watch(firestoreServiceProvider);
    final service = ref.watch(leaderboardServiceProvider);
    return firestore
        .watchCollection(
          // Reads the public mirror, not `colUsers` — no client can see
          // another user's private fields (e.g. email) via this query.
          collection: AppConstants.colLeaderboardPublic,
          filters: [QueryFilter(field: 'currentLeague', isEqualTo: leagueId)],
        )
        .map((snap) {
          final users = snap.docs.map(UserModel.fromFirestore).toList()
            ..sort((a, b) => b.weeklyXp.compareTo(a.weeklyXp));
          final top = users.take(AppConstants.leaderboardPageSize).toList();
          return service.buildEntries(top);
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
/// Updates every 30 seconds. `autoDispose` because it's only watched by the
/// Leaderboard/Leagues screens — the timer should stop once neither is
/// mounted rather than ticking for the lifetime of the app.
final weeklyResetCountdownProvider = StreamProvider.autoDispose<String>((ref) {
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

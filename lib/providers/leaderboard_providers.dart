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

/// Real-time leaderboard for a specific league: the top
/// [AppConstants.leaderboardPageSize] members by weekly XP, ordered and
/// capped by the server (Phase 8). Requires the composite index
/// `currentLeague ASC, weeklyXp DESC` (firestore.indexes.json) to be
/// deployed — production gets it with the Firestore deploy that precedes
/// this build. The client re-sorts the page so ties render consistently.
final leagueBoardProvider = StreamProvider.autoDispose
    .family<List<LeaderboardEntryModel>, String>((ref, leagueId) {
      final firestore = ref.watch(firestoreServiceProvider);
      final service = ref.watch(leaderboardServiceProvider);
      return firestore
          .watchCollection(
            // Reads the public mirror, not `colUsers` — no client can see
            // another user's private fields (e.g. email) via this query.
            collection: AppConstants.colLeaderboardPublic,
            filters: [QueryFilter(field: 'currentLeague', isEqualTo: leagueId)],
            // Phase 8: the server orders and caps, so a view reads at most
            // one page instead of every member of the league (cost and
            // latency grew with the league). Needs the composite index
            // (currentLeague ASC, weeklyXp DESC) in firestore.indexes.json,
            // deployed before this build (cutover plan).
            orderByField: 'weeklyXp',
            descending: true,
            limit: AppConstants.leaderboardPageSize,
          )
          .map((snap) {
            final users = snap.docs.map(UserModel.fromFirestore).toList()
              ..sort((a, b) => b.weeklyXp.compareTo(a.weeklyXp));
            final top = users.take(AppConstants.leaderboardPageSize).toList();
            return service.buildEntries(top);
          });
    });

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
  final timer = Timer.periodic(const Duration(seconds: 30), (_) {
    if (!controller.isClosed) {
      controller.add(AppConstants.weeklyResetLabel());
    }
  });
  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });
  return controller.stream;
});

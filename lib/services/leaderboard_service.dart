import '../core/constants/app_constants.dart';
import '../models/leaderboard_entry_model.dart';
import '../models/league_definition.dart';
import '../models/user_model.dart';

/// Centralises all leaderboard ranking logic.
///
/// No screen calculates ranks or zone membership directly —
/// everything flows through this service.
class LeaderboardService {
  const LeaderboardService();

  // ── Entry building ─────────────────────────────────────────────────────────

  /// Converts a raw [UserModel] list (already ordered by weeklyXp DESC from
  /// Firestore) into ranked [LeaderboardEntryModel] entries.
  ///
  /// Users who have opted out of public leaderboards are removed before
  /// ranking so rank numbers stay contiguous.
  List<LeaderboardEntryModel> buildEntries(List<UserModel> users) {
    final visible = users.where((u) => u.settings.profilePublic).toList();
    return visible.indexed
        .map(
          (pair) => LeaderboardEntryModel.fromUser(pair.$2, rank: pair.$1 + 1),
        )
        .toList();
  }

  // ── Zone membership ────────────────────────────────────────────────────────

  /// Whether [rank] is among this week's top performers in a board of
  /// [total] entries — a purely presentational highlight (bragging rights),
  /// not a promise of league promotion.
  ///
  /// League placement in TouchGrass is driven entirely by lifetime XP
  /// (see [LeagueDef.forXp]), recalculated on every XP-earning action —
  /// there is no separate weekly cohort promotion/demotion transaction.
  /// This app has no backend (no Cloud Functions) capable of safely
  /// ranking-and-moving every member of a league at a synchronized reset
  /// instant, and Firestore security rules correctly forbid one client from
  /// writing another user's `currentLeague`. Rather than imply a mechanic
  /// that cannot exist, the leaderboard only ever celebrates real, current
  /// performance.
  bool isTopPerformer(int rank, int total) {
    if (total <= AppConstants.promotionZoneCount) return false;
    return rank <= AppConstants.promotionZoneCount;
  }

  // ── League helpers ─────────────────────────────────────────────────────────

  LeagueDef leagueForUser(UserModel user) => LeagueDef.forXp(user.xp);
}

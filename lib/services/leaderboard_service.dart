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
        .map((pair) => LeaderboardEntryModel.fromUser(
              pair.$2,
              rank: pair.$1 + 1,
            ))
        .toList();
  }

  // ── Zone membership ────────────────────────────────────────────────────────

  /// Whether [rank] falls in the promotion zone for a board of [total] entries.
  ///
  /// Zones are only meaningful when the board is large enough to have both
  /// zones without overlap.
  bool isPromotion(int rank, int total) {
    if (total <= AppConstants.promotionZoneCount + AppConstants.demotionZoneCount) {
      return false;
    }
    return rank <= AppConstants.promotionZoneCount;
  }

  bool isDemotion(int rank, int total) {
    if (total <= AppConstants.promotionZoneCount + AppConstants.demotionZoneCount) {
      return false;
    }
    return rank > total - AppConstants.demotionZoneCount;
  }

  bool isSafe(int rank, int total) =>
      !isPromotion(rank, total) && !isDemotion(rank, total);

  // ── League helpers ─────────────────────────────────────────────────────────

  LeagueDef leagueForUser(UserModel user) => LeagueDef.forXp(user.xp);
}

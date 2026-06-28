import 'package:flutter/foundation.dart';

import 'user_model.dart';

/// Display-ready leaderboard entry.
///
/// Wraps the subset of [UserModel] fields needed for ranking UI,
/// plus a computed [rank] position (1-based).
@immutable
class LeaderboardEntryModel {
  const LeaderboardEntryModel({
    required this.userId,
    required this.displayName,
    required this.username,
    this.photoUrl,
    required this.totalXp,
    required this.weeklyXp,
    required this.level,
    required this.streak,
    required this.leagueId,
    required this.rank,
  });

  final String userId;
  final String displayName;
  final String username;
  final String? photoUrl;

  /// All-time XP (used for league tier calculation).
  final int totalXp;

  /// XP earned in the current weekly cycle.
  final int weeklyXp;

  final int level;
  final int streak;
  final String leagueId;

  /// 1-based rank within the queried league leaderboard.
  final int rank;

  factory LeaderboardEntryModel.fromUser(
    UserModel user, {
    required int rank,
  }) =>
      LeaderboardEntryModel(
        userId: user.uid,
        displayName: user.displayName,
        username: user.username,
        photoUrl: user.photoUrl,
        totalXp: user.xp,
        weeklyXp: user.weeklyXp,
        level: user.level,
        streak: user.streak,
        leagueId: user.currentLeague,
        rank: rank,
      );

  String get initials =>
      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
}

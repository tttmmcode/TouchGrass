// Unit tests for LeaderboardService — entry building (rank assignment,
// public-profile filtering) and the "top performer" highlight boundary.
//
// Note: isTopPerformer is presentational only (bragging-rights highlight on
// the weekly board) — TouchGrass league placement is derived entirely from
// lifetime XP (LeagueDef.forXp, tested in game_logic_test.dart), recomputed
// on every XP-earning action. There is deliberately no separate weekly
// rank-based promotion/demotion transaction: this app has no backend
// (no Cloud Functions) that could safely rank-and-move every member of a
// league at a synchronized reset instant, and Firestore rules correctly
// forbid one client from writing another user's currentLeague. See
// LeaderboardService.isTopPerformer's doc comment for the full rationale.

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/services/leaderboard_service.dart';

void main() {
  group('LeaderboardService.isTopPerformer', () {
    const service = LeaderboardService();

    test('rank 1 on a small board (at or below the threshold) is not '
        'specially highlighted — nothing to stand out from', () {
      expect(service.isTopPerformer(1, 5), isFalse);
    });

    test('rank 1 on a board larger than the threshold is a top performer',
        () {
      expect(service.isTopPerformer(1, 10), isTrue);
    });

    test('rank exactly at the threshold is still a top performer', () {
      expect(service.isTopPerformer(5, 10), isTrue);
    });

    test('rank just past the threshold is not a top performer', () {
      expect(service.isTopPerformer(6, 10), isFalse);
    });

    test('bottom rank on a large board is never flagged (no demotion '
        'concept — see doc comment)', () {
      expect(service.isTopPerformer(10, 10), isFalse);
    });
  });
}

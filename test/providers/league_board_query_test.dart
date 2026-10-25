// Phase 8: the league board asks the server for one ordered page instead of
// streaming every member of the league and sorting on the device.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/core/constants/app_constants.dart';
import 'package:touchgrass/models/user_model.dart';
import 'package:touchgrass/providers/leaderboard_providers.dart';
import 'package:touchgrass/providers/user_providers.dart';
import 'package:touchgrass/services/firestore_service.dart';

void main() {
  test(
    'returns the top page by weekly XP, from an ordered, capped query',
    () async {
      final db = FakeFirebaseFirestore();
      for (var i = 0; i < 40; i++) {
        final u = UserModel.initial(
          uid: 'u$i',
          displayName: 'User $i',
        ).copyWith(weeklyXp: i * 10);
        await db.collection('leaderboard_public').doc('u$i').set({
          ...u.toFirestore(),
          'currentLeague': 'seedling',
        });
      }
      // Another league's member never appears.
      await db.collection('leaderboard_public').doc('other').set({
        ...UserModel.initial(
          uid: 'other',
          displayName: 'Other',
        ).copyWith(weeklyXp: 9999).toFirestore(),
        'currentLeague': 'sprout',
      });

      final container = ProviderContainer(
        overrides: [
          firestoreServiceProvider.overrideWithValue(FirestoreService(db: db)),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(leagueBoardProvider('seedling'), (_, _) {});
      addTearDown(sub.close);
      final board = await container.read(
        leagueBoardProvider('seedling').future,
      );

      expect(board, hasLength(AppConstants.leaderboardPageSize));
      expect(board.first.weeklyXp, 390);
      expect(
        board.last.weeklyXp,
        390 - (AppConstants.leaderboardPageSize - 1) * 10,
      );
      expect(board.map((e) => e.rank), [
        for (var r = 1; r <= AppConstants.leaderboardPageSize; r++) r,
      ]);
    },
  );

  test('the query itself is ordered and capped (not the whole league)', () {
    final src = File(
      'lib/providers/leaderboard_providers.dart',
    ).readAsStringSync();
    final query = src.substring(src.indexOf('final leagueBoardProvider'));
    expect(query, contains("orderByField: 'weeklyXp'"));
    expect(query, contains('descending: true'));
    expect(query, contains('limit: AppConstants.leaderboardPageSize'));
    final indexes = File('firestore.indexes.json').readAsStringSync();
    expect(indexes, contains('"leaderboard_public"'));
  });
}

// Unit tests for the map's proximity clustering — extracted as pure
// functions (cellSizeForZoom / clusterMemoriesByProximity) specifically so
// the grouping behavior (few nearby memories stay individual, many nearby
// memories merge into one cluster) is directly testable without a
// GoogleMap widget or controller.

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/features/map/screens/map_screen.dart';
import 'package:touchgrass/models/adventure_memory_model.dart';
import 'package:touchgrass/models/challenge_model.dart';

void main() {
  AdventureMemoryModel memoryAt(String id, double lat, double lng) =>
      AdventureMemoryModel(
        memoryId: id,
        userId: 'u1',
        challengeId: id,
        challengeDay: 1,
        challengeTitle: 'Touch grass',
        challengeCategory: ChallengeCategory.nature,
        photoUrl: 'https://example.com/$id.jpg',
        xpEarned: 25,
        verificationMethod: 'ai_verified',
        completionDate: DateTime(2026, 3, 10),
        createdAt: DateTime(2026, 3, 10),
        latitude: lat,
        longitude: lng,
      );

  group('cellSizeForZoom', () {
    test('shrinks as zoom increases (finer grouping when zoomed in)', () {
      final worldView = cellSizeForZoom(2);
      final streetView = cellSizeForZoom(18);
      expect(streetView, lessThan(worldView));
    });

    test('never returns zero or negative — always a valid grid size', () {
      expect(cellSizeForZoom(2), greaterThan(0));
      expect(cellSizeForZoom(20), greaterThan(0));
    });
  });

  group('clusterMemoriesByProximity', () {
    test('two memories a world apart stay in separate clusters', () {
      final groups = clusterMemoriesByProximity(
        [memoryAt('a', 30.2672, -97.7431), memoryAt('b', 51.5072, -0.1276)],
        zoom: 10,
      );
      expect(groups.length, 2);
      expect(groups.every((g) => g.length == 1), isTrue);
    });

    test('memories at the same coordinates merge into one cluster', () {
      final groups = clusterMemoriesByProximity(
        [
          memoryAt('a', 30.2672, -97.7431),
          memoryAt('b', 30.2672, -97.7431),
          memoryAt('c', 30.2672, -97.7431),
        ],
        zoom: 10,
      );
      expect(groups.length, 1);
      expect(groups.single.length, 3);
    });

    test('zooming in on the same points eventually separates them', () {
      final memories = [
        memoryAt('a', 30.26720, -97.74310),
        memoryAt('b', 30.26725, -97.74305),
      ];
      final zoomedOut = clusterMemoriesByProximity(memories, zoom: 2);
      final zoomedIn = clusterMemoriesByProximity(memories, zoom: 21);
      expect(zoomedOut.length, 1, reason: 'merged when zoomed far out');
      expect(zoomedIn.length, 2, reason: 'separated when zoomed in close');
    });

    test('empty input produces no clusters', () {
      expect(clusterMemoriesByProximity(const [], zoom: 10), isEmpty);
    });
  });
}

// Unit tests for resolveFocusMemory — the "View on Map" lookup rule.
// Extracted from _MapScreenState so the fallback behavior (missing memory,
// memory with no location, repeated focus requests) is directly testable
// without a GoogleMapController or widget tree.

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/features/map/screens/map_screen.dart';
import 'package:touchgrass/models/adventure_memory_model.dart';
import 'package:touchgrass/models/challenge_model.dart';

void main() {
  AdventureMemoryModel memory(String id, {double? lat, double? lng}) =>
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

  group('resolveFocusMemory', () {
    test('returns null when there is no pending focus request', () {
      final memories = [memory('a', lat: 30.0, lng: -97.0)];
      expect(resolveFocusMemory(memories, null), isNull);
    });

    test('finds the requested memory when it has a location', () {
      final memories = [
        memory('a', lat: 30.0, lng: -97.0),
        memory('b', lat: 31.0, lng: -98.0),
      ];
      expect(resolveFocusMemory(memories, 'b')?.memoryId, 'b');
    });

    test('gracefully falls back to null when the memory has no location — '
        'never crashes normal map navigation', () {
      final memories = [memory('a', lat: null, lng: null)];
      expect(resolveFocusMemory(memories, 'a'), isNull);
    });

    test('gracefully falls back to null when the memory is not (yet) '
        'loaded — e.g. a brand-new completion the realtime listener hasn\'t '
        'delivered yet', () {
      final memories = [memory('a', lat: 30.0, lng: -97.0)];
      expect(resolveFocusMemory(memories, 'does-not-exist'), isNull);
    });

    test('repeated focus requests for different memories both resolve '
        'correctly — the "second completion in a row" scenario', () {
      final memories = [
        memory('first', lat: 30.0, lng: -97.0),
        memory('second', lat: 31.0, lng: -98.0),
      ];
      expect(resolveFocusMemory(memories, 'first')?.memoryId, 'first');
      expect(resolveFocusMemory(memories, 'second')?.memoryId, 'second');
    });
  });
}

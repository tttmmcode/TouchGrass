// Unit tests for AdventureMemoryModel.isAiVerified / verificationLabel — the
// three-way distinction between a real Gemini verification, a manual
// override, and a no-API-key auto-approval. Section 4 introduced a
// fabrication bug where auto-approved completions were mislabeled as
// 'ai_verified'; these tests lock in the fix so the three states can never
// be collapsed back into a binary again.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/models/adventure_memory_model.dart';
import 'package:touchgrass/models/challenge_model.dart';

void main() {
  AdventureMemoryModel memoryWith(String verificationMethod) =>
      AdventureMemoryModel(
        memoryId: 'm1',
        userId: 'u1',
        challengeId: 'c1',
        challengeDay: 1,
        challengeTitle: 'Touch grass',
        challengeCategory: ChallengeCategory.nature,
        photoUrl: 'https://example.com/photo.jpg',
        xpEarned: 25,
        verificationMethod: verificationMethod,
        completionDate: DateTime(2026, 3, 10),
        createdAt: DateTime(2026, 3, 10),
      );

  group('AdventureMemoryModel.isAiVerified', () {
    test('is true only for a real Gemini verification', () {
      expect(memoryWith('ai_verified').isAiVerified, isTrue);
    });

    test('is false for a manual override — never claim AI verified it', () {
      expect(memoryWith('manual_override').isAiVerified, isFalse);
    });

    test('is false for a no-API-key auto-approval — AI never ran', () {
      expect(memoryWith('auto_approved').isAiVerified, isFalse);
    });
  });

  group('AdventureMemoryModel.verificationLabel', () {
    test('distinguishes all three verification methods', () {
      expect(memoryWith('ai_verified').verificationLabel, '🤖 AI Verified');
      expect(
        memoryWith('manual_override').verificationLabel,
        '✋ Manual Submit',
      );
      expect(memoryWith('auto_approved').verificationLabel, '✓ Auto-Approved');
    });
  });

  group('AdventureMemoryModel.hasLocation', () {
    AdventureMemoryModel memoryAt(double? lat, double? lng) =>
        AdventureMemoryModel(
          memoryId: 'm1',
          userId: 'u1',
          challengeId: 'c1',
          challengeDay: 1,
          challengeTitle: 'Touch grass',
          challengeCategory: ChallengeCategory.nature,
          photoUrl: 'https://example.com/photo.jpg',
          xpEarned: 25,
          verificationMethod: 'ai_verified',
          completionDate: DateTime(2026, 3, 10),
          createdAt: DateTime(2026, 3, 10),
          latitude: lat,
          longitude: lng,
        );

    test('is true for valid real-world coordinates', () {
      expect(memoryAt(30.2672, -97.7431).hasLocation, isTrue);
    });

    test('is false when coordinates are missing entirely', () {
      expect(memoryAt(null, null).hasLocation, isFalse);
    });

    test('rejects out-of-range latitude — never feeds corrupt data to the '
        'map/clustering pipeline', () {
      expect(memoryAt(200.0, -97.0).hasLocation, isFalse);
      expect(memoryAt(-91.0, -97.0).hasLocation, isFalse);
    });

    test('rejects out-of-range longitude', () {
      expect(memoryAt(30.0, 400.0).hasLocation, isFalse);
      expect(memoryAt(30.0, -181.0).hasLocation, isFalse);
    });

    test('rejects (0, 0) "null island" — the common unset-GPS sentinel', () {
      expect(memoryAt(0.0, 0.0).hasLocation, isFalse);
    });

    test('accepts a real location that happens to be near the equator or '
        'prime meridian but isn\'t exactly (0, 0)', () {
      expect(memoryAt(0.5, 0.0).hasLocation, isTrue);
      expect(memoryAt(0.0, 0.5).hasLocation, isTrue);
    });
  });

  // Journal photo persistence audit (Phase 6): these lock in that photo
  // metadata actually survives the Firestore write/read round trip, and
  // that reading back a document with a missing/absent photoUrl degrades
  // gracefully instead of throwing — a broken or not-yet-uploaded photo
  // must never crash the journal list.
  group('AdventureMemoryModel serialization', () {
    test('toFirestore includes photoUrl and required fields', () {
      final memory = AdventureMemoryModel(
        memoryId: 'm1',
        userId: 'u1',
        challengeId: 'c1',
        challengeDay: 3,
        challengeTitle: 'Touch grass',
        challengeCategory: ChallengeCategory.nature,
        photoUrl: 'https://example.com/photo.jpg',
        xpEarned: 25,
        verificationMethod: 'ai_verified',
        completionDate: DateTime(2026, 3, 10),
        createdAt: DateTime(2026, 3, 10),
      );
      final data = memory.toFirestore();
      expect(data['photoUrl'], 'https://example.com/photo.jpg');
      expect(data['userId'], 'u1');
      expect(data['challengeCategory'], 'nature');
      expect(data['xpEarned'], 25);
    });

    test('toFirestore omits null optional fields entirely rather than '
        'writing explicit nulls', () {
      final memory = AdventureMemoryModel(
        memoryId: 'm1',
        userId: 'u1',
        challengeId: 'c1',
        challengeDay: 1,
        challengeTitle: 'Touch grass',
        challengeCategory: ChallengeCategory.nature,
        photoUrl: 'https://example.com/photo.jpg',
        xpEarned: 25,
        verificationMethod: 'ai_verified',
        completionDate: DateTime(2026, 3, 10),
        createdAt: DateTime(2026, 3, 10),
      );
      final data = memory.toFirestore();
      expect(data.containsKey('caption'), isFalse);
      expect(data.containsKey('locationName'), isFalse);
      expect(data.containsKey('weatherCondition'), isFalse);
    });

    test('fromMap defaults a missing photoUrl to an empty string instead of '
        'throwing — a broken/not-yet-uploaded photo must not crash the '
        'journal list', () {
      final memory = AdventureMemoryModel.fromMap({
        'userId': 'u1',
        'challengeId': 'c1',
        'completionDate': Timestamp.fromDate(DateTime(2026, 3, 10)),
        'createdAt': Timestamp.fromDate(DateTime(2026, 3, 10)),
        // photoUrl deliberately absent.
      }, memoryId: 'm1');
      expect(memory.photoUrl, '');
    });

    test('fromMap round-trips a fully-populated toFirestore map', () {
      final original = AdventureMemoryModel(
        memoryId: 'm1',
        userId: 'u1',
        challengeId: 'c1',
        challengeDay: 5,
        challengeTitle: 'Find a hidden trail',
        challengeCategory: ChallengeCategory.exploration,
        photoUrl: 'https://example.com/photo.jpg',
        caption: 'Beautiful views today',
        xpEarned: 50,
        verificationMethod: 'ai_verified',
        completionDate: DateTime(2026, 3, 10),
        createdAt: DateTime(2026, 3, 10),
        latitude: 30.2672,
        longitude: -97.7431,
        locationName: 'Zilker Park',
      );
      // toFirestore's real 'createdAt' is a server-timestamp sentinel that
      // only resolves to a real value once actually written — substitute a
      // real Timestamp here to isolate the round-trip from that write-time
      // behavior, which isn't what this test is checking.
      final data = original.toFirestore()
        ..['createdAt'] = Timestamp.fromDate(original.createdAt)
        ..['completionDate'] = Timestamp.fromDate(original.completionDate);

      final restored = AdventureMemoryModel.fromMap(data, memoryId: 'm1');

      expect(restored.photoUrl, original.photoUrl);
      expect(restored.caption, original.caption);
      expect(restored.challengeCategory, original.challengeCategory);
      expect(restored.latitude, original.latitude);
      expect(restored.longitude, original.longitude);
      expect(restored.locationName, original.locationName);
      expect(restored.xpEarned, original.xpEarned);
    });

    test('fromMap handles a memory with no location/caption/weather — the '
        'minimum a completion can legitimately produce', () {
      final memory = AdventureMemoryModel.fromMap({
        'userId': 'u1',
        'challengeId': 'c1',
        'photoUrl': 'https://example.com/photo.jpg',
        'completionDate': Timestamp.fromDate(DateTime(2026, 3, 10)),
        'createdAt': Timestamp.fromDate(DateTime(2026, 3, 10)),
      }, memoryId: 'm1');
      expect(memory.caption, isNull);
      expect(memory.hasLocation, isFalse);
      expect(memory.weatherCondition, isNull);
      expect(memory.photoUrl, 'https://example.com/photo.jpg');
    });
  });
}

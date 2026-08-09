// Unit tests for AdventureMemoryModel.isAiVerified / verificationLabel — the
// three-way distinction between a real Gemini verification, a manual
// override, and a no-API-key auto-approval. Section 4 introduced a
// fabrication bug where auto-approved completions were mislabeled as
// 'ai_verified'; these tests lock in the fix so the three states can never
// be collapsed back into a binary again.

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
      expect(memoryWith('manual_override').verificationLabel, '✋ Manual Submit');
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
}

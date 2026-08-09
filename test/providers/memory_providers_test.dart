// Unit tests for mergeMemoryPages — the pure de-duplication/ordering logic
// behind MemoriesController's cursor pagination. Firestore itself isn't
// testable here (no emulator/fake in this project), but this merge
// invariant — no duplicate memories, no dropped memories, newer wins on
// conflict, order preserved — is pure and directly testable.

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/models/adventure_memory_model.dart';
import 'package:touchgrass/models/challenge_model.dart';
import 'package:touchgrass/providers/memory_providers.dart';

void main() {
  AdventureMemoryModel memory(String id, {String caption = ''}) =>
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
        caption: caption.isEmpty ? null : caption,
      );

  group('mergeMemoryPages', () {
    test('concatenates two disjoint pages preserving order', () {
      final result = mergeMemoryPages(
        newer: [memory('a'), memory('b')],
        older: [memory('c'), memory('d')],
      );
      expect(result.map((m) => m.memoryId), ['a', 'b', 'c', 'd']);
    });

    test('never produces duplicate memory IDs across pages', () {
      final result = mergeMemoryPages(
        newer: [memory('a'), memory('b')],
        older: [memory('b'), memory('c')],
      );
      expect(result.map((m) => m.memoryId).toSet().length, result.length);
      expect(result.map((m) => m.memoryId), ['a', 'b', 'c']);
    });

    test('a newer entry wins over an older one with the same ID', () {
      final result = mergeMemoryPages(
        newer: [memory('a', caption: 'updated')],
        older: [memory('a', caption: 'stale')],
      );
      expect(result.single.caption, 'updated');
    });

    test('empty older page just returns newer as-is', () {
      final result = mergeMemoryPages(newer: [memory('a')], older: const []);
      expect(result.map((m) => m.memoryId), ['a']);
    });

    test('empty newer page just returns older as-is', () {
      final result = mergeMemoryPages(newer: const [], older: [memory('a')]);
      expect(result.map((m) => m.memoryId), ['a']);
    });
  });
}

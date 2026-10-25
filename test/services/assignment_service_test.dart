// Reroll cap (audit D-06: 3 rerolls per user per local day) and the
// template-only challenge generator that replaced client-side Gemini.
// The server-side half of the cap is covered by firestore-tests/
// (challenges.test.mjs), including the 4th-reroll boundary and concurrency.

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/core/constants/app_constants.dart';
import 'package:touchgrass/core/data/challenge_seed_library.dart';
import 'package:touchgrass/models/challenge_model.dart';
import 'package:touchgrass/repositories/challenge_repository.dart';
import 'package:touchgrass/services/assignment_service.dart';
import 'package:touchgrass/services/challenge_generation_service.dart';

/// Any repository call fails the test: the cap must be enforced before the
/// client attempts a write.
class _NoWriteRepository implements ChallengeRepository {
  const _NoWriteRepository();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      fail('repository must not be touched: ${invocation.memberName}');
}

void main() {
  const generator = ChallengeGenerationService();
  final seed = ChallengeSeedLibrary.selectSeed(
    dayNumber: 3,
    userId: 'u1',
    difficulty: ChallengeDifficulty.medium,
  );
  ChallengeModel challenge({int rerollCount = 0, bool isCompleted = false}) =>
      generator
          .generate(seed: seed, userId: 'u1', dayNumber: 3)
          .copyWith(rerollCount: rerollCount, isCompleted: isCompleted);

  group('reroll cap', () {
    test('the daily cap is 3 (must match firestore.rules maxRerolls())', () {
      expect(AppConstants.maxRerollsPerDay, 3);
    });

    for (final used in [0, 1, 2]) {
      test('allows a reroll after $used of 3', () {
        expect(canReroll(challenge(rerollCount: used)), isTrue);
      });
    }

    test('blocks the 4th reroll (3 of 3 used — boundary)', () {
      expect(canReroll(challenge(rerollCount: 3)), isFalse);
    });

    test('blocks rerolls on legacy documents above the cap', () {
      expect(canReroll(challenge(rerollCount: 12)), isFalse);
    });

    test('blocks rerolling a completed challenge', () {
      expect(canReroll(challenge(isCompleted: true)), isFalse);
    });

    test(
      'rerollChallenge refuses at the cap without writing anything',
      () async {
        const service = AssignmentService(
          challengeRepository: _NoWriteRepository(),
          challengeGenerationService: generator,
        );
        await expectLater(
          service.rerollChallenge('u1', challenge(rerollCount: 3)),
          throwsA(same(rerollLimitReachedError)),
        );
      },
    );
  });

  group('template-only challenge generation (no client AI)', () {
    final now = DateTime(2026, 3, 11, 9, 30);
    final c = generator.generate(
      seed: seed,
      userId: 'u1',
      dayNumber: 3,
      now: now,
    );

    test('is never marked AI-generated', () {
      expect(c.aiGenerated, isFalse);
    });

    test('uses the local calendar date as the document ID', () {
      expect(c.challengeId, '2026-03-11');
    });

    test('xpReward matches the difficulty (rules reject anything else)', () {
      expect(c.xpReward, c.difficulty.xpReward);
    });

    test('starts with no rerolls and not completed', () {
      expect(c.rerollCount, 0);
      expect(c.isCompleted, isFalse);
    });

    test('expires at the next local midnight', () {
      expect(c.expiresAt, DateTime(2026, 3, 12));
    });

    test('is deterministic for the same seed and day', () {
      final again = generator.generate(
        seed: seed,
        userId: 'u1',
        dayNumber: 3,
        now: now,
      );
      expect(again.title, c.title);
      expect(again.description, c.description);
    });
  });
}

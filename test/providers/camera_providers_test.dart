// Unit tests for honorSystemVerificationResult — the pure decision logic
// behind the honor-system auto-approve path (camera_providers.dart's
// verify()), covering both reasons a completion can skip a real Gemini
// call: paid-feature gating (aiLocked) vs. no key configured.

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/core/errors/app_exception.dart';
import 'package:touchgrass/models/challenge_model.dart';
import 'package:touchgrass/providers/camera_providers.dart';

void main() {
  group('diagnosticFailureMessage', () {
    // KNOWN_BUGS.md A1 follow-up: the generic "An unexpected error
    // occurred." text hides exactly which Firestore/Storage condition
    // rejected a request. This is what turns a user's next retry into a
    // usable diagnostic instead of a repeat of the same opaque message.
    test(
      'UnexpectedException wrapping a FirebaseException appends its code',
      () {
        final wrapped = UnexpectedException.wrap(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          ),
        );
        expect(
          diagnosticFailureMessage(wrapped),
          contains('[permission-denied]'),
        );
        expect(diagnosticFailureMessage(wrapped), startsWith(wrapped.message));
      },
    );

    test('UnexpectedException wrapping a non-Firebase cause still surfaces '
        'its type and text, rather than being left generic', () {
      final wrapped = UnexpectedException.wrap(Exception('some other failure'));
      final result = diagnosticFailureMessage(wrapped);
      expect(result, startsWith(wrapped.message));
      expect(result, contains('some other failure'));
    });

    test('a very long cause description is truncated, not dumped in full', () {
      final wrapped = UnexpectedException.wrap(Exception('x' * 500));
      expect(diagnosticFailureMessage(wrapped).length, lessThan(300));
    });

    test('other AppException subtypes are never modified', () {
      final e = DataException.permissionDenied();
      expect(diagnosticFailureMessage(e), equals(e.message));
    });
  });

  group('honorSystemVerificationResult', () {
    test(
      'aiLocked: marks the completion as premium-gated, not AI-verified',
      () {
        final result = honorSystemVerificationResult(aiLocked: true);
        expect(result['aiLocked'], true);
        expect(result.containsKey('confidence'), isFalse);
        expect(result.containsKey('matches'), isFalse);
        expect(result['reason'], contains('premium feature'));
      },
    );

    test('not aiLocked (no key configured): does not claim a premium lock', () {
      final result = honorSystemVerificationResult(aiLocked: false);
      expect(result.containsKey('aiLocked'), isFalse);
      expect(result.containsKey('confidence'), isFalse);
      expect(result.containsKey('matches'), isFalse);
      expect(result['reason'], contains('not configured'));
    });

    test(
      'the two reasons are distinct strings — UI/analytics can tell them apart',
      () {
        final locked = honorSystemVerificationResult(aiLocked: true);
        final unconfigured = honorSystemVerificationResult(aiLocked: false);
        expect(locked['reason'], isNot(equals(unconfigured['reason'])));
      },
    );
  });

  group('CameraVerifying.usingAi', () {
    // Pure construction/default checks — the UI must never claim "AI is
    // reviewing your adventure" for a completion that never calls Gemini.
    // Reaching verify()'s actual honor-system branch needs a fully mocked
    // CameraNotifier (GeminiService/StorageService/repositories), which
    // isn't attempted here; these tests instead pin down the contract the
    // branch relies on: the field defaults to true (matching the real-AI
    // path's behavior) and is only false when explicitly set.
    test('defaults to true, matching the real-Gemini path', () {
      final state = CameraVerifying(bytes: Uint8List(0));
      expect(state.usingAi, isTrue);
    });

    test('can be explicitly set to false for the honor-system path', () {
      final state = CameraVerifying(bytes: Uint8List(0), usingAi: false);
      expect(state.usingAi, isFalse);
    });
  });

  group('CameraFailure.caption / CameraCaptionStep.initialCaption', () {
    // Pure construction checks for the caption-preservation fields — the
    // full retryVerification() -> verify() -> CameraCaptionStep round trip
    // needs a fully mocked CameraNotifier (same limitation noted above for
    // usingAi), so these pin down the contract: a failure carries whatever
    // caption the user had typed, defaulting to null when there wasn't one
    // to lose (e.g. a verification-time failure, which never reaches the
    // caption step at all).
    test('CameraFailure has no caption by default', () {
      final state = CameraFailure(message: 'x', bytes: Uint8List(0));
      expect(state.caption, isNull);
    });

    test('CameraFailure preserves a typed caption through the failure', () {
      final state = CameraFailure(
        message: 'x',
        bytes: Uint8List(0),
        caption: 'It started raining halfway through!',
      );
      expect(state.caption, 'It started raining halfway through!');
    });

    test('CameraCaptionStep has no initialCaption by default', () {
      expect(_captionStep().initialCaption, isNull);
    });

    test(
      'CameraCaptionStep can carry a preserved caption back from a retry',
      () {
        final step = _captionStep(initialCaption: 'Saw a heron by the pond');
        expect(step.initialCaption, 'Saw a heron by the pond');
      },
    );
  });
}

CameraCaptionStep _captionStep({String? initialCaption}) {
  final now = DateTime(2026, 1, 1);
  return CameraCaptionStep(
    bytes: Uint8List(0),
    captionPrompt: 'What did you discover?',
    pendingUserId: 'u1',
    pendingChallenge: ChallengeModel(
      challengeId: 'c1',
      userId: 'u1',
      dayNumber: 1,
      title: 'Find a leaf',
      description: 'd',
      objective: 'o',
      successCriteria: 's',
      challengeCategory: ChallengeCategory.nature,
      difficulty: ChallengeDifficulty.easy,
      xpReward: 10,
      emoji: '🍃',
      estimatedMinutes: 5,
      generatedAt: now,
      expiresAt: now.add(const Duration(days: 1)),
      challengeVersion: 1,
    ),
    pendingVerificationResult: const {},
    pendingPhotoUrl: 'https://example.com/p.jpg',
    initialCaption: initialCaption,
  );
}

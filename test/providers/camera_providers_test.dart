// Unit tests for the camera flow's pure helpers: the honor-system
// verification result every completion records (no AI check runs, and
// since Phase 7G no tier-specific "AI is a premium feature" wording), the
// diagnostic failure message, and CameraVerifying.usingAi.

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/core/errors/app_exception.dart';
import 'package:touchgrass/models/challenge_model.dart';
import 'package:touchgrass/models/completion_model.dart';
import 'package:touchgrass/providers/camera_providers.dart';

void main() {
  group('diagnosticFailureMessage (audit S-9: no raw error text in the UI)', () {
    test(
      'an unexpected Firebase failure shows the friendly text plus its short code',
      () {
        final wrapped = UnexpectedException.wrap(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          ),
        );
        expect(
          diagnosticFailureMessage(wrapped),
          '${wrapped.message} [permission-denied]',
        );
      },
    );

    test('a non-Firebase cause is never shown — only the friendly text', () {
      final wrapped = UnexpectedException.wrap(
        Exception(
          'JSObject: Error at https://internal.example/path?uid=abc123',
        ),
      );
      final result = diagnosticFailureMessage(wrapped);
      expect(result, wrapped.message);
      expect(result, isNot(contains('internal.example')));
      expect(result, isNot(contains('abc123')));
    });

    test('a Firebase error with an unusual code does not leak it either', () {
      final wrapped = UnexpectedException.wrap(
        FirebaseException(
          plugin: 'x',
          code: 'Error: <script>alert(1)</script> at line 4',
        ),
      );
      expect(diagnosticFailureMessage(wrapped), wrapped.message);
    });

    test('typed AppExceptions keep their own friendly message', () {
      final e = DataException.permissionDenied();
      expect(diagnosticFailureMessage(e), equals(e.message));
    });
  });

  group('honorSystemVerificationResult (Phase 7G)', () {
    test('records an honor-system completion, never an AI verdict', () {
      final result = honorSystemVerificationResult();
      expect(result, {'reason': honorSystemReason});
      expect(result.containsKey('confidence'), isFalse);
      expect(result.containsKey('matches'), isFalse);
    });

    test('no longer writes aiLocked or advertises AI as a premium feature', () {
      final result = honorSystemVerificationResult();
      expect(result.containsKey('aiLocked'), isFalse);
      final reason = result['reason'] as String;
      expect(reason, isNot(matches(RegExp(r'AI'))));
      expect(reason.toLowerCase(), isNot(contains('premium')));
      expect(reason.toLowerCase(), isNot(contains('coming soon')));
      expect(reason.toLowerCase(), isNot(contains('verif')));
    });

    test('only keys firestore.rules accept (reason, aiLocked)', () {
      expect(
        honorSystemVerificationResult().keys.every(
          (k) => const {'reason', 'aiLocked'}.contains(k),
        ),
        isTrue,
      );
    });
  });

  group('CameraVerifying.usingAi', () {
    // Pure construction/default checks — the UI must never claim "AI is
    // reviewing your adventure" when no AI is running. Client-side AI was
    // removed (audit D-06), so the default is now the fail-safe `false`:
    // nothing can show the AI copy unless a verifier explicitly opts in.
    test('defaults to false — AI copy is opt-in, never implied', () {
      final state = CameraVerifying(bytes: Uint8List(0));
      expect(state.usingAi, isFalse);
    });

    test('is true only when explicitly set by an AI verifier', () {
      final state = CameraVerifying(bytes: Uint8List(0), usingAi: true);
      expect(state.usingAi, isTrue);
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

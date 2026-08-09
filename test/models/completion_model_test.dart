// Unit tests for CompletionModel.confidenceScore/verificationExplanation —
// specifically that a completion whose verificationResult omits
// 'confidence' (the shape CameraNotifier.override() and the no-API-key
// auto-approve path now produce, after the Section 4 fix that removed
// fabricated confidence:1.0/matches:true) never reports a fabricated score.

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/models/challenge_model.dart';
import 'package:touchgrass/models/completion_model.dart';

void main() {
  CompletionModel completionWith(Map<String, dynamic> verificationResult) =>
      CompletionModel(
        id: 'u1_2026-03-10',
        userId: 'u1',
        challengeId: '2026-03-10',
        challengeTitle: 'Touch grass',
        challengeEmoji: '🌿',
        challengeCategory: ChallengeCategory.nature,
        photoUrl: 'https://example.com/photo.jpg',
        verificationResult: verificationResult,
        completedAt: DateTime(2026, 3, 10),
        xpAwarded: 25,
        overrideUsed: verificationResult['reason'] ==
            'Manually submitted by user after verification failed.',
      );

  group('CompletionModel.confidenceScore', () {
    test('a real AI verification reports its actual confidence', () {
      final c = completionWith(const {
        'matches': true,
        'confidence': 0.87,
        'reason': 'Clearly outdoors.',
      });
      expect(c.confidenceScore, 0.87);
    });

    test('a manual override with no confidence key never fabricates one', () {
      final c = completionWith(const {
        'reason': 'Manually submitted by user after verification failed.',
      });
      expect(c.confidenceScore, 0.0);
      expect(c.overrideUsed, isTrue);
    });

    test('a no-API-key auto-approval with no confidence key never '
        'fabricates one', () {
      final c = completionWith(const {
        'reason': 'Auto-approved — AI verification not configured.',
      });
      expect(c.confidenceScore, 0.0);
      expect(c.overrideUsed, isFalse);
    });
  });
}

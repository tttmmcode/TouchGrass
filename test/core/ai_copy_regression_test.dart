// Phase 7G: AI photo verification is disabled, and the app must not
// advertise it. The camera's caption step used to show "AI verification —
// Coming soon!" (and a premium-feature reason was stored on completions);
// these tests keep that copy from returning anywhere in lib/.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/features/camera/screens/camera_screen.dart';
import 'package:touchgrass/models/challenge_model.dart';
import 'package:touchgrass/models/completion_model.dart';
import 'package:touchgrass/providers/camera_providers.dart';

/// Phrases that announce, sell or claim AI photo verification.
final _banned = RegExp(
  r'\bAI[ -]?(photo )?verif|coming soon|premium feature|verified by AI|'
  r'\bGemini\b|AI[- ]powered|powered by AI|our AI',
  caseSensitive: false,
);

/// The one allowed match: the privacy policy saying photos are NOT sent to
/// an AI service and AI photo verification is turned off.
const _allowed = {
  "'Your photos are not sent to any AI service: AI photo verification is '",
};

/// A single- or double-quoted string literal on one line.
final _stringLiteral = RegExp(
  r"'(?:[^'\\\n]|\\.)*'"
  '|'
  r'"(?:[^"\\\n]|\\.)*"',
);

CompletionModel _completion(Map<String, dynamic> verificationResult) =>
    CompletionModel(
      id: 'u_2026-10-21',
      userId: 'u',
      challengeId: '2026-10-21',
      challengeTitle: 't',
      challengeEmoji: '🌿',
      challengeCategory: ChallengeCategory.values.first,
      photoUrl: 'https://example.test/p.jpg',
      verificationResult: verificationResult,
      completedAt: DateTime.utc(2026, 10, 21),
      xpAwarded: 25,
      overrideUsed: false,
    );

void main() {
  group('no AI-verification announcement in the app (Phase 7G)', () {
    test('no string literal in lib/ advertises or claims AI verification', () {
      final hits = <String>[];
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final file in files) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].trimLeft().startsWith('//')) continue;
          for (final m in _stringLiteral.allMatches(lines[i])) {
            final literal = m.group(0)!;
            if (_banned.hasMatch(literal) && !_allowed.contains(literal)) {
              hits.add('${file.path}:${i + 1} $literal');
            }
          }
        }
      }
      expect(hits, isEmpty);
    });

    test(
      'the scan really sees string literals (guards the scanner itself)',
      () {
        expect(
          _stringLiteral
              .allMatches("x('AI verification — Coming soon!');")
              .map((m) => m.group(0))
              .where((s) => _banned.hasMatch(s!)),
          isNotEmpty,
        );
      },
    );

    test('the unused "AI Verification — Coming Soon" card is gone', () {
      expect(
        File('lib/widgets/ai_feature_locked_card.dart').existsSync(),
        isFalse,
      );
    });
  });

  group('camera caption step copy', () {
    test('says what happened and what saving does — no verification claim', () {
      expect(captionStepStatus, contains('Photo added'));
      expect(captionStepStatus, contains('Journal'));
      expect(_banned.hasMatch(captionStepStatus), isFalse);
      expect(captionStepStatus.toLowerCase(), isNot(contains('verif')));
    });

    test('the button saves to the Journal; it never says "Share"', () {
      expect(captionStepSaveLabel, 'Save to Journal');
      expect(captionStepSaveLabel.toLowerCase(), isNot(contains('share')));
    });
  });

  group('Challenge details: how a completion is described', () {
    test('new completions show the honor-system line', () {
      final c = _completion(honorSystemVerificationResult());
      expect(c.verificationDisplayText, honorSystemReason);
    });

    test('legacy wording advertising AI is never shown again', () {
      for (final legacy in const [
        {
          'reason':
              'Honor-system approved — AI verification is a premium feature.',
          'aiLocked': true,
        },
        {'reason': 'Auto-approved — AI verification not configured.'},
        <String, dynamic>{},
      ]) {
        final shown = _completion(legacy).verificationDisplayText;
        expect(shown, honorSystemReason, reason: '$legacy');
        expect(_banned.hasMatch(shown), isFalse);
      }
    });

    test('an older AI-checked completion keeps its stored explanation', () {
      final c = _completion({
        'confidence': 0.9,
        'reason': 'A tree is visible.',
      });
      expect(c.verificationDisplayText, 'A tree is visible.');
    });
  });

  test(
    'what a new completion writes to Firestore: the honor-system reason only',
    () {
      final data = _completion(honorSystemVerificationResult()).toFirestore();
      expect(data['verificationResult'], {'reason': honorSystemReason});
      expect(data['completedAt'], isA<FieldValue>());
    },
  );
}

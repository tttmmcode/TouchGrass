// Unit tests for GeminiService.parseVerificationResult — the pure
// JSON-extraction/validation step applied to Gemini's raw text response.
// This is the actual "did verification pass or fail" decision logic; the
// network call itself isn't unit-testable without a Gemini fake, but this
// parsing step is pure and covers the malformed-response failure paths
// PART L requires ("Malformed response" / "Unexpected Gemini response").

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/core/errors/app_exception.dart';
import 'package:touchgrass/services/gemini_service.dart';

void main() {
  final service = GeminiService();

  group('GeminiService.parseVerificationResult', () {
    test('parses a clean JSON response', () {
      final result = service.parseVerificationResult(
        '{"matches": true, "confidence": 0.85, "reason": "Looks like a park."}',
      );
      expect(result.confidence, 0.85);
      expect(result.matches, isTrue);
      expect(result.reason, 'Looks like a park.');
    });

    test('extracts JSON even when wrapped in prose or markdown fences', () {
      final result = service.parseVerificationResult(
        'Sure, here you go:\n```json\n{"matches": false, "confidence": 0.3, '
        '"reason": "No plants visible."}\n```',
      );
      expect(result.confidence, 0.3);
      expect(result.matches, isFalse);
    });

    test('recomputes matches from the confidence threshold instead of '
        "trusting Gemini's own matches field", () {
      // Gemini claims matches:true, but confidence is below the 0.6
      // threshold — the app-level decision must not be spoofable by a
      // model that returns an inconsistent pair.
      final result = service.parseVerificationResult(
        '{"matches": true, "confidence": 0.2, "reason": "Uncertain."}',
      );
      expect(result.matches, isFalse);
    });

    test('boundary confidence exactly at the threshold counts as a match', () {
      final result = service.parseVerificationResult(
        '{"matches": false, "confidence": 0.6, "reason": "Borderline."}',
      );
      expect(result.matches, isTrue);
    });

    test('missing reason falls back to an empty string instead of throwing', () {
      final result =
          service.parseVerificationResult('{"matches": true, "confidence": 0.9}');
      expect(result.reason, '');
    });

    test('throws a friendly VerificationException on malformed JSON', () {
      expect(
        () => service.parseVerificationResult('not json at all'),
        throwsA(isA<VerificationException>()),
      );
    });

    test('throws a friendly VerificationException when confidence is missing', () {
      expect(
        () => service.parseVerificationResult('{"reason": "no confidence field"}'),
        throwsA(isA<VerificationException>()),
      );
    });
  });
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';

// Update this when Google deprecates the current model.
const _kModel = 'gemini-2.5-flash';

// Retry budget for quota-exceeded (429) responses.
const _kMaxRetries = 3;
const _kRetryBaseMs = 2000;

// ── Verification result ───────────────────────────────────────────────────────

class VerificationResult {
  const VerificationResult({
    required this.matches,
    required this.confidence,
    required this.reason,
  });

  final bool matches;
  final double confidence;
  final String reason;

  Map<String, dynamic> toMap() => {
        'matches': matches,
        'confidence': confidence,
        'reason': reason,
      };
}

class GeminiService {
  GeminiService()
      : _model = GenerativeModel(
          model: _kModel,
          apiKey: AppConstants.geminiApiKey,
        );

  final GenerativeModel _model;

  Future<VerificationResult> verifyPhoto({
    required Uint8List imageBytes,
    required String challengeTitle,
    required String challengeDescription,
    required String challengeCategory,
  }) async {
    if (AppConstants.geminiApiKey.isEmpty) {
      throw const VerificationException(
        message: 'AI verification is not configured. '
            'Run with --dart-define=GEMINI_API_KEY=<key>.',
      );
    }

    const prompt = '''
You are verifying whether a photo matches an outdoor challenge for a mobile app.
Be encouraging and lenient — if the user made a genuine attempt, accept it.

Respond ONLY with a valid JSON object (no markdown, no explanation):
{"matches": true, "confidence": 0.85, "reason": "Brief reason here"}

Rules:
- confidence is 0.0–1.0
- matches is true when confidence >= 0.6
- reason is one short sentence
''';

    final challengeContext =
        'Challenge: "$challengeTitle". Description: $challengeDescription. '
        'Category: $challengeCategory.';

    try {
      final raw = await _withRetry(() => _model.generateContent([
            Content.multi([
              TextPart('$prompt\n\n$challengeContext'),
              DataPart('image/jpeg', imageBytes),
            ]),
          ]).timeout(
            const Duration(seconds: AppConstants.aiVerificationTimeoutSeconds),
            onTimeout: () => throw VerificationException.timeout(),
          ));

      final text = raw.text;
      if (text == null || text.isEmpty) {
        throw VerificationException.apiError('Empty response from Gemini');
      }
      return _parse(text);
    } on VerificationException {
      rethrow;
    } catch (e) {
      debugPrint('[GeminiService] verifyPhoto error: $e');
      throw VerificationException.apiError(e);
    }
  }

  Future<String> generateCaptionPrompt({
    required String challengeTitle,
    required String challengeCategory,
  }) async {
    try {
      final prompt =
          'Generate a single, unique reflective question to ask a user who just '
          'completed this outdoor challenge: "$challengeTitle" (category: $challengeCategory).\n\n'
          'The question should:\n'
          '• Be personal and specific to the challenge\n'
          '• Invite a short, genuine response (1–3 sentences)\n'
          '• Avoid generic phrasing like "How did it go?"\n'
          '• Be warm and curious in tone\n'
          '• Be under 15 words\n\n'
          'Reply ONLY with the question itself — no quotes, no explanation, '
          'no punctuation except the question mark.';

      final response = await _withRetry(() => _model.generateContent([
            Content.text(prompt),
          ]).timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw VerificationException.timeout(),
          ));

      final text = response.text?.trim() ?? '';
      if (text.isEmpty) return 'What did you discover on your adventure today?';
      return text;
    } catch (_) {
      return "What was the most memorable moment from today's challenge?";
    }
  }

  /// Retries [fn] up to [_kMaxRetries] times on quota-exceeded (429) errors,
  /// with exponential backoff starting at [_kRetryBaseMs] ms.
  Future<T> _withRetry<T>(Future<T> Function() fn) async {
    for (var attempt = 0; attempt <= _kMaxRetries; attempt++) {
      try {
        return await fn();
      } catch (e) {
        final isQuota = e.toString().toLowerCase().contains('quota') ||
            e.toString().contains('429') ||
            e.toString().toLowerCase().contains('resource_exhausted');
        if (!isQuota || attempt == _kMaxRetries) rethrow;
        final delay = _kRetryBaseMs * (1 << attempt); // 2s, 4s, 8s
        debugPrint(
            '[GeminiService] quota exceeded — retrying in ${delay}ms '
            '(attempt ${attempt + 1}/$_kMaxRetries)');
        await Future<void>.delayed(Duration(milliseconds: delay));
      }
    }
    // Unreachable — loop always returns or rethrows.
    throw StateError('_withRetry exited loop unexpectedly');
  }

  VerificationResult _parse(String text) {
    try {
      // Extract the JSON object even when Gemini wraps it in prose or fences.
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start == -1 || end == -1 || end <= start) {
        throw const FormatException('No JSON object found in response');
      }
      final json = jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
      final confidence = (json['confidence'] as num).toDouble();
      return VerificationResult(
        matches: confidence >= AppConstants.aiConfidenceThreshold,
        confidence: confidence,
        reason: json['reason'] as String? ?? '',
      );
    } catch (_) {
      throw VerificationException.apiError(
        'Could not parse verification response.',
      );
    }
  }
}

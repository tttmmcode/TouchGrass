import 'package:flutter/foundation.dart' show visibleForTesting;

import '../core/constants/app_constants.dart';
import '../core/data/challenge_seed_library.dart';
import '../models/challenge_model.dart';

/// Builds today's [ChallengeModel] from the built-in seed library.
///
/// Fully on-device and deterministic for a given seed — no network, no AI.
/// The previous Gemini-backed tiers were removed (audit D-06): they required
/// a Gemini API key compiled into the client, which shipped inside the public
/// web bundle. AI-written challenge text can return only behind an approved
/// server-side implementation (Cloud Functions + Secret Manager).
class ChallengeGenerationService {
  const ChallengeGenerationService();

  /// Returns the challenge for [seed] on [dayNumber]. Never throws.
  ChallengeModel generate({
    required ChallengeSeed seed,
    required String userId,
    required int dayNumber,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final title = _templateTitle(seed);
    return ChallengeModel(
      challengeId: ChallengeModel.docIdForDate(at),
      userId: userId,
      dayNumber: dayNumber,
      title: title,
      description: describe(seed, dayNumber),
      objective: '${_capitalize(seed.action)} ${seed.subject}.',
      successCriteria: seed.successHint,
      difficulty: seed.difficulty,
      estimatedMinutes:
          seed.difficulty.minMinutes +
          ((seed.difficulty.maxMinutes - seed.difficulty.minMinutes) ~/ 2),
      xpReward: seed.difficulty.xpReward,
      challengeCategory: seed.category,
      emoji: seed.category.emoji,
      generatedAt: at,
      expiresAt: DateTime(at.year, at.month, at.day + 1),
      challengeVersion: AppConstants.challengeCurrentVersion,
      rerollCount: 0,
      aiGenerated: false,
      challengeSeed: seed.toString(),
    );
  }

  /// The challenge text. "Go outside and" is added only when the action
  /// doesn't already take you out (Phase 8: "Go outside and go outside
  /// and look for…" was shown).
  @visibleForTesting
  static String describe(ChallengeSeed seed, int dayNumber) {
    final goesOut = _goesOut.hasMatch(seed.action);
    final what = goesOut
        ? '${_capitalize(seed.action)} ${seed.subject}'
        : 'Go outside and ${seed.action} ${seed.subject}';
    return '$what. Take a photo to complete your Day $dayNumber challenge.';
  }

  static final RegExp _goesOut = RegExp(r'^go\b|\boutside\b|\boutdoors\b');

  String _templateTitle(ChallengeSeed seed) {
    // Use theme (already a short noun phrase) rather than truncating subject.
    final words = seed.theme
        .split(' ')
        .map((w) => w.replaceAll(RegExp(r'[,;]$'), ''))
        .take(4)
        .toList();
    if (words.isEmpty) return _capitalize(seed.action);
    return _capitalize(words.first) +
        (words.length > 1 ? ' ${words.skip(1).join(' ')}' : '');
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

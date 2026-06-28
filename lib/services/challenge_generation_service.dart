import 'dart:convert';
import 'dart:developer' as dev;

import 'package:google_generative_ai/google_generative_ai.dart';

import '../core/constants/app_constants.dart';
import '../core/data/challenge_seed_library.dart';
import '../core/errors/app_exception.dart';
import '../models/challenge_model.dart';
import '../models/weather_model.dart';

/// Generates a [ChallengeModel] for a user using Gemini + seed context.
///
/// Three-tier fallback:
///   1. Gemini with full seed + weather + day context (preferred)
///   2. Gemini with minimal prompt (network OK but context failed)
///   3. Synthetic challenge assembled from seed fields (fully offline)
class ChallengeGenerationService {
  ChallengeGenerationService()
      : _model = GenerativeModel(
          model: 'gemini-2.5-flash',
          apiKey: AppConstants.geminiApiKey,
        );

  final GenerativeModel _model;

  /// Generates today's challenge. Always returns a valid [ChallengeModel].
  ///
  /// Throws only on programming errors; all network/AI failures are handled
  /// internally by falling back to synthetic generation.
  Future<ChallengeModel> generate({
    required ChallengeSeed seed,
    required String userId,
    required int dayNumber,
    required List<String> excludedTitles,
    WeatherModel? weather,
  }) async {
    final docId = ChallengeModel.todayDocId();
    final now = DateTime.now();
    final expiresAt = _localMidnight(now).add(const Duration(days: 1));

    // Tier 1: Gemini with full context.
    try {
      final challenge = await _generateWithGemini(
        seed: seed,
        userId: userId,
        dayNumber: dayNumber,
        excludedTitles: excludedTitles,
        weather: weather,
        docId: docId,
        generatedAt: now,
        expiresAt: expiresAt,
      );
      if (challenge.isValid) return challenge;
    } catch (e) {
      dev.log('Tier-1 Gemini generation failed: $e', name: 'ChallengeGenerationService');
    }

    // Tier 2: Gemini minimal (no seed / weather context).
    try {
      final challenge = await _generateMinimal(
        userId: userId,
        dayNumber: dayNumber,
        excludedTitles: excludedTitles,
        docId: docId,
        generatedAt: now,
        expiresAt: expiresAt,
      );
      if (challenge.isValid) return challenge;
    } catch (e) {
      dev.log('Tier-2 Gemini minimal failed: $e', name: 'ChallengeGenerationService');
    }

    // Tier 3: Synthetic from seed — always succeeds.
    dev.log('Falling back to synthetic challenge', name: 'ChallengeGenerationService');
    return _syntheticFromSeed(
      seed: seed,
      userId: userId,
      dayNumber: dayNumber,
      docId: docId,
      generatedAt: now,
      expiresAt: expiresAt,
    );
  }

  // ── Tier 1: Gemini with full context ───────────────────────────────────────

  Future<ChallengeModel> _generateWithGemini({
    required ChallengeSeed seed,
    required String userId,
    required int dayNumber,
    required List<String> excludedTitles,
    required WeatherModel? weather,
    required String docId,
    required DateTime generatedAt,
    required DateTime expiresAt,
  }) async {
    final exclusionNote = excludedTitles.isNotEmpty
        ? '\nAVOID these recent challenge titles: ${excludedTitles.take(10).join('; ')}'
        : '';

    final weatherNote = weather != null
        ? '\nCurrent weather: ${weather.condition}, ${weather.tempRounded}°C. '
            'Design the challenge to be appropriate for these conditions.'
        : '';

    final prompt = '''
You generate daily outdoor challenges for "TouchGrass", a mobile app that motivates people to go outside.

SEED CONTEXT (build your challenge around this):
- Category: ${seed.category.displayName}
- Theme: ${seed.theme}
- Core action: ${seed.action}
- Subject: ${seed.subject}
- What a photo should show: ${seed.successHint}
- Difficulty: ${seed.difficulty.displayName} (${seed.difficulty.minMinutes}–${seed.difficulty.maxMinutes} minutes)
- Day number: Day $dayNumber of this user's TouchGrass journey
- XP reward: ${seed.difficulty.xpReward} XP$weatherNote$exclusionNote

RULES:
• The challenge must be entirely outdoors — the user must leave their home/office
• Safe, legal, and appropriate for all ages and fitness levels
• Concrete and specific — tell the user exactly what to do and photograph
• Achievable in ${seed.difficulty.minMinutes}–${seed.difficulty.maxMinutes} minutes
• The objective field must start with a verb (e.g. "Find", "Photograph", "Explore")
• successCriteria describes what the AI photo verifier should see to approve it

Respond ONLY with a valid JSON object — no markdown, no explanation:
{
  "title": "verb-led title, 3-5 words",
  "emoji": "single relevant emoji",
  "description": "one vivid sentence: what to do and why it is interesting",
  "objective": "single imperative sentence starting with a verb",
  "successCriteria": "what the photo must clearly show for verification",
  "estimatedMinutes": ${seed.difficulty.minMinutes + ((seed.difficulty.maxMinutes - seed.difficulty.minMinutes) ~/ 2)},
  "challengeCategory": "${seed.category.name}"
}
''';

    final response = await _model.generateContent([Content.text(prompt)]).timeout(
      const Duration(seconds: AppConstants.aiGenerationTimeoutSeconds),
      onTimeout: () => throw VerificationException.timeout(),
    );

    final text = response.text;
    if (text == null || text.isEmpty) throw const DataException(message: 'Empty Gemini response');

    return _parseResponse(
      text: text,
      seed: seed,
      userId: userId,
      dayNumber: dayNumber,
      docId: docId,
      generatedAt: generatedAt,
      expiresAt: expiresAt,
      aiGenerated: true,
    );
  }

  // ── Tier 2: Gemini minimal ─────────────────────────────────────────────────

  Future<ChallengeModel> _generateMinimal({
    required String userId,
    required int dayNumber,
    required List<String> excludedTitles,
    required String docId,
    required DateTime generatedAt,
    required DateTime expiresAt,
  }) async {
    final exclusionNote = excludedTitles.isNotEmpty
        ? ' Do not repeat: ${excludedTitles.take(5).join('; ')}.'
        : '';

    final prompt = '''
Generate a single outdoor challenge for a mobile app called TouchGrass.$exclusionNote
The challenge must be outdoors, safe, achievable in 5-20 minutes, verifiable by photo.
Reply ONLY with valid JSON:
{"title":"3-5 word verb-led title","emoji":"emoji","description":"one sentence","objective":"imperative sentence","successCriteria":"what photo must show","estimatedMinutes":10,"challengeCategory":"nature"}
''';

    final response = await _model.generateContent([Content.text(prompt)]).timeout(
      const Duration(seconds: AppConstants.aiGenerationTimeoutSeconds),
      onTimeout: () => throw VerificationException.timeout(),
    );

    final text = response.text;
    if (text == null || text.isEmpty) throw const DataException(message: 'Empty Gemini response');

    // Use a generic seed for the fallback.
    const fallbackSeed = ChallengeSeed(
      category: ChallengeCategory.nature,
      theme: 'outdoor discovery',
      difficulty: ChallengeDifficulty.medium,
      action: 'go outside and find',
      subject: 'something interesting in your environment',
      successHint: 'something interesting found outdoors',
    );

    return _parseResponse(
      text: text,
      seed: fallbackSeed,
      userId: userId,
      dayNumber: dayNumber,
      docId: docId,
      generatedAt: generatedAt,
      expiresAt: expiresAt,
      aiGenerated: true,
    );
  }

  // ── Tier 3: Synthetic from seed ────────────────────────────────────────────

  ChallengeModel _syntheticFromSeed({
    required ChallengeSeed seed,
    required String userId,
    required int dayNumber,
    required String docId,
    required DateTime generatedAt,
    required DateTime expiresAt,
  }) {
    final title = _syntheticTitle(seed);
    return ChallengeModel(
      challengeId: docId,
      userId: userId,
      dayNumber: dayNumber,
      title: title,
      description:
          'Go outside and ${seed.action} ${seed.subject}. '
          'Take a photo to complete your Day $dayNumber challenge.',
      objective: '${_capitalize(seed.action)} ${seed.subject}.',
      successCriteria: seed.successHint,
      difficulty: seed.difficulty,
      estimatedMinutes: seed.difficulty.minMinutes +
          ((seed.difficulty.maxMinutes - seed.difficulty.minMinutes) ~/ 2),
      xpReward: seed.difficulty.xpReward,
      challengeCategory: seed.category,
      emoji: seed.category.emoji,
      generatedAt: generatedAt,
      expiresAt: expiresAt,
      challengeVersion: AppConstants.challengeCurrentVersion,
      rerollCount: 0,
      aiGenerated: false,
      challengeSeed: seed.toString(),
    );
  }

  // ── Parsing ────────────────────────────────────────────────────────────────

  ChallengeModel _parseResponse({
    required String text,
    required ChallengeSeed seed,
    required String userId,
    required int dayNumber,
    required String docId,
    required DateTime generatedAt,
    required DateTime expiresAt,
    required bool aiGenerated,
  }) {
    final clean = text.replaceAll(RegExp(r'```json|```'), '').trim();
    final json = jsonDecode(clean) as Map<String, dynamic>;

    final title = (json['title'] as String? ?? '').trim();
    if (title.isEmpty) throw const DataException(message: 'Empty title from Gemini');

    final category = ChallengeCategory.fromString(
      json['challengeCategory'] as String? ?? seed.category.name,
    );

    final estimatedMinutes = (json['estimatedMinutes'] as num?)?.toInt() ??
        (seed.difficulty.minMinutes + seed.difficulty.maxMinutes) ~/ 2;

    return ChallengeModel(
      challengeId: docId,
      userId: userId,
      dayNumber: dayNumber,
      title: title,
      description: (json['description'] as String? ?? '').trim(),
      objective: (json['objective'] as String? ?? '').trim(),
      successCriteria: (json['successCriteria'] as String? ?? seed.successHint).trim(),
      difficulty: seed.difficulty,
      estimatedMinutes: estimatedMinutes.clamp(
        seed.difficulty.minMinutes,
        seed.difficulty.maxMinutes,
      ),
      xpReward: seed.difficulty.xpReward,
      challengeCategory: category,
      emoji: (json['emoji'] as String? ?? seed.category.emoji).trim(),
      generatedAt: generatedAt,
      expiresAt: expiresAt,
      challengeVersion: AppConstants.challengeCurrentVersion,
      rerollCount: 0,
      aiGenerated: aiGenerated,
      challengeSeed: seed.toString(),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _syntheticTitle(ChallengeSeed seed) {
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

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  DateTime _localMidnight(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day);
}

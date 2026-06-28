import 'dart:developer' as dev;

import '../core/data/challenge_seed_library.dart';
import '../models/challenge_model.dart';
import '../models/weather_model.dart';
import '../repositories/challenge_repository.dart';
import 'challenge_generation_service.dart';
import 'location_service.dart';
import 'weather_service.dart';

class AssignmentService {
  const AssignmentService({
    required ChallengeRepository challengeRepository,
    required ChallengeGenerationService challengeGenerationService,
    required WeatherService weatherService,
    required LocationService locationService,
  })  : _repo = challengeRepository,
        _generator = challengeGenerationService,
        _weather = weatherService,
        _location = locationService;

  final ChallengeRepository _repo;
  final ChallengeGenerationService _generator;
  final WeatherService _weather;
  final LocationService _location;

  // ── Daily challenge ────────────────────────────────────────────────────────

  /// Ensures a challenge exists for today. No-op if one already exists.
  ///
  /// Safe to call multiple times — idempotent via doc existence check.
  Future<void> ensureTodaysChallenge(
    String userId, {
    required int dayNumber,
  }) async {
    try {
      if (await _repo.todaysChallengeExists(userId)) return;

      final challenge = await _buildChallenge(
        userId: userId,
        dayNumber: dayNumber,
        rerollCount: 0,
        excludedTheme: null,
      );
      final result = await _repo.saveChallenge(challenge);
      result.onErr((e) =>
          dev.log('saveChallenge failed: $e', name: 'AssignmentService'));
    } catch (e) {
      dev.log('ensureTodaysChallenge error: $e', name: 'AssignmentService');
    }
  }

  // ── Reroll (unlimited) ─────────────────────────────────────────────────────

  /// Generates a new challenge for today, replacing the existing one.
  ///
  /// Tracks [rerollCount] and avoids repeating today's theme.
  /// Unlimited rerolls — no cap enforced.
  Future<void> rerollChallenge(
    String userId,
    ChallengeModel currentChallenge,
  ) async {
    try {
      final excludedTheme = ChallengeSeedLibrary
          .selectSeed(
            dayNumber: currentChallenge.dayNumber,
            userId: userId,
            difficulty: currentChallenge.difficulty,
          )
          .theme;

      final challenge = await _buildChallenge(
        userId: userId,
        dayNumber: currentChallenge.dayNumber,
        rerollCount: currentChallenge.rerollCount + 1,
        excludedTheme: excludedTheme,
      );

      // Preserve the doc ID (same date) so this overwrites the existing doc.
      final updated = ChallengeModel(
        challengeId: currentChallenge.challengeId,
        userId: challenge.userId,
        dayNumber: challenge.dayNumber,
        title: challenge.title,
        description: challenge.description,
        objective: challenge.objective,
        successCriteria: challenge.successCriteria,
        difficulty: challenge.difficulty,
        estimatedMinutes: challenge.estimatedMinutes,
        xpReward: challenge.xpReward,
        challengeCategory: challenge.challengeCategory,
        emoji: challenge.emoji,
        generatedAt: challenge.generatedAt,
        expiresAt: challenge.expiresAt,
        challengeVersion: challenge.challengeVersion,
        isCompleted: false,
        rerollCount: currentChallenge.rerollCount + 1,
        aiGenerated: challenge.aiGenerated,
        challengeSeed: challenge.challengeSeed,
      );

      final result = await _repo.saveChallenge(updated);
      result.onErr((e) =>
          dev.log('reroll saveChallenge failed: $e', name: 'AssignmentService'));
    } catch (e) {
      dev.log('rerollChallenge error: $e', name: 'AssignmentService');
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  Future<ChallengeModel> _buildChallenge({
    required String userId,
    required int dayNumber,
    required int rerollCount,
    required String? excludedTheme,
  }) async {
    // Pick difficulty based on day number: increases every 7 days, max hard.
    final difficulty = _difficultyForDay(dayNumber);

    // Select seed deterministically (rerollCount shifts the selection).
    final seed = rerollCount == 0
        ? ChallengeSeedLibrary.selectSeed(
            dayNumber: dayNumber,
            userId: userId,
            difficulty: difficulty,
          )
        : ChallengeSeedLibrary.selectRerollSeed(
            dayNumber: dayNumber,
            userId: userId,
            difficulty: difficulty,
            rerollCount: rerollCount,
            excludedTheme: excludedTheme,
          );

    // Fetch exclusion list and weather in parallel; both are best-effort.
    final futures = await Future.wait([
      _repo.fetchRecentChallengeTitles(userId),
      _fetchWeather(),
    ]);
    final excludedTitles = futures[0] as List<String>;
    final weather = futures[1] as WeatherModel?;

    return _generator.generate(
      seed: seed,
      userId: userId,
      dayNumber: dayNumber,
      excludedTitles: excludedTitles,
      weather: weather,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  ChallengeDifficulty _difficultyForDay(int dayNumber) {
    if (dayNumber <= 7) return ChallengeDifficulty.easy;
    if (dayNumber <= 14) return ChallengeDifficulty.medium;
    // After day 14 alternate medium/hard to keep variety.
    return dayNumber.isEven ? ChallengeDifficulty.hard : ChallengeDifficulty.medium;
  }

  Future<WeatherModel?> _fetchWeather() async {
    try {
      final position = await _location.getCurrentLocation();
      if (position == null) return null;
      return _weather.fetchWeather(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (e) {
      dev.log('Weather fetch failed (non-critical): $e',
          name: 'AssignmentService');
      return null;
    }
  }
}

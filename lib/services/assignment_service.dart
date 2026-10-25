import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/app_constants.dart';
import '../core/data/challenge_seed_library.dart';
import '../core/errors/app_exception.dart';
import '../core/result.dart';
import '../models/challenge_model.dart';
import '../repositories/challenge_repository.dart';
import 'analytics_service.dart';
import 'challenge_generation_service.dart';

/// The error [AssignmentService.rerollChallenge] throws once today's reroll
/// budget ([AppConstants.maxRerollsPerDay]) is spent. firestore.rules
/// enforces the same cap server-side, so the client check is only the
/// friendly fast path, never the guard.
const rerollLimitReachedError = DataException(
  message:
      "You've used all ${AppConstants.maxRerollsPerDay} rerolls for today. "
      'A fresh challenge arrives tomorrow!',
);

/// Whether [challenge] can still be rerolled today.
bool canReroll(ChallengeModel challenge) =>
    !challenge.isCompleted &&
    challenge.rerollCount < AppConstants.maxRerollsPerDay;

class AssignmentService {
  const AssignmentService({
    required ChallengeRepository challengeRepository,
    required ChallengeGenerationService challengeGenerationService,
  }) : _repo = challengeRepository,
       _generator = challengeGenerationService;

  final ChallengeRepository _repo;
  final ChallengeGenerationService _generator;

  // ── Daily challenge ────────────────────────────────────────────────────────

  /// Ensures a challenge exists for today. No-op if one already exists.
  ///
  /// Safe to call multiple times — idempotent via doc existence check.
  Future<void> ensureTodaysChallenge(
    String userId, {
    required int dayNumber,
    Set<ChallengeCategory> preferredCategories = const {},
  }) async {
    try {
      if (await _repo.todaysChallengeExists(userId)) return;

      final challenge = _buildChallenge(
        userId: userId,
        dayNumber: dayNumber,
        rerollCount: 0,
        excludedTheme: null,
        preferredCategories: preferredCategories,
      );
      (await _repo.saveChallenge(challenge)).valueOrThrow;
    } catch (e, st) {
      // Never blocks the user — _PendingCard offers a manual retry after a
      // few seconds if generation doesn't complete — but still worth
      // reporting so a persistent failure (e.g. Gemini outage) is visible.
      dev.log('ensureTodaysChallenge error: $e', name: 'AssignmentService');
      CrashReporter.recordError(e, st, reason: 'ensureTodaysChallenge failed');
    }
  }

  // ── Reroll (capped) ────────────────────────────────────────────────────────

  /// Generates a new challenge for today, replacing the existing one.
  ///
  /// Tracks [rerollCount] and avoids repeating today's theme. Capped at
  /// [AppConstants.maxRerollsPerDay] per challenge document (= per local
  /// day); throws [rerollLimitReachedError] once the budget is spent.
  Future<void> rerollChallenge(
    String userId,
    ChallengeModel currentChallenge, {
    Set<ChallengeCategory> preferredCategories = const {},
  }) async {
    if (!canReroll(currentChallenge)) {
      throw rerollLimitReachedError;
    }
    try {
      final excludedTheme = ChallengeSeedLibrary.selectSeed(
        dayNumber: currentChallenge.dayNumber,
        userId: userId,
        difficulty: currentChallenge.difficulty,
        preferredCategories: preferredCategories,
      ).theme;

      final challenge = _buildChallenge(
        userId: userId,
        dayNumber: currentChallenge.dayNumber,
        rerollCount: currentChallenge.rerollCount + 1,
        excludedTheme: excludedTheme,
        preferredCategories: preferredCategories,
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

      final saved = await _repo.saveChallenge(updated);
      if (saved case Err(:final exception)) {
        // The rules deny a reroll past the cap (e.g. the budget was spent on
        // another device since this screen loaded) — say so plainly.
        if (_isPermissionDenied(exception)) throw rerollLimitReachedError;
        throw exception;
      }
    } catch (e, st) {
      if (identical(e, rerollLimitReachedError)) rethrow;
      dev.log('rerollChallenge error: $e', name: 'AssignmentService');
      CrashReporter.recordError(e, st, reason: 'rerollChallenge failed');
      // RerollNotifier.reroll() has its own try/catch that surfaces this to
      // the UI as a retry-able error — swallowing it here would make that
      // dead code and report a failed reroll as a silent success.
      rethrow;
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  ChallengeModel _buildChallenge({
    required String userId,
    required int dayNumber,
    required int rerollCount,
    required String? excludedTheme,
    Set<ChallengeCategory> preferredCategories = const {},
  }) {
    // Pick difficulty based on day number: increases every 7 days, max hard.
    final difficulty = _difficultyForDay(dayNumber);

    // Select seed deterministically (rerollCount shifts the selection).
    final seed = rerollCount == 0
        ? ChallengeSeedLibrary.selectSeed(
            dayNumber: dayNumber,
            userId: userId,
            difficulty: difficulty,
            preferredCategories: preferredCategories,
          )
        : ChallengeSeedLibrary.selectRerollSeed(
            dayNumber: dayNumber,
            userId: userId,
            difficulty: difficulty,
            rerollCount: rerollCount,
            excludedTheme: excludedTheme,
            preferredCategories: preferredCategories,
          );

    return _generator.generate(
      seed: seed,
      userId: userId,
      dayNumber: dayNumber,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static bool _isPermissionDenied(AppException e) {
    final cause = e.cause;
    return cause is FirebaseException && cause.code == 'permission-denied';
  }

  ChallengeDifficulty _difficultyForDay(int dayNumber) {
    if (dayNumber <= 7) return ChallengeDifficulty.easy;
    if (dayNumber <= 14) return ChallengeDifficulty.medium;
    // After day 14 alternate medium/hard to keep variety.
    return dayNumber.isEven
        ? ChallengeDifficulty.hard
        : ChallengeDifficulty.medium;
  }
}

import 'dart:async';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../models/adventure_memory_model.dart';
import '../models/challenge_model.dart';
import '../models/completion_model.dart';
import '../models/weather_model.dart';
import '../repositories/challenge_repository.dart';
import '../repositories/completion_repository.dart';
import '../repositories/memory_repository.dart';
import '../repositories/user_repository.dart';
import '../services/analytics_service.dart';
import '../services/gemini_service.dart';
import '../services/location_service.dart';
import '../services/storage_service.dart';
import '../services/weather_service.dart';
import 'auth_providers.dart';
import 'challenge_providers.dart';
import 'connectivity_providers.dart';
import 'memory_providers.dart';
import 'user_providers.dart';

// ── State ─────────────────────────────────────────────────────────────────────

sealed class CameraFlowState {
  const CameraFlowState();
}

final class CameraIdle extends CameraFlowState {
  const CameraIdle();
}

final class CameraLive extends CameraFlowState {
  const CameraLive();
}

final class CameraImagePicked extends CameraFlowState {
  const CameraImagePicked({required this.bytes});
  final Uint8List bytes;
}

/// Real stage of the verification pipeline, so the UI can show what's
/// actually happening instead of a timer-driven guess.
enum VerifyingStage {
  /// Gemini is analyzing the photo against the challenge.
  analyzing,

  /// Verification passed (or was skipped/overridden); uploading the photo
  /// and fetching location/caption prompt.
  uploading,

  /// Caption submitted; writing the completion, XP, streak and achievements.
  saving,
}

final class CameraVerifying extends CameraFlowState {
  const CameraVerifying({
    required this.bytes,
    this.stage = VerifyingStage.analyzing,
  });
  final Uint8List bytes;
  final VerifyingStage stage;
}

/// Verification passed — waiting for the user to write a caption.
final class CameraCaptionStep extends CameraFlowState {
  const CameraCaptionStep({
    required this.bytes,
    required this.captionPrompt,
    required this.pendingUserId,
    required this.pendingChallenge,
    required this.pendingVerificationResult,
    required this.pendingPhotoUrl,
    this.pendingLocation,
  });

  final Uint8List bytes;
  final String captionPrompt;
  final String pendingUserId;
  final ChallengeModel pendingChallenge;
  final Map<String, dynamic> pendingVerificationResult;
  final String pendingPhotoUrl;
  final GeoPoint? pendingLocation;
}

final class CameraSuccess extends CameraFlowState {
  const CameraSuccess({
    required this.xpAwarded,
    required this.challengeTitle,
    required this.emoji,
    required this.completion,
    required this.newStreak,
    required this.streakIncreased,
    required this.leveledUp,
    required this.newLevel,
    required this.rainyDaysAvailable,
    required this.previousLeague,
    required this.newLeague,
    this.newAchievements = const [],
    this.rainyDayConsumed = false,
    this.rainyDayEarned = 0,
  });
  final int xpAwarded;
  final String challengeTitle;
  final String emoji;
  final CompletionModel completion;
  final int newStreak;

  /// True when this completion actually grew the streak (vs. held it
  /// steady, e.g. a same-day resubmission or a Rainy Day save).
  final bool streakIncreased;
  final bool leveledUp;
  final int newLevel;
  final List<String> newAchievements;
  final bool rainyDayConsumed;
  final int rainyDayEarned;
  final int rainyDaysAvailable;

  /// League ID before this completion. Equal to [newLeague] unless the
  /// completion (or its achievement XP bonus) pushed the user's total XP
  /// into a higher league tier.
  final String previousLeague;

  /// League ID after this completion — always derived from total XP
  /// (see `LeagueDef.idForXp`), never a separate weekly mechanic.
  final String newLeague;

  /// True when the user's league tier actually changed as a result of this
  /// completion. Only ever true when [previousLeague] and [newLeague]
  /// genuinely differ — never inferred or assumed.
  bool get leagueChanged => previousLeague != newLeague;
}

final class CameraFailure extends CameraFlowState {
  const CameraFailure({
    required this.message,
    this.bytes,
    this.confidence,
    this.explanation,
  });
  final String message;
  final Uint8List? bytes;
  final double? confidence;
  final String? explanation;
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class CameraNotifier extends StateNotifier<CameraFlowState> {
  CameraNotifier({
    required this._challenge,
    required this._userId,
    required this._ref,
    required GeminiService geminiService,
    required StorageService storageService,
    required CompletionRepository completionRepository,
    required UserRepository userRepository,
    required ChallengeRepository challengeRepository,
    required MemoryRepository memoryRepository,
  })  : _gemini = geminiService,
        _storage = storageService,
        _completions = completionRepository,
        _users = userRepository,
        _challenges = challengeRepository,
        _memories = memoryRepository,
        _picker = ImagePicker(),
        super(const CameraIdle());

  final ChallengeModel? _challenge;
  final String? _userId;
  final Ref _ref;
  final GeminiService _gemini;
  final StorageService _storage;
  final CompletionRepository _completions;
  final UserRepository _users;
  final ChallengeRepository _challenges;
  final MemoryRepository _memories;
  final ImagePicker _picker;

  /// Pre-flight connectivity check — Gemini verification and Storage upload
  /// both require a live connection, so failing fast with a clear message
  /// beats letting the user sit on a spinner until a network timeout fires.
  bool get _isOffline => _ref.read(isOnlineProvider).valueOrNull == false;

  /// Bumped by [cancelVerification]; captured at the start of [verify]/
  /// [override] so in-flight awaits can tell they were cancelled and skip
  /// their pending `state = ...` write instead of ambushing the user back
  /// into the flow after they've already backed out to the idle screen.
  int _generation = 0;

  /// Lets the user back out of the verifying screen. Does not (and cannot)
  /// abort the underlying network calls, but ensures their eventual result
  /// is discarded instead of overwriting whatever state the user is on by
  /// the time they resolve.
  void cancelVerification() {
    _generation++;
    state = const CameraIdle();
  }

  Future<void> pickImage(ImageSource source) async {
    try {
      final xFile = await _picker.pickImage(
        source: source,
        maxWidth: AppConstants.imageMaxWidthPx.toDouble(),
        maxHeight: AppConstants.imageMaxHeightPx.toDouble(),
        imageQuality: AppConstants.imageQualityPercent,
      );
      if (xFile == null) return;
      final bytes = await xFile.readAsBytes();
      state = CameraImagePicked(bytes: bytes);
    } catch (_) {
      state = const CameraFailure(
        message: 'Could not load that photo. Please try again.',
      );
    }
  }

  Future<void> verify() async {
    final current = state;
    if (current is! CameraImagePicked) return;

    final challenge = _challenge;
    final userId = _userId;
    if (challenge == null || userId == null) {
      state = const CameraFailure(message: 'No active challenge found.');
      return;
    }
    if (challenge.isCompleted) {
      state = const CameraFailure(
        message: "You've already completed today's challenge. Nice work!",
      );
      return;
    }

    final bytes = current.bytes;

    if (_isOffline) {
      state = CameraFailure(
        message: "You're offline. Connect to the internet and try again.",
        bytes: bytes,
      );
      return;
    }

    final gen = ++_generation;
    state = CameraVerifying(bytes: bytes);

    // No API key: skip AI verification and auto-approve so the app works
    // without a Gemini key. Re-enable by configuring GEMINI_API_KEY.
    if (AppConstants.geminiApiKey.isEmpty) {
      state = CameraVerifying(bytes: bytes, stage: VerifyingStage.uploading);
      // Location is a best-effort enrichment — a failure there shouldn't
      // block completion. The photo upload is not optional: silently
      // proceeding with an empty photoUrl would persist a broken
      // completion, so that failure is surfaced instead.
      GeoPoint? location;
      try {
        location = await LocationService().getCurrentLocation();
      } catch (_) {}
      if (gen != _generation) return;
      final String photoUrl;
      try {
        photoUrl = await _storage.uploadCompletionPhoto(
            userId: userId, bytes: bytes);
      } on AppException catch (e) {
        if (gen != _generation) return;
        state = CameraFailure(message: e.message, bytes: bytes);
        return;
      } catch (_) {
        if (gen != _generation) return;
        state = CameraFailure(
          message: 'Upload failed. Please try again.',
          bytes: bytes,
        );
        return;
      }
      if (gen != _generation) return;

      state = CameraCaptionStep(
        bytes: bytes,
        captionPrompt: AppConstants.defaultCaptionPrompt,
        pendingUserId: userId,
        pendingChallenge: challenge,
        // No fabricated confidence/matches — this bypassed AI entirely, so
        // the completion record should honestly say so rather than claiming
        // a verification that never happened.
        pendingVerificationResult: const {
          'reason': 'Auto-approved — AI verification not configured.',
        },
        pendingPhotoUrl: photoUrl,
        pendingLocation: location,
      );
      return;
    }

    final locationFuture = LocationService().getCurrentLocation();
    // The caption prompt is a cosmetic nicety — falling back on failure
    // (same default used elsewhere) means a transient Gemini hiccup here
    // can never sink an already-verified, already-uploading submission via
    // Future.wait's fail-fast behavior below.
    final captionPromptFuture = _gemini
        .generateCaptionPrompt(
          challengeTitle: challenge.title,
          challengeCategory: challenge.challengeCategory.displayName,
        )
        .catchError((_) => AppConstants.defaultCaptionPrompt);

    try {
      final result = await _gemini.verifyPhoto(
        imageBytes: bytes,
        challengeTitle: challenge.title,
        challengeDescription: challenge.description,
        challengeObjective: challenge.objective,
        challengeSuccessCriteria: challenge.successCriteria,
        challengeCategory: challenge.challengeCategory.displayName,
      );
      if (gen != _generation) return;

      if (!result.matches) {
        state = CameraFailure(
          message: VerificationException.lowConfidence(result.confidence).message,
          bytes: bytes,
          confidence: result.confidence,
          explanation: result.reason,
        );
        return;
      }

      AnalyticsService.logVerificationPassed(
        challengeId: challenge.challengeId,
        confidence: result.confidence,
      );

      state = CameraVerifying(bytes: bytes, stage: VerifyingStage.uploading);

      final results = await Future.wait([
        locationFuture,
        captionPromptFuture,
        _storage.uploadCompletionPhoto(userId: userId, bytes: bytes),
      ]);
      if (gen != _generation) return;

      final location = results[0] as GeoPoint?;
      final captionPrompt = results[1] as String;
      final photoUrl = results[2] as String;

      AnalyticsService.logPhotoUploaded(challengeId: challenge.challengeId);

      state = CameraCaptionStep(
        bytes: bytes,
        captionPrompt: captionPrompt,
        pendingUserId: userId,
        pendingChallenge: challenge,
        pendingVerificationResult: result.toMap(),
        pendingPhotoUrl: photoUrl,
        pendingLocation: location,
      );
    } on AppException catch (e) {
      if (gen != _generation) return;
      state = CameraFailure(message: e.message, bytes: bytes);
    } catch (e) {
      if (gen != _generation) return;
      state = CameraFailure(
        message: 'Something went wrong. Please try again.',
        bytes: bytes,
      );
    }
  }

  /// Re-runs verification on the same photo after a failure, without making
  /// the user retake it. Distinct from [retake] (new photo) and [override]
  /// (skip verification entirely).
  Future<void> retryVerification() async {
    final current = state;
    if (current is! CameraFailure || current.bytes == null) return;
    _ref.read(verificationRetryCountProvider.notifier).state++;
    state = CameraImagePicked(bytes: current.bytes!);
    await verify();
  }

  Future<void> submitCaption(String caption) async {
    final current = state;
    if (current is! CameraCaptionStep) return;

    final bytes = current.bytes;
    // Reassign state before the first await (same pattern as verify()/
    // override()) so a rapid double-tap on Submit/Skip can't pass the guard
    // above twice and create two completions — the second call's `state` is
    // no longer CameraCaptionStep, so it returns immediately at the guard.
    state = CameraVerifying(bytes: bytes, stage: VerifyingStage.saving);

    try {
      final trimmed = caption.trim();
      final completionResult = await _completions.createCompletion(
        userId: current.pendingUserId,
        challengeId: current.pendingChallenge.challengeId,
        challengeTitle: current.pendingChallenge.title,
        challengeEmoji: current.pendingChallenge.emoji,
        challengeCategory: current.pendingChallenge.challengeCategory,
        photoUrl: current.pendingPhotoUrl,
        verificationResult: current.pendingVerificationResult,
        xpAwarded: current.pendingChallenge.xpReward,
        overrideUsed: false,
        assignmentDate: current.pendingChallenge.generatedAt,
        location: current.pendingLocation,
        caption: trimmed.isNotEmpty ? trimmed : null,
      );

      CompletionModel? completion;
      completionResult.when(
        ok: (c) => completion = c,
        err: (e) => state = CameraFailure(message: e.message, bytes: bytes),
      );
      if (completion == null) return;

      await _finishWithCompletion(
        completion!,
        bytes,
        current.pendingChallenge,
        captionPrompt: current.captionPrompt,
      );
    } on AppException catch (e) {
      state = CameraFailure(message: e.message, bytes: bytes);
    } catch (_) {
      state = CameraFailure(
        message: 'Something went wrong. Please try again.',
        bytes: bytes,
      );
    }
  }

  Future<void> override() async {
    final current = state;
    final bytes = current is CameraFailure ? current.bytes : null;
    if (bytes == null) {
      state = const CameraFailure(message: 'No photo to submit.');
      return;
    }

    final challenge = _challenge;
    final userId = _userId;
    if (challenge == null || userId == null) {
      state = const CameraFailure(message: 'No active challenge found.');
      return;
    }
    if (challenge.isCompleted) {
      state = const CameraFailure(
        message: "You've already completed today's challenge. Nice work!",
      );
      return;
    }

    if (_isOffline) {
      state = CameraFailure(
        message: "You're offline. Connect to the internet and try again.",
        bytes: bytes,
      );
      return;
    }

    final gen = ++_generation;
    state = CameraVerifying(bytes: bytes, stage: VerifyingStage.uploading);

    try {
      AnalyticsService.logVerificationOverridden(
          challengeId: challenge.challengeId);

      final location = await LocationService().getCurrentLocation();
      final photoUrl = await _storage.uploadCompletionPhoto(
        userId: userId,
        bytes: bytes,
      );
      // Once createCompletion below persists the submission, the flow can
      // no longer be cancelled — the completion already exists in Firestore,
      // so the user must land on the real result rather than being left to
      // wonder whether their submission went through.
      if (gen != _generation) return;
      AnalyticsService.logPhotoUploaded(challengeId: challenge.challengeId);

      final completionResult = await _completions.createCompletion(
        userId: userId,
        challengeId: challenge.challengeId,
        challengeTitle: challenge.title,
        challengeEmoji: challenge.emoji,
        challengeCategory: challenge.challengeCategory,
        photoUrl: photoUrl,
        // No fabricated confidence — the user submitted this without AI
        // agreement, so the record should say exactly that (overrideUsed
        // below is the authoritative signal), not claim a verification score
        // that was never computed.
        verificationResult: const {
          'reason': 'Manually submitted by user after verification failed.',
        },
        xpAwarded: challenge.xpReward,
        overrideUsed: true,
        assignmentDate: challenge.generatedAt,
        location: location,
      );

      CompletionModel? completion;
      completionResult.when(
        ok: (c) => completion = c,
        err: (e) => state = CameraFailure(message: e.message, bytes: bytes),
      );
      if (completion == null) return;

      await _finishWithCompletion(completion!, bytes, challenge);
    } on AppException catch (e) {
      if (gen != _generation) return;
      state = CameraFailure(message: e.message, bytes: bytes);
    } catch (_) {
      if (gen != _generation) return;
      state = CameraFailure(
        message: 'Something went wrong. Please try again.',
        bytes: bytes,
      );
    }
  }

  Future<void> _finishWithCompletion(
    CompletionModel completion,
    Uint8List bytes,
    ChallengeModel challenge, {
    String? captionPrompt,
  }) async {
    // Fire-and-forget: create adventure memory in background.
    unawaited(_createMemory(completion, challenge, captionPrompt));

    // Mark the challenge document as completed. Best-effort: the completion
    // doc's deterministic per-day ID (see CompletionRepository) is the real
    // source of truth for "already completed," so a failure here shouldn't
    // block the reward transaction below — but it also shouldn't be
    // silently swallowed, since it can leave challenge.isCompleted stale.
    final markResult = await _challenges.markChallengeCompleted(
      completion.userId,
      challenge.challengeId,
    );
    markResult.onErr((e) => dev.log(
          'markChallengeCompleted failed for ${challenge.challengeId}: '
          '${e.message}',
          name: 'CameraNotifier',
        ));

    final rewardResult = await _users.awardCompletionRewards(
      uid: completion.userId,
      xpAmount: completion.xpAwarded,
    );

    if (rewardResult.isOk) {
      final reward = rewardResult.valueOrThrow;
      AnalyticsService.logChallengeComplete(
        challengeId: completion.challengeId,
        category: completion.challengeCategory.name,
        xpAwarded: reward.xpAwarded,
      );
      if (reward.leveledUp) AnalyticsService.logLevelUp(reward.newLevel);
      for (final id in reward.newAchievements) {
        AnalyticsService.logAchievementUnlocked(id);
      }
      if (reward.leaguePromoted) {
        AnalyticsService.logLeaguePromotion(
          fromLeague: reward.previousLeague,
          toLeague: reward.updatedUser.currentLeague,
        );
      }
      state = CameraSuccess(
        xpAwarded: reward.xpAwarded,
        challengeTitle: completion.challengeTitle,
        emoji: completion.challengeEmoji,
        completion: completion,
        newStreak: reward.newStreak,
        streakIncreased: reward.streakIncreased,
        leveledUp: reward.leveledUp,
        newLevel: reward.newLevel,
        newAchievements: reward.newAchievements,
        rainyDayConsumed: reward.rainyDayConsumed,
        rainyDayEarned: reward.rainyDayEarned,
        rainyDaysAvailable: reward.rainyDaysAvailable,
        previousLeague: reward.previousLeague,
        newLeague: reward.updatedUser.currentLeague,
      );
      return;
    }

    // The reward write may have partially or fully succeeded even though
    // this call reported failure (e.g. a later step inside it threw) —
    // re-fetch the real user doc instead of showing fabricated numbers that
    // could contradict what's actually persisted.
    final fresh = (await _users.fetchUser(completion.userId)).valueOrNull;
    // We don't know the pre-completion streak/league here (the write's own
    // result is what would have told us), so previousStreak/previousLeague
    // are set equal to the fresh values — the celebration screen then
    // correctly shows neither a false "streak extended" nor a false league
    // change rather than guessing.
    state = CameraSuccess(
      xpAwarded: completion.xpAwarded,
      challengeTitle: completion.challengeTitle,
      emoji: completion.challengeEmoji,
      completion: completion,
      newStreak: fresh?.streak ?? 0,
      streakIncreased: false,
      leveledUp: false,
      newLevel: fresh?.level ?? 1,
      rainyDaysAvailable: fresh?.rainyDaysAvailable ?? 0,
      previousLeague: fresh?.currentLeague ?? 'seedling',
      newLeague: fresh?.currentLeague ?? 'seedling',
    );
  }

  /// Creates the [AdventureMemoryModel] entry for this completion.
  ///
  /// Runs in the background — never blocks the success screen.
  /// Fetches weather and reverse-geocodes location name in parallel.
  Future<void> _createMemory(
    CompletionModel completion,
    ChallengeModel challenge,
    String? captionPrompt,
  ) async {
    try {
      final loc = completion.location;
      String? locationName;
      String? weatherCondition;
      String? weatherEmoji;

      if (loc != null) {
        // Fetch location name + weather in parallel.
        final results = await Future.wait([
          LocationService().getLocationName(
            latitude: loc.latitude,
            longitude: loc.longitude,
          ),
          WeatherService().fetchWeather(
            latitude: loc.latitude,
            longitude: loc.longitude,
          ),
        ]);
        locationName = results[0] as String?;
        final weather = results[1] as WeatherModel?;
        if (weather != null) {
          weatherCondition = weather.condition;
          weatherEmoji = weather.emoji;
        }
      }

      final memory = AdventureMemoryModel(
        memoryId: completion.id,
        userId: completion.userId,
        challengeId: completion.challengeId,
        challengeDay: challenge.dayNumber,
        challengeTitle: completion.challengeTitle,
        challengeCategory: completion.challengeCategory,
        photoUrl: completion.photoUrl,
        caption: completion.caption,
        captionPrompt: captionPrompt,
        latitude: loc?.latitude,
        longitude: loc?.longitude,
        locationName: locationName,
        weatherCondition: weatherCondition,
        weatherEmoji: weatherEmoji,
        xpEarned: completion.xpAwarded,
        // 'ai_verified' only when Gemini actually ran (its result map
        // carries a 'confidence' key) — the no-API-key auto-approve path
        // shares overrideUsed:false with it but never called Gemini, so it
        // must not be mislabeled as AI-verified either.
        verificationMethod: completion.overrideUsed
            ? 'manual_override'
            : completion.verificationResult.containsKey('confidence')
                ? 'ai_verified'
                : 'auto_approved',
        completionDate: completion.completedAt,
        createdAt: completion.completedAt,
      );

      await _memories.createMemory(memory);
    } catch (_) {
      // Memory creation is best-effort — never affect the completion flow.
    }
  }

  void startLiveCamera() => state = const CameraLive();

  void retake() {
    _ref.read(verificationRetryCountProvider.notifier).state = 0;
    state = const CameraLive();
  }

  void setBytes(Uint8List bytes) => state = CameraImagePicked(bytes: bytes);

  void reset() {
    _ref.read(verificationRetryCountProvider.notifier).state = 0;
    state = const CameraIdle();
  }
}

/// Counts consecutive "Retry Verification" taps for the photo currently in
/// hand, so the failure screen can nudge toward "Submit Anyway" after
/// repeated failures instead of showing the identical prompt forever (a
/// user stuck in a retry loop should be gently pointed at the way out).
/// Reset on [CameraNotifier.retake]/[CameraNotifier.reset] and whenever
/// verification succeeds (a fresh [CameraImagePicked] not reached via
/// retry starts at zero, since only [retryVerification] increments this).
final verificationRetryCountProvider = StateProvider.autoDispose<int>((_) => 0);

// ── Service providers ─────────────────────────────────────────────────────────

final geminiServiceProvider = Provider<GeminiService>((_) => GeminiService());

// storageServiceProvider is defined in user_providers.dart — import that file.

final completionRepositoryProvider =
    Provider<CompletionRepository>((_) => const CompletionRepository());

// ── Camera notifier provider ──────────────────────────────────────────────────

final cameraFlowProvider =
    StateNotifierProvider.autoDispose<CameraNotifier, CameraFlowState>((ref) {
  // Use ref.read (not ref.watch) for challenge and auth so that Firestore
  // updates to the challenge document (e.g. markChallengeCompleted) do NOT
  // re-create this notifier mid-flow and wipe the CameraSuccess state.
  return CameraNotifier(
    challenge: ref.read(todaysChallengeProvider).valueOrNull,
    userId: ref.read(authStateProvider).valueOrNull?.uid,
    ref: ref,
    geminiService: ref.watch(geminiServiceProvider),
    storageService: ref.watch(storageServiceProvider),
    completionRepository: ref.watch(completionRepositoryProvider),
    userRepository: ref.watch(userRepositoryProvider),
    challengeRepository: ref.watch(challengeRepositoryProvider),
    memoryRepository: ref.watch(memoryRepositoryProvider),
  );
});

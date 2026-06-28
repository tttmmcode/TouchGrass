import 'dart:async';
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

final class CameraVerifying extends CameraFlowState {
  const CameraVerifying({required this.bytes});
  final Uint8List bytes;
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
    required this.leveledUp,
    required this.newLevel,
    required this.rainyDaysAvailable,
    this.newAchievements = const [],
    this.rainyDayConsumed = false,
    this.rainyDayEarned = 0,
  });
  final int xpAwarded;
  final String challengeTitle;
  final String emoji;
  final CompletionModel completion;
  final int newStreak;
  final bool leveledUp;
  final int newLevel;
  final List<String> newAchievements;
  final bool rainyDayConsumed;
  final int rainyDayEarned;
  final int rainyDaysAvailable;
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
  final GeminiService _gemini;
  final StorageService _storage;
  final CompletionRepository _completions;
  final UserRepository _users;
  final ChallengeRepository _challenges;
  final MemoryRepository _memories;
  final ImagePicker _picker;

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
    } catch (_) {}
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

    final bytes = current.bytes;
    state = CameraVerifying(bytes: bytes);

    // No API key: skip AI verification and auto-approve so the app works
    // without a Gemini key. Re-enable by configuring GEMINI_API_KEY.
    if (AppConstants.geminiApiKey.isEmpty) {
      // Best-effort uploads — failures don't block the completion flow.
      GeoPoint? location;
      String photoUrl = '';
      try {
        location = await LocationService().getCurrentLocation();
      } catch (_) {}
      try {
        photoUrl = await _storage.uploadCompletionPhoto(
            userId: userId, bytes: bytes);
      } catch (_) {}

      state = CameraCaptionStep(
        bytes: bytes,
        captionPrompt: 'What did you discover on your outdoor adventure today?',
        pendingUserId: userId,
        pendingChallenge: challenge,
        pendingVerificationResult: const {
          'matches': true,
          'confidence': 1.0,
          'reason': 'Auto-approved',
        },
        pendingPhotoUrl: photoUrl,
        pendingLocation: location,
      );
      return;
    }

    final locationFuture = LocationService().getCurrentLocation();
    final captionPromptFuture = _gemini.generateCaptionPrompt(
      challengeTitle: challenge.title,
      challengeCategory: challenge.challengeCategory.displayName,
    );

    try {
      final result = await _gemini.verifyPhoto(
        imageBytes: bytes,
        challengeTitle: challenge.title,
        challengeDescription: challenge.description,
        challengeCategory: challenge.challengeCategory.displayName,
      );

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

      final results = await Future.wait([
        locationFuture,
        captionPromptFuture,
        _storage.uploadCompletionPhoto(userId: userId, bytes: bytes),
      ]);

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
      state = CameraFailure(message: e.message, bytes: bytes);
    } catch (e) {
      state = CameraFailure(
        message: 'Something went wrong. Please try again.',
        bytes: bytes,
      );
    }
  }

  Future<void> submitCaption(String caption) async {
    final current = state;
    if (current is! CameraCaptionStep) return;

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
        err: (e) => state = CameraFailure(
          message: e.message,
          bytes: current.bytes,
        ),
      );
      if (completion == null) return;

      await _finishWithCompletion(
        completion!,
        current.bytes,
        current.pendingChallenge,
        captionPrompt: current.captionPrompt,
      );
    } on AppException catch (e) {
      final bytes = (state as CameraCaptionStep?)?.bytes;
      state = CameraFailure(message: e.message, bytes: bytes);
    } catch (_) {
      final bytes = (state as CameraCaptionStep?)?.bytes;
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

    state = CameraVerifying(bytes: bytes);

    try {
      AnalyticsService.logVerificationOverridden(
          challengeId: challenge.challengeId);

      final location = await LocationService().getCurrentLocation();
      final photoUrl = await _storage.uploadCompletionPhoto(
        userId: userId,
        bytes: bytes,
      );
      AnalyticsService.logPhotoUploaded(challengeId: challenge.challengeId);

      final completionResult = await _completions.createCompletion(
        userId: userId,
        challengeId: challenge.challengeId,
        challengeTitle: challenge.title,
        challengeEmoji: challenge.emoji,
        challengeCategory: challenge.challengeCategory,
        photoUrl: photoUrl,
        verificationResult: const {
          'matches': true,
          'confidence': 1.0,
          'reason': 'Manually submitted by user',
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
      state = CameraFailure(message: e.message, bytes: bytes);
    } catch (_) {
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

    // Mark the challenge document as completed.
    await _challenges.markChallengeCompleted(
      completion.userId,
      challenge.challengeId,
    );

    final rewardResult = await _users.awardCompletionRewards(
      uid: completion.userId,
      xpAmount: completion.xpAwarded,
    );

    rewardResult.when(
      ok: (reward) {
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
          leveledUp: reward.leveledUp,
          newLevel: reward.newLevel,
          newAchievements: reward.newAchievements,
          rainyDayConsumed: reward.rainyDayConsumed,
          rainyDayEarned: reward.rainyDayEarned,
          rainyDaysAvailable: reward.rainyDaysAvailable,
        );
      },
      err: (_) => state = CameraSuccess(
        xpAwarded: completion.xpAwarded,
        challengeTitle: completion.challengeTitle,
        emoji: completion.challengeEmoji,
        completion: completion,
        newStreak: 1,
        leveledUp: false,
        newLevel: 1,
        rainyDaysAvailable: 0,
      ),
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
        verificationMethod:
            completion.overrideUsed ? 'manual_override' : 'ai_verified',
        completionDate: completion.completedAt,
        createdAt: completion.completedAt,
      );

      await _memories.createMemory(memory);
    } catch (_) {
      // Memory creation is best-effort — never affect the completion flow.
    }
  }

  void startLiveCamera() => state = const CameraLive();

  void retake() => state = const CameraLive();

  void setBytes(Uint8List bytes) => state = CameraImagePicked(bytes: bytes);

  void reset() => state = const CameraIdle();
}

// ── Service providers ─────────────────────────────────────────────────────────

final geminiServiceProvider = Provider<GeminiService>((_) => GeminiService());

// storageServiceProvider is defined in user_providers.dart — import that file.

final completionRepositoryProvider = Provider<CompletionRepository>((ref) {
  return CompletionRepository(
    firestoreService: ref.watch(firestoreServiceProvider),
  );
});

// ── Camera notifier provider ──────────────────────────────────────────────────

final cameraFlowProvider =
    StateNotifierProvider.autoDispose<CameraNotifier, CameraFlowState>((ref) {
  // Use ref.read (not ref.watch) for challenge and auth so that Firestore
  // updates to the challenge document (e.g. markChallengeCompleted) do NOT
  // re-create this notifier mid-flow and wipe the CameraSuccess state.
  return CameraNotifier(
    challenge: ref.read(todaysChallengeProvider).valueOrNull,
    userId: ref.read(authStateProvider).valueOrNull?.uid,
    geminiService: ref.watch(geminiServiceProvider),
    storageService: ref.watch(storageServiceProvider),
    completionRepository: ref.watch(completionRepositoryProvider),
    userRepository: ref.watch(userRepositoryProvider),
    challengeRepository: ref.watch(challengeRepositoryProvider),
    memoryRepository: ref.watch(memoryRepositoryProvider),
  );
});

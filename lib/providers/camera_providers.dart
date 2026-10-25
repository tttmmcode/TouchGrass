import 'dart:async';
import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../core/result.dart';
import '../models/challenge_model.dart';
import '../models/completion_model.dart';
import '../models/weather_model.dart';
import '../repositories/challenge_repository.dart';
import '../repositories/completion_repository.dart';
import '../repositories/memory_repository.dart';
import '../repositories/user_repository.dart';
import '../services/analytics_service.dart';
import '../services/location_service.dart';
import '../services/storage_service.dart';
import '../services/weather_service.dart';
import 'auth_providers.dart';
import 'challenge_providers.dart';
import 'connectivity_providers.dart';
import 'location_privacy_providers.dart';
import 'map_providers.dart';
import 'user_providers.dart';
import 'weather_providers.dart';

/// The `verificationResult` map recorded on an honor-system completion —
/// every completion today, since AI photo verification is disabled (audit
/// D-06). The same for every tier: the earlier free-tier wording advertised
/// AI verification as a "premium feature, coming soon", which Phase 7G
/// removed. firestore.rules only accept the keys `reason` and `aiLocked`,
/// so a client can't record a fake AI verdict; `aiLocked` is no longer
/// written. Extracted as a pure function so it's unit-testable without
/// mocking [CameraNotifier]'s Firebase-backed dependencies.
@visibleForTesting
Map<String, dynamic> honorSystemVerificationResult() {
  return const {'reason': honorSystemReason};
}

// ── Diagnostics ──────────────────────────────────────────────────────────────

/// The user-facing text for a failure (audit S-9). Typed [AppException]s
/// already carry a friendly message and are returned as is. For the generic
/// [UnexpectedException], only a short Firebase error code is appended
/// (e.g. `[permission-denied]`) so support can tell failures apart; raw
/// cause text (JS error dumps, paths, IDs) is never shown to users. The full
/// cause goes to crash reporting instead.
///
/// Replaces the temporary diagnostic aid from KNOWN_BUGS.md A1, which
/// appended the raw cause text while that (since fixed) web bug was traced.
@visibleForTesting
String diagnosticFailureMessage(AppException e) {
  if (e is! UnexpectedException) return e.message;
  final cause = e.cause;
  CrashReporter.recordError(
    cause ?? e,
    null,
    reason: 'camera flow: ${e.message}',
  );
  if (cause is FirebaseException &&
      RegExp(r'^[a-z][a-z0-9-]{0,40}$').hasMatch(cause.code)) {
    return '${e.message} [${cause.code}]';
  }
  return e.message;
}

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
  /// AI is analyzing the photo. Unused while AI verification is disabled
  /// (audit D-06); kept for the future server-side verifier.
  analyzing,

  /// Uploading the photo (and reading location, if the user allows it).
  uploading,

  /// Caption submitted; writing the completion, XP, streak, achievements
  /// and the Journal entry in one atomic batch.
  saving,
}

final class CameraVerifying extends CameraFlowState {
  const CameraVerifying({
    required this.bytes,
    this.stage = VerifyingStage.analyzing,
    this.usingAi = false,
  });
  final Uint8List bytes;
  final VerifyingStage stage;

  /// Whether an AI verifier is actually reviewing this photo — the UI must
  /// never claim AI is reviewing when no AI call is happening. Defaults to
  /// `false` (fail-safe): client-side AI was removed (audit D-06), and only
  /// a future server-side verifier may set it.
  final bool usingAi;
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
    this.initialCaption,
  });

  final Uint8List bytes;
  final String captionPrompt;
  final String pendingUserId;
  final ChallengeModel pendingChallenge;
  final Map<String, dynamic> pendingVerificationResult;
  final String pendingPhotoUrl;
  final GeoPoint? pendingLocation;

  /// Text the user had already typed before a submission failure sent them
  /// back through [CameraNotifier.retryVerification] — carried here so the
  /// caption field can be pre-filled instead of forcing a full retype of
  /// their reflection. Null on the normal (first-attempt) path.
  final String? initialCaption;
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
    this.savedToJournal = false,
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

  /// True when the Journal entry (with this photo) was committed in the same
  /// batch as the completion — only then may the UI say it's saved.
  final bool savedToJournal;
}

/// What went wrong, so the UI can say what was (not) saved and whether a
/// retry can help (audit D-13).
enum CameraFailureKind {
  /// The photo didn't upload. Nothing was saved; retrying is safe.
  uploadFailed,

  /// The photo uploaded but the completion (and its Journal entry) wasn't
  /// saved. Nothing was counted; retrying is safe and can't double-count.
  saveFailed,

  /// Today's challenge is already completed and in the Journal. Final.
  alreadyCompleted,

  /// Anything else (no challenge, photo couldn't be loaded, …).
  other,
}

final class CameraFailure extends CameraFlowState {
  const CameraFailure({
    required this.message,
    this.bytes,
    this.confidence,
    this.explanation,
    this.caption,
    this.kind = CameraFailureKind.other,
  });
  final String message;
  final CameraFailureKind kind;

  /// Whether Retry can help: there's a photo to retry with and the failure
  /// isn't final.
  bool get canRetry =>
      bytes != null && kind != CameraFailureKind.alreadyCompleted;
  final Uint8List? bytes;
  final double? confidence;
  final String? explanation;

  /// The reflection the user had already typed when this failure happened
  /// (submission-time failures only — verification-time failures never
  /// reach the caption step, so this is null there). Carried through so a
  /// retry can restore it instead of forcing a retype; see
  /// [CameraCaptionStep.initialCaption].
  final String? caption;
}

// ── Notifier ──────────────────────────────────────────────────────────────────

/// Message shown when today's completion already exists (a retry after a
/// save whose confirmation was lost, a double-tap, or a second device).
const alreadyCompletedMessage =
    "You've already completed today's challenge — it's saved in your Journal.";

/// Place name and weather looked up for a photo's location, to enrich its
/// Journal entry. Only ever fetched when the user allows optional location
/// use (audit D-09).
class _PlaceAndWeather {
  const _PlaceAndWeather({this.name, this.condition, this.emoji});
  final String? name;
  final String? condition;
  final String? emoji;
}

class CameraNotifier extends StateNotifier<CameraFlowState> {
  CameraNotifier({
    required this._challenge,
    required this._userId,
    required this._ref,
    required StorageService storageService,
    required CompletionRepository completionRepository,
    required UserRepository userRepository,
    required ChallengeRepository challengeRepository,
    required LocationService locationService,
    required WeatherService weatherService,
  }) : _storage = storageService,
       _completions = completionRepository,
       _users = userRepository,
       _challenges = challengeRepository,
       _location = locationService,
       _weather = weatherService,
       _picker = ImagePicker(),
       super(const CameraIdle());

  final ChallengeModel? _challenge;
  final String? _userId;
  final Ref _ref;
  final StorageService _storage;
  final CompletionRepository _completions;
  final UserRepository _users;
  final ChallengeRepository _challenges;
  final LocationService _location;
  final WeatherService _weather;
  final ImagePicker _picker;

  /// Pre-flight connectivity check — the photo upload and the completion
  /// commit both require a live connection, so failing fast with a clear message
  /// beats letting the user sit on a spinner until a network timeout fires.
  bool get _isOffline => _ref.read(isOnlineProvider).valueOrNull == false;

  /// The user's optional-location setting (audit D-09), read at each step so
  /// switching it off mid-flow takes effect before anything is saved.
  bool get _locationAllowed => _ref.read(optionalLocationAllowedProvider);

  /// Bumped by [cancelVerification]; captured at the start of [verify]/
  /// [override] so in-flight awaits can tell they were cancelled and skip
  /// their pending `state = ...` write instead of ambushing the user back
  /// into the flow after they've already backed out to the idle screen.
  int _generation = 0;

  /// Caption text preserved from a [CameraFailure] that happened during
  /// [submitCaption] (i.e. after the user had already typed a reflection),
  /// set by [retryVerification] and consumed once by the next successful
  /// [CameraCaptionStep] this run produces — see [CameraCaptionStep.initialCaption].
  String? _pendingCaptionOnRetry;

  /// Place name + weather lookup started while the user writes a caption,
  /// so the Journal entry can be saved with them in the completion batch.
  Future<_PlaceAndWeather?>? _enrichment;

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

  /// Checks that a photo may be submitted for [challenge] now. Returns the
  /// failure to show, or null to proceed.
  Future<CameraFailure?> _preflight(
    ChallengeModel? challenge,
    String? userId,
    Uint8List bytes,
  ) async {
    if (challenge == null || userId == null) {
      return const CameraFailure(message: 'No active challenge found.');
    }
    if (challenge.isCompleted) {
      return const CameraFailure(
        message: alreadyCompletedMessage,
        kind: CameraFailureKind.alreadyCompleted,
      );
    }
    if (_isOffline) {
      return CameraFailure(
        message:
            "You're offline, so nothing was uploaded or saved. "
            'Connect to the internet and tap Retry.',
        bytes: bytes,
        kind: CameraFailureKind.uploadFailed,
      );
    }
    // The photo path is fixed per completion, so uploading again after the
    // completion was saved would replace the photo it points to. Check the
    // authoritative completion first (the challenge's isCompleted flag can
    // lag behind, e.g. when a save's confirmation was lost).
    final completionId = CompletionRepository.completionDocId(
      userId,
      challenge.challengeId,
    );
    final bool exists;
    try {
      exists = await _completions.exists(completionId);
    } catch (_) {
      return CameraFailure(
        message:
            "We couldn't reach TouchGrass, so nothing was uploaded or "
            'saved. Check your connection and tap Retry.',
        bytes: bytes,
        kind: CameraFailureKind.uploadFailed,
      );
    }
    if (exists) {
      return const CameraFailure(
        message: alreadyCompletedMessage,
        kind: CameraFailureKind.alreadyCompleted,
      );
    }
    return null;
  }

  /// Reads the location (only if the user allows it) and uploads the photo
  /// to its fixed per-completion path. Returns the upload's download URL and
  /// location, or sets a failure state and returns null.
  Future<({String photoUrl, GeoPoint? location})?> _uploadPhoto({
    required int gen,
    required String userId,
    required ChallengeModel challenge,
    required Uint8List bytes,
  }) async {
    // Location is an optional enrichment (audit D-09): never read unless the
    // user allows it, and a failure there never blocks the completion.
    GeoPoint? location;
    if (_locationAllowed) {
      try {
        location = await _location.getCurrentLocation();
      } catch (_) {}
    }
    if (gen != _generation) return null;
    try {
      final photoUrl = await _storage.uploadCompletionPhoto(
        userId: userId,
        challengeId: challenge.challengeId,
        bytes: bytes,
      );
      if (gen != _generation) return null;
      AnalyticsService.logPhotoUploaded(challengeId: challenge.challengeId);
      return (photoUrl: photoUrl, location: location);
    } catch (e) {
      if (gen != _generation) return null;
      final detail = e is AppException
          ? ' (${diagnosticFailureMessage(e)})'
          : '';
      state = CameraFailure(
        message:
            "Your photo didn't upload, so nothing was saved. "
            'Tap Retry to try again.$detail',
        bytes: bytes,
        kind: CameraFailureKind.uploadFailed,
      );
      return null;
    }
  }

  Future<void> verify() async {
    final current = state;
    if (current is! CameraImagePicked) return;
    final bytes = current.bytes;
    final gen = ++_generation;

    // AI photo verification is disabled on every tier (audit D-06): the
    // client never holds an AI key, and the server-side verifier
    // (functions/) is not deployed. Every submission is honor-system
    // approved, the UI never claims AI is reviewing it (`usingAi: false`),
    // and the stored verification record says exactly why no AI ran —
    // never a fabricated confidence/match verdict (firestore.rules reject
    // one anyway).
    state = CameraVerifying(
      bytes: bytes,
      stage: VerifyingStage.uploading,
      usingAi: false,
    );

    final challenge = _challenge;
    final userId = _userId;
    final blocked = await _preflight(challenge, userId, bytes);
    if (gen != _generation) return;
    if (blocked != null) {
      state = blocked;
      return;
    }

    final uploaded = await _uploadPhoto(
      gen: gen,
      userId: userId!,
      challenge: challenge!,
      bytes: bytes,
    );
    if (uploaded == null) return;

    // Look up the place name and weather while the user writes a caption.
    _enrichment = uploaded.location == null
        ? null
        : _lookUpPlaceAndWeather(uploaded.location!);

    state = CameraCaptionStep(
      bytes: bytes,
      captionPrompt: AppConstants.defaultCaptionPrompt,
      pendingUserId: userId,
      pendingChallenge: challenge,
      pendingVerificationResult: honorSystemVerificationResult(),
      pendingPhotoUrl: uploaded.photoUrl,
      pendingLocation: uploaded.location,
      initialCaption: _pendingCaptionOnRetry,
    );
    _pendingCaptionOnRetry = null;
  }

  /// Retries after a failure with the same photo, without making the user
  /// retake it. Safe to repeat: the photo goes to the same fixed path and
  /// the save is create-only, so nothing is ever saved or counted twice.
  /// Distinct from [retake] (new photo) and [override] (skip verification).
  Future<void> retryVerification() async {
    final current = state;
    if (current is! CameraFailure || !current.canRetry) return;
    _ref.read(verificationRetryCountProvider.notifier).state++;
    _pendingCaptionOnRetry = current.caption;
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

    if (_isOffline) {
      state = CameraFailure(
        message:
            "You're offline, so your adventure isn't saved yet. "
            'Reconnect and tap Retry — nothing will be counted twice.',
        bytes: bytes,
        caption: caption,
        kind: CameraFailureKind.saveFailed,
      );
      return;
    }

    final trimmed = caption.trim();
    await _commit(
      bytes: bytes,
      caption: caption,
      userId: current.pendingUserId,
      challenge: current.pendingChallenge,
      photoUrl: current.pendingPhotoUrl,
      location: current.pendingLocation,
      verificationResult: current.pendingVerificationResult,
      overrideUsed: false,
      captionText: trimmed.isNotEmpty ? trimmed : null,
      captionPrompt: current.captionPrompt,
    );
  }

  Future<void> override() async {
    final current = state;
    final bytes = current is CameraFailure ? current.bytes : null;
    if (bytes == null) {
      state = const CameraFailure(message: 'No photo to submit.');
      return;
    }
    final gen = ++_generation;
    // Manual override — the user explicitly chose "Submit Anyway" after AI
    // verification failed or was skipped, so AI is definitionally not
    // reviewing this submission.
    state = CameraVerifying(
      bytes: bytes,
      stage: VerifyingStage.uploading,
      usingAi: false,
    );

    final challenge = _challenge;
    final userId = _userId;
    final blocked = await _preflight(challenge, userId, bytes);
    if (gen != _generation) return;
    if (blocked != null) {
      state = blocked;
      return;
    }
    AnalyticsService.logVerificationOverridden(
      challengeId: challenge!.challengeId,
    );

    final uploaded = await _uploadPhoto(
      gen: gen,
      userId: userId!,
      challenge: challenge,
      bytes: bytes,
    );
    if (uploaded == null) return;
    _enrichment = uploaded.location == null
        ? null
        : _lookUpPlaceAndWeather(uploaded.location!);

    // Once the commit below persists the submission, the flow can no
    // longer be cancelled — the user must land on the real result.
    state = CameraVerifying(bytes: bytes, stage: VerifyingStage.saving);
    await _commit(
      bytes: bytes,
      userId: userId,
      challenge: challenge,
      photoUrl: uploaded.photoUrl,
      location: uploaded.location,
      // No fabricated confidence — the user submitted this without AI
      // agreement, so the record says exactly that (overrideUsed below is
      // the authoritative signal).
      verificationResult: const {
        'reason': 'Manually submitted by user after verification failed.',
      },
      overrideUsed: true,
    );
  }

  /// Saves the completion, reward and Journal entry in one atomic batch
  /// (audit D-13), then shows the committed result — or a failure that says
  /// nothing was saved and whether Retry can help.
  Future<void> _commit({
    required Uint8List bytes,
    required String userId,
    required ChallengeModel challenge,
    required String photoUrl,
    required GeoPoint? location,
    required Map<String, dynamic> verificationResult,
    required bool overrideUsed,
    String? caption,
    String? captionText,
    String? captionPrompt,
  }) async {
    try {
      // Re-check the setting now: if the user switched it off after the
      // photo was taken, nothing location-related is saved.
      final allowLocation = _locationAllowed;
      final savedLocation = allowLocation ? location : null;
      final place = savedLocation == null ? null : await _placeAndWeather();

      final draft = _completions.buildCompletion(
        userId: userId,
        challengeId: challenge.challengeId,
        challengeTitle: challenge.title,
        challengeEmoji: challenge.emoji,
        challengeCategory: challenge.challengeCategory,
        photoUrl: photoUrl,
        verificationResult: verificationResult,
        xpAwarded: challenge.xpReward,
        overrideUsed: overrideUsed,
        assignmentDate: challenge.generatedAt,
        location: savedLocation,
        caption: captionText,
      );

      final result = await _users.commitCompletion(
        draft,
        journalEntry: (completion) => journalEntryForCompletion(
          completion,
          challengeDay: challenge.dayNumber,
          includeLocation: allowLocation,
          captionPrompt: captionPrompt,
          locationName: place?.name,
          weatherCondition: place?.condition,
          weatherEmoji: place?.emoji,
        ),
      );
      switch (result) {
        case Ok(:final value):
          await _finishWithCompletion(value, challenge);
        case Err(:final exception):
          final already = exception.message.contains('already completed');
          state = CameraFailure(
            message: already
                ? alreadyCompletedMessage
                : 'Your photo is uploaded, but your adventure isn\'t saved '
                      'yet and nothing was counted. Tap Retry to save it. '
                      '(${diagnosticFailureMessage(exception)})',
            bytes: bytes,
            caption: caption,
            kind: already
                ? CameraFailureKind.alreadyCompleted
                : CameraFailureKind.saveFailed,
          );
      }
    } catch (_) {
      state = CameraFailure(
        message:
            'Your photo is uploaded, but your adventure isn\'t saved '
            'yet and nothing was counted. Tap Retry to save it.',
        bytes: bytes,
        caption: caption,
        kind: CameraFailureKind.saveFailed,
      );
    }
  }

  /// The enrichment started at upload, waited for briefly: it's cosmetic,
  /// so a slow lookup never holds up saving.
  Future<_PlaceAndWeather?> _placeAndWeather() async {
    final pending = _enrichment;
    _enrichment = null;
    if (pending == null) return null;
    try {
      return await pending.timeout(const Duration(seconds: 4));
    } catch (_) {
      return null;
    }
  }

  /// Sends the photo's coordinates to the platform geocoder (place name) and
  /// Open-Meteo (weather, coarse coordinates). Only called when the user
  /// allows optional location use. Never throws.
  Future<_PlaceAndWeather?> _lookUpPlaceAndWeather(GeoPoint loc) async {
    try {
      final results = await Future.wait([
        _location.getLocationName(
          latitude: loc.latitude,
          longitude: loc.longitude,
        ),
        _weather.fetchWeather(
          latitude: coarseCoordinate(loc.latitude),
          longitude: coarseCoordinate(loc.longitude),
        ),
      ]);
      final weather = results[1] as WeatherModel?;
      return _PlaceAndWeather(
        name: results[0] as String?,
        condition: weather?.condition,
        emoji: weather?.emoji,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _finishWithCompletion(
    CompletionCommit commit,
    ChallengeModel challenge,
  ) async {
    final completion = commit.completion;
    final reward = commit.reward;

    // Mark the challenge document as completed. Best-effort: the completion
    // doc's deterministic per-day ID (see CompletionRepository) is the real
    // source of truth for "already completed," so a failure here must not
    // undo the success — but it also shouldn't be silently swallowed, since
    // it can leave challenge.isCompleted stale.
    final markResult = await _challenges.markChallengeCompleted(
      completion.userId,
      challenge.challengeId,
    );
    markResult.onErr(
      (e) => dev.log(
        'markChallengeCompleted failed for ${challenge.challengeId}: '
        '${e.message}',
        name: 'CameraNotifier',
      ),
    );

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
      savedToJournal: commit.journalEntry != null,
    );
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

// storageServiceProvider is defined in user_providers.dart — import that file.

final completionRepositoryProvider = Provider<CompletionRepository>(
  (_) => CompletionRepository(),
);

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
        storageService: ref.watch(storageServiceProvider),
        completionRepository: ref.watch(completionRepositoryProvider),
        userRepository: ref.watch(userRepositoryProvider),
        challengeRepository: ref.watch(challengeRepositoryProvider),
        locationService: ref.watch(locationServiceProvider),
        weatherService: ref.watch(weatherServiceProvider),
      );
    });

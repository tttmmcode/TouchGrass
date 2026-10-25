import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_exception.dart';
import '../models/challenge_model.dart';
import '../models/completion_model.dart';
import '../providers/entitlement_providers.dart';

/// Outcome of submitting a photo for challenge verification — the same
/// shape regardless of which [ChallengeVerificationService] implementation
/// produced it, so a future caller genuinely doesn't need to know or care
/// which one ran.
sealed class VerificationSubmitOutcome {
  const VerificationSubmitOutcome();
}

final class VerificationSubmitRejected extends VerificationSubmitOutcome {
  const VerificationSubmitRejected({
    required this.confidence,
    required this.reason,
  });
  final double confidence;
  final String reason;
}

/// Deliberately just the fields both implementations can actually produce —
/// not the full [CompletionReward]/[UserModel] shape the client reward
/// path returns, since fabricating a whole placeholder [UserModel] (many required
/// fields — email, settings, achievements, etc.) for the remote path would
/// misrepresent data the Cloud Function never sends back.
@immutable
class VerificationReward {
  const VerificationReward({
    required this.xpAwarded,
    required this.newXp,
    required this.newLevel,
    required this.newStreak,
    required this.newLeague,
  });
  final int xpAwarded;
  final int newXp;
  final int newLevel;
  final int newStreak;
  final String newLeague;
}

final class VerificationSubmitAccepted extends VerificationSubmitOutcome {
  const VerificationSubmitAccepted({
    required this.completion,
    required this.reward,
  });
  final CompletionModel completion;
  final VerificationReward reward;
}

/// Verifies a completion photo against a challenge and, if it matches,
/// authoritatively records the completion and its reward.
///
/// This interface intentionally matches the Cloud Function's real contract
/// (`functions/src/index.ts`'s `verifyChallengeCompletion`): the photo is
/// already uploaded to Storage, and verification + reward happen as one
/// atomic step — not a separate "verify" then "reward" pair — because the
/// server-authoritative design (KNOWN_BUGS.md B1) depends on the two never
/// being split apart, otherwise a client could call a real "verify" step
/// and then fabricate the reward write on its own.
///
/// **Not currently wired into `CameraNotifier`** (`lib/providers/camera_providers.dart`).
/// That flow shows the user a caption-entry step *between* a successful
/// verification and the completion being created, which this atomic
/// verify+reward contract has no room for without either dropping the
/// caption step or asking for it before verification — a real UX decision,
/// not just an implementation swap, so it's deliberately left for a
/// dedicated follow-up rather than decided silently here. See
/// functions/README.md for the full cutover plan.
abstract class ChallengeVerificationService {
  Future<VerificationSubmitOutcome> submit({
    required ChallengeModel challenge,
    required String userId,
    required String storagePath,
    Uint8List? imageBytes,
  });
}

/// Calls the server-authoritative `verifyChallengeCompletion` Cloud
/// Function (`functions/src/index.ts`) — real, compiled, callable code, but
/// the function has never been deployed in this environment (no Blaze
/// billing configured; see functions/README.md), so this implementation is
/// untested against a live backend. It exists so the abstraction has a
/// genuine second implementation ready for whenever a call site adopts it,
/// not as a stub.
///
/// [canUseAiVerification], if provided, is checked client-side before
/// spending a network call — purely a UX nicety to fail fast with a clear
/// message; the Cloud Function enforces the real entitlement/quota check
/// server-side regardless (KNOWN_BUGS.md / Phase 12), so this is never the
/// security boundary.
///
/// **Fail-closed by construction**: every path through [submit] either
/// returns [VerificationSubmitAccepted] built from a real server response
/// with `matches: true`, or throws. There is no branch that awards a
/// reward, marks a completion verified, or falls back to on-device
/// verification when the callable is unreachable/misconfigured/undeployed
/// — an unreachable Cloud Function surfaces as a thrown [AppException] a
/// caller can show as a friendly error, never as a silent success.
class RemoteVerificationService implements ChallengeVerificationService {
  RemoteVerificationService({
    FirebaseFunctions? functions,
    bool Function()? entitlementCheck,
  }) : _functions = functions ?? FirebaseFunctions.instance,
       _canUseAiVerification = entitlementCheck;

  final FirebaseFunctions _functions;
  final bool Function()? _canUseAiVerification;

  @override
  Future<VerificationSubmitOutcome> submit({
    required ChallengeModel challenge,
    required String userId,
    required String storagePath,
    Uint8List? imageBytes,
  }) async {
    if (_canUseAiVerification != null && !_canUseAiVerification()) {
      throw DataException.permissionDenied();
    }

    final callable = _functions.httpsCallable(
      'verifyChallengeCompletion',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
    );

    final Map<String, dynamic> data;
    try {
      final response = await callable.call<Map<String, dynamic>>({
        'challengeId': challenge.challengeId,
        'storagePath': storagePath,
      });
      data = response.data;
    } on FirebaseFunctionsException catch (e) {
      throw _mapFunctionsException(e);
    } catch (e) {
      // Anything else — e.g. a raw network/platform error if the function
      // is undeployed or unreachable — still fails closed (thrown, not
      // swallowed), just wrapped in a friendly message instead of a raw
      // platform exception reaching the UI.
      throw NetworkException(
        message: "We couldn't verify your photo right now.",
        cause: e,
      );
    }

    final matches = data['matches'] as bool? ?? false;
    if (!matches) {
      return VerificationSubmitRejected(
        confidence: (data['confidence'] as num?)?.toDouble() ?? 0.0,
        reason: data['reason'] as String? ?? '',
      );
    }

    // The callable is authoritative for the reward — this only reshapes its
    // response into app types, never recomputing or trusting a client value.
    final completion = CompletionModel(
      id: '${userId}_${challenge.challengeId}',
      userId: userId,
      challengeId: challenge.challengeId,
      challengeTitle: challenge.title,
      challengeEmoji: challenge.emoji,
      challengeCategory: challenge.challengeCategory,
      photoUrl: storagePath,
      verificationResult: {
        'matches': true,
        'confidence': data['confidence'],
        'reason': data['reason'],
      },
      xpAwarded: (data['xpAwarded'] as num?)?.toInt() ?? 0,
      overrideUsed: false,
      completedAt: DateTime.now(),
      assignmentDate: challenge.generatedAt,
    );

    return VerificationSubmitAccepted(
      completion: completion,
      // Callers needing the full updated UserModel (not just these fields)
      // should re-fetch via UserRepository.fetchUser — same fallback
      // pattern CameraNotifier._finishWithCompletion already uses when a
      // reward write's own result is incomplete.
      reward: VerificationReward(
        xpAwarded: (data['xpAwarded'] as num?)?.toInt() ?? 0,
        newXp: (data['newXp'] as num?)?.toInt() ?? 0,
        newLevel: (data['newLevel'] as num?)?.toInt() ?? 1,
        newStreak: (data['newStreak'] as num?)?.toInt() ?? 0,
        newLeague: data['newLeague'] as String? ?? 'seedling',
      ),
    );
  }

  AppException _mapFunctionsException(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return AuthException.sessionExpired();
      case 'permission-denied':
        return DataException.permissionDenied();
      case 'resource-exhausted':
        return DataException(message: e.message ?? 'Quota exceeded.');
      case 'not-found':
        return DataException.notFound(e.message ?? 'Resource');
      case 'invalid-argument':
        return DataException(message: e.message ?? 'Invalid request.');
      default:
        return VerificationException.apiError(e);
    }
  }
}

// ── Providers ────────────────────────────────────────────────────────────────

/// The only [ChallengeVerificationService]: the server-authoritative Cloud
/// Function. The former on-device Gemini implementation was removed (audit
/// D-06) — the client never holds an AI key, in any build. Until the function
/// is deployed (requires Blaze) and a call site adopts this, AI verification
/// stays disabled and completions use the honor-system path in
/// CameraNotifier; this provider fails closed rather than falling back.
final challengeVerificationServiceProvider =
    Provider<ChallengeVerificationService>((ref) {
      return RemoteVerificationService(
        entitlementCheck: () => ref.read(canUseAiVerificationProvider),
      );
    });

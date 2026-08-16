import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../core/result.dart';
import '../models/challenge_model.dart';
import '../models/completion_model.dart';

class CompletionRepository {
  const CompletionRepository();

  /// The canonical completion document ID for a user's challenge:
  /// `${userId}_${challengeId}` (challengeId is itself the `yyyy-MM-dd`
  /// per-user challenge doc ID, so this is stable per user per day even
  /// across rerolls).
  ///
  /// This exact format is also encoded in `firestore.rules`'s `completions`
  /// `allow create` rule (`completionId == request.auth.uid + '_' +
  /// request.resource.data.challengeId`) — the two must stay in sync, since
  /// together they're what makes duplicate completions for the same day
  /// impossible to write, even via a direct SDK/REST call that bypasses this
  /// repository entirely. Extracted as its own method (rather than inlined)
  /// specifically so that contract is unit-testable.
  @visibleForTesting
  static String completionDocId(String userId, String challengeId) =>
      '${userId}_$challengeId';

  /// Creates a completion for [userId]/[challengeId].
  ///
  /// Uses [completionDocId] so two concurrent submissions for the same
  /// day's challenge can never both succeed — the second always fails with
  /// a friendly [DataException] instead of creating a duplicate completion
  /// (and therefore duplicate XP/streak/achievement awards downstream).
  ///
  /// Deliberately does a plain `.set()` rather than a `runTransaction`
  /// read-then-write. Firestore itself already atomically classifies a
  /// `.set()` on a path with no existing document as a `create` and one on
  /// an existing document as an `update` — `firestore.rules`'s `completions`
  /// match block allows the former (for the doc's own future owner) and
  /// denies the latter outright, so the server enforces "only once" without
  /// any client-side read-check-write race window needed.
  ///
  /// A prior version of this method used `runTransaction` for the same
  /// exists-check — on Flutter Web, `cloud_firestore_web`'s `runTransaction`
  /// has a known js_interop gap where an exception thrown inside the
  /// transaction closure doesn't cross back into Dart as a typed exception,
  /// surfacing instead as a generic, opaque JS error ("Dart exception
  /// thrown from converted Future...") that made every completion attempt
  /// fail with no diagnosable cause. See KNOWN_BUGS.md A1 for the full
  /// trace. Mobile builds never hit that bug, but this plain-`.set()` form
  /// works identically and correctly everywhere, so there's no reason to
  /// keep two code paths.
  Future<Result<CompletionModel>> createCompletion({
    required String userId,
    required String challengeId,
    required String challengeTitle,
    required String challengeEmoji,
    required ChallengeCategory challengeCategory,
    required String photoUrl,
    required Map<String, dynamic> verificationResult,
    required int xpAwarded,
    required bool overrideUsed,
    DateTime? assignmentDate,
    GeoPoint? location,
    String? caption,
  }) => guardAsync(() async {
    final now = DateTime.now();
    final docId = completionDocId(userId, challengeId);

    final completion = CompletionModel(
      id: docId,
      userId: userId,
      challengeId: challengeId,
      challengeTitle: challengeTitle,
      challengeEmoji: challengeEmoji,
      challengeCategory: challengeCategory,
      photoUrl: photoUrl,
      verificationResult: verificationResult,
      completedAt: now,
      xpAwarded: xpAwarded,
      overrideUsed: overrideUsed,
      assignmentDate: assignmentDate,
      location: location,
      caption: caption,
    );

    final ref = FirebaseFirestore.instance
        .collection(AppConstants.colCompletions)
        .doc(docId);

    try {
      await ref.set(completion.toFirestore());
    } on FirebaseException catch (e) {
      // The only way this specific, correctly-shaped, self-owned write
      // hits `permission-denied` is the doc already existing (`allow
      // update: if false`) — every other `allow create` condition is
      // satisfied by construction above.
      if (e.code == 'permission-denied') {
        throw const DataException(
          message: "You've already completed today's challenge.",
        );
      }
      rethrow;
    }

    return completion;
  });
}

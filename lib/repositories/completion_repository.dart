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
  /// repository's own transaction below. Extracted as its own method (rather
  /// than inlined) specifically so that contract is unit-testable.
  @visibleForTesting
  static String completionDocId(String userId, String challengeId) =>
      '${userId}_$challengeId';

  /// Creates a completion for [userId]/[challengeId].
  ///
  /// Uses [completionDocId] combined with a transactional exists-check, so
  /// two concurrent submissions for the same day's challenge can never both
  /// succeed — the second always fails with a friendly [DataException]
  /// instead of creating a duplicate completion (and therefore duplicate
  /// XP/streak/achievement awards downstream).
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
  }) =>
      guardAsync(() async {
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

        await FirebaseFirestore.instance.runTransaction((tx) async {
          final existing = await tx.get(ref);
          if (existing.exists) {
            throw const DataException(
              message: "You've already completed today's challenge.",
            );
          }
          tx.set(ref, completion.toFirestore());
        });

        return completion;
      });
}

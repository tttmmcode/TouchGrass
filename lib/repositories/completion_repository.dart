import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/app_constants.dart';
import '../models/challenge_model.dart';
import '../models/completion_model.dart';

class CompletionRepository {
  CompletionRepository({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// The canonical completion document ID for a user's challenge:
  /// `${userId}_${challengeId}` (challengeId is itself the `yyyy-MM-dd`
  /// per-user challenge doc ID, so this is stable per user per day even
  /// across rerolls).
  ///
  /// This exact format is also encoded in `firestore.rules`'s `completions`
  /// create rule (`completionId == uid + '_' + challengeId`, with
  /// challengeId a date within ±1 day of server time) — the two must stay in
  /// sync, since together they make duplicate completions for the same day
  /// impossible to write, even via a direct SDK/REST call. Extracted as its
  /// own method (rather than inlined) specifically so that contract is
  /// unit-testable.
  static String completionDocId(String userId, String challengeId) =>
      '${userId}_$challengeId';

  /// Builds the completion for [userId]/[challengeId] without writing it.
  ///
  /// The write happens in [UserRepository.commitCompletion], in the same
  /// atomic batch as the reward update: firestore.rules only accept an XP
  /// increase when it is committed together with a brand-new completion
  /// document (audit D-02), and completions are create-only, so a retried or
  /// duplicated submission can never be rewarded twice.
  CompletionModel buildCompletion({
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
  }) => CompletionModel(
    id: completionDocId(userId, challengeId),
    userId: userId,
    challengeId: challengeId,
    challengeTitle: challengeTitle,
    challengeEmoji: challengeEmoji,
    challengeCategory: challengeCategory,
    photoUrl: photoUrl,
    verificationResult: verificationResult,
    completedAt: DateTime.now(),
    xpAwarded: xpAwarded,
    overrideUsed: overrideUsed,
    assignmentDate: assignmentDate,
    location: location,
    caption: caption,
  );

  /// Whether the completion document already exists — used to explain a
  /// rejected commit as "already completed" rather than a generic error.
  /// Reading a nonexistent completion is allowed by the rules.
  Future<bool> exists(String completionId) async {
    final snap = await _db
        .collection(AppConstants.colCompletions)
        .doc(completionId)
        .get();
    return snap.exists;
  }

  /// `completedAt` of [userId]'s most recent completion, or null if they
  /// have none. Used once per legacy account (no `lastCompletionDate` yet)
  /// to recover the real last-completion day without a data migration.
  /// Served by the existing (userId ASC, completedAt DESC) index.
  Future<DateTime?> latestCompletedAt(String userId) async {
    final snap = await _db
        .collection(AppConstants.colCompletions)
        .where('userId', isEqualTo: userId)
        .orderBy('completedAt', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final ts = snap.docs.first.data()['completedAt'];
    return ts is Timestamp ? ts.toDate().toUtc() : null;
  }
}

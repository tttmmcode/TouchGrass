import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/app_constants.dart';
import '../core/result.dart';
import '../models/challenge_model.dart';
import '../models/completion_model.dart';
import '../services/firestore_service.dart';

/// Reads and writes challenges stored in the per-user subcollection:
///   `users/{uid}/challenges/{yyyy-MM-dd}`
///
/// [FirestoreService] only handles top-level collections, so subcollection
/// operations use [FirebaseFirestore.instance] directly.
class ChallengeRepository {
  ChallengeRepository({required FirestoreService firestoreService})
      : _firestore = firestoreService;

  final FirestoreService _firestore;

  // ── Subcollection ref helpers ───────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _challengesCol(String uid) =>
      FirebaseFirestore.instance
          .collection(AppConstants.colUsers)
          .doc(uid)
          .collection(AppConstants.colUserChallenges);

  DocumentReference<Map<String, dynamic>> _challengeDoc(
          String uid, String docId) =>
      _challengesCol(uid).doc(docId);

  // ── Today's challenge ──────────────────────────────────────────────────────

  /// Live stream of today's challenge document. Emits `null` if not yet generated.
  Stream<ChallengeModel?> watchTodaysChallenge(String uid) {
    final docId = ChallengeModel.todayDocId();
    return _challengeDoc(uid, docId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      try {
        return ChallengeModel.fromFirestore(snap);
      } catch (e) {
        dev.log('watchTodaysChallenge parse error: $e',
            name: 'ChallengeRepository');
        return null;
      }
    });
  }

  /// One-shot fetch of today's challenge.
  Future<ChallengeModel?> fetchTodaysChallenge(String uid) async {
    try {
      final snap = await _challengeDoc(uid, ChallengeModel.todayDocId()).get();
      if (!snap.exists || snap.data() == null) return null;
      return ChallengeModel.fromFirestore(snap);
    } catch (e) {
      dev.log('fetchTodaysChallenge error: $e', name: 'ChallengeRepository');
      return null;
    }
  }

  /// Returns true if a challenge document already exists for today.
  Future<bool> todaysChallengeExists(String uid) async {
    try {
      final snap = await _challengeDoc(uid, ChallengeModel.todayDocId()).get();
      return snap.exists;
    } catch (e) {
      return false;
    }
  }

  // ── Write ──────────────────────────────────────────────────────────────────

  /// Saves (or overwrites) a challenge. Used both for initial generation
  /// and for rerolls (same doc ID, incremented rerollCount).
  Future<Result<void>> saveChallenge(ChallengeModel challenge) =>
      guardAsync(() async {
        await _challengeDoc(challenge.userId, challenge.challengeId)
            .set(challenge.toFirestore(), SetOptions(merge: false));
      });

  /// Updates only the completion fields; does not touch generation fields.
  Future<Result<void>> markChallengeCompleted(
    String uid,
    String docId,
  ) =>
      guardAsync(() async {
        await _challengeDoc(uid, docId).update({
          'isCompleted': true,
          'completionDate': Timestamp.fromDate(DateTime.now()),
        });
      });

  // ── History & deduplication ────────────────────────────────────────────────

  /// Returns the titles of recent challenges for Gemini dedup.
  Future<List<String>> fetchRecentChallengeTitles(
    String uid, {
    int limit = AppConstants.challengeDedupeWindowDays,
  }) async {
    try {
      final snap = await _challengesCol(uid)
          .orderBy('generatedAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs
          .map((doc) => doc.data()['title'] as String? ?? '')
          .where((t) => t.isNotEmpty)
          .toList();
    } catch (e) {
      dev.log('fetchRecentChallengeTitles error: $e',
          name: 'ChallengeRepository');
      return const [];
    }
  }

  /// Paginated challenge history, newest first.
  Future<List<ChallengeModel>> fetchChallengeHistory(
    String uid, {
    int limit = AppConstants.challengeHistoryPageSize,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      var query = _challengesCol(uid)
          .orderBy('generatedAt', descending: true)
          .limit(limit);
      if (startAfter != null) query = query.startAfterDocument(startAfter);
      final snap = await query.get();
      return snap.docs
          .map((doc) {
            try {
              return ChallengeModel.fromFirestore(doc);
            } catch (_) {
              return null;
            }
          })
          .whereType<ChallengeModel>()
          .toList();
    } catch (e) {
      dev.log('fetchChallengeHistory error: $e', name: 'ChallengeRepository');
      return const [];
    }
  }

  // ── Completions (home path nodes) ──────────────────────────────────────────

  /// Live stream of recent completions for the home path nodes display.
  Stream<List<CompletionModel>> watchRecentCompletions(
    String uid, {
    int limit = AppConstants.defaultPageSize,
  }) {
    return _firestore
        .watchCollection(
          collection: AppConstants.colCompletions,
          filters: [QueryFilter(field: 'userId', isEqualTo: uid)],
          orderByField: 'completedAt',
          descending: true,
          limit: limit,
        )
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => CompletionModel.fromFirestore(
                  doc as DocumentSnapshot<Map<String, dynamic>>,
                ),
              )
              .toList(),
        );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/app_constants.dart';
import '../core/result.dart';
import '../models/adventure_memory_model.dart';
import '../models/completion_model.dart';

/// One page of a cursor-paginated memory query, plus the cursor needed to
/// fetch the next page.
class MemoryPage {
  const MemoryPage({
    required this.memories,
    required this.lastDoc,
    required this.hasMore,
  });

  final List<AdventureMemoryModel> memories;

  /// The last raw document in this page — pass to [MemoryRepository.fetchNextPage]
  /// as `startAfter` to continue from here. Null when the page was empty.
  final QueryDocumentSnapshot<Map<String, dynamic>>? lastDoc;

  /// True if the page was full (`memories.length == limit`), meaning there
  /// may be more documents after it. A short page always means the end of
  /// the collection has been reached.
  final bool hasMore;

  static MemoryPage fromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
    int limit,
  ) => MemoryPage(
    memories: snap.docs.map(AdventureMemoryModel.fromFirestore).toList(),
    lastDoc: snap.docs.isEmpty ? null : snap.docs.last,
    hasMore: snap.docs.length >= limit,
  );
}

/// The Journal entry (memory) for [completion]: same ID, photo, caption and
/// XP actually granted — exactly what firestore.rules require a memory to
/// mirror. Coordinates are included only when [includeLocation] is true
/// (the user's optional-location setting, audit D-09).
AdventureMemoryModel journalEntryForCompletion(
  CompletionModel completion, {
  required int challengeDay,
  required bool includeLocation,
  String? captionPrompt,
  String? locationName,
  String? weatherCondition,
  String? weatherEmoji,
}) {
  final loc = includeLocation ? completion.location : null;
  return AdventureMemoryModel(
    memoryId: completion.id,
    userId: completion.userId,
    challengeId: completion.challengeId,
    challengeDay: challengeDay,
    challengeTitle: completion.challengeTitle,
    challengeCategory: completion.challengeCategory,
    photoUrl: completion.photoUrl,
    caption: completion.caption,
    captionPrompt: captionPrompt,
    latitude: loc?.latitude,
    longitude: loc?.longitude,
    locationName: loc == null ? null : locationName,
    weatherCondition: loc == null ? null : weatherCondition,
    weatherEmoji: loc == null ? null : weatherEmoji,
    xpEarned: completion.xpAwarded,
    // Client-side AI verification no longer exists (audit D-06), so an entry
    // is either a manual override or honor-system approved — firestore.rules
    // require exactly this mapping.
    verificationMethod: completion.overrideUsed
        ? 'manual_override'
        : 'auto_approved',
    completionDate: completion.completedAt,
    createdAt: completion.completedAt,
  );
}

class MemoryRepository {
  MemoryRepository({FirebaseFirestore? db}) : _dbOverride = db;

  final FirebaseFirestore? _dbOverride;
  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  /// How many of a user's most recent completions [repairMissingEntries]
  /// checks per run.
  static const repairScanLimit = 30;

  // ── Private helpers ───────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _col(String userId) => _db
      .collection(AppConstants.colUsers)
      .doc(userId)
      .collection(AppConstants.colUserMemories);

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Recreates Journal entries missing for the user's most recent
  /// [repairScanLimit] completions (audit D-13) — e.g. completions saved by
  /// older app versions, whose entry was written separately and could fail.
  /// New completions write their entry in the same batch, so they never
  /// need this.
  ///
  /// Retry-safe and idempotent: entries that exist are never touched, a
  /// second run creates nothing, and firestore.rules make entries
  /// create-only, so a concurrent run on another device can't overwrite
  /// one. Never reads or writes XP, streaks or the completion itself.
  /// Returns how many entries were created.
  Future<Result<int>> repairMissingEntries({
    required String userId,
    required bool includeLocation,
  }) => guardAsync(() async {
    final completions = await _db
        .collection(AppConstants.colCompletions)
        .where('userId', isEqualTo: userId)
        .orderBy('completedAt', descending: true)
        .limit(repairScanLimit)
        .get();
    if (completions.docs.isEmpty) return 0;

    final ids = completions.docs.map((d) => d.id).toList();
    final existing = <String>{};
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      final snap = await _col(
        userId,
      ).where(FieldPath.documentId, whereIn: chunk).get();
      existing.addAll(snap.docs.map((d) => d.id));
    }

    var created = 0;
    for (final doc in completions.docs) {
      if (existing.contains(doc.id)) continue;
      final completion = CompletionModel.fromFirestore(doc);
      final entry = journalEntryForCompletion(
        completion,
        challengeDay: await _challengeDay(userId, completion.challengeId),
        includeLocation: includeLocation,
      );
      try {
        await _col(userId).doc(entry.memoryId).set(entry.toFirestore());
        created++;
      } on FirebaseException catch (e) {
        // Created meanwhile (another device or a concurrent run): the
        // rules deny overwriting it, which is exactly what we want.
        if (e.code != 'permission-denied') rethrow;
      }
    }
    return created;
  });

  /// The challenge's day number for the entry's "Day N" badge, or 0 when the
  /// challenge document is gone (the badge is then hidden).
  Future<int> _challengeDay(String userId, String challengeId) async {
    try {
      final snap = await _db
          .collection(AppConstants.colUsers)
          .doc(userId)
          .collection(AppConstants.colUserChallenges)
          .doc(challengeId)
          .get();
      return (snap.data()?['dayNumber'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Updates only the caption of an existing memory.
  Future<Result<void>> updateCaption({
    required String userId,
    required String memoryId,
    required String newCaption,
  }) => guardAsync(
    () => _col(userId).doc(memoryId).update({
      'caption': newCaption.trim(),
      'captionUpdatedAt': FieldValue.serverTimestamp(),
    }),
  );

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Real-time stream of the newest [limit] memories for [userId].
  ///
  /// This is the *first page* only — it stays live so a freshly completed
  /// challenge (or an edited caption) always appears without a manual
  /// refresh. Deeper history is fetched once via [fetchNextPage] instead of
  /// widening this listener, so the realtime subscription never grows
  /// unbounded as a user's history grows.
  Stream<MemoryPage> watchFirstPage(
    String userId, {
    int limit = AppConstants.memoryPageSize,
  }) {
    return _col(userId)
        .orderBy('completionDate', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => MemoryPage.fromSnapshot(snap, limit));
  }

  /// Fetches the next page of memories strictly older than [startAfter],
  /// newest-first. A one-time read (not realtime) — history beyond the
  /// first page doesn't need to update live.
  Future<MemoryPage> fetchNextPage({
    required String userId,
    required QueryDocumentSnapshot<Map<String, dynamic>> startAfter,
    int limit = AppConstants.memoryPageSize,
  }) async {
    final snap = await _col(userId)
        .orderBy('completionDate', descending: true)
        .startAfterDocument(startAfter)
        .limit(limit)
        .get();
    return MemoryPage.fromSnapshot(snap, limit);
  }

  /// Fetches a single memory by ID.
  Future<AdventureMemoryModel?> getMemory({
    required String userId,
    required String memoryId,
  }) async {
    final doc = await _col(userId).doc(memoryId).get();
    if (!doc.exists) return null;
    return AdventureMemoryModel.fromFirestore(doc);
  }
}

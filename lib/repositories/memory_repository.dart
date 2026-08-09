import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/app_constants.dart';
import '../core/result.dart';
import '../models/adventure_memory_model.dart';

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
  ) =>
      MemoryPage(
        memories:
            snap.docs.map(AdventureMemoryModel.fromFirestore).toList(),
        lastDoc: snap.docs.isEmpty ? null : snap.docs.last,
        hasMore: snap.docs.length >= limit,
      );
}

class MemoryRepository {
  const MemoryRepository();

  // ── Private helpers ───────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _col(String userId) =>
      FirebaseFirestore.instance
          .collection(AppConstants.colUsers)
          .doc(userId)
          .collection(AppConstants.colUserMemories);

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Creates a memory document.
  ///
  /// Uses [memory.memoryId] as the document ID so it matches the completion ID.
  /// Silently no-ops if a document with that ID already exists (idempotent).
  Future<Result<void>> createMemory(AdventureMemoryModel memory) =>
      guardAsync(() async {
        final ref = _col(memory.userId).doc(memory.memoryId);
        final existing = await ref.get();
        if (existing.exists) return; // already created — idempotent
        await ref.set(memory.toFirestore());
      });

  /// Updates only the caption of an existing memory.
  Future<Result<void>> updateCaption({
    required String userId,
    required String memoryId,
    required String newCaption,
  }) =>
      guardAsync(() => _col(userId).doc(memoryId).update({
            'caption': newCaption.trim(),
            'captionUpdatedAt': FieldValue.serverTimestamp(),
          }));

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

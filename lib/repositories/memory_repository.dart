import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/app_constants.dart';
import '../core/result.dart';
import '../models/adventure_memory_model.dart';

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

  /// Real-time stream of all memories for [userId], newest first.
  Stream<List<AdventureMemoryModel>> watchMemories(
    String userId, {
    int limit = AppConstants.mapHistoryLimit,
  }) {
    return _col(userId)
        .orderBy('completionDate', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map(AdventureMemoryModel.fromFirestore)
            .toList());
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

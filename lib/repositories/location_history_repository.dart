import 'dart:async';
import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';

/// The optional location field on a completion document.
const completionLocationKeys = ['location'];

/// The optional location-derived fields on a Journal entry (memory) —
/// firestore.rules' `locationDerivedKeys()`.
const journalLocationKeys = [
  'latitude',
  'longitude',
  'locationName',
  'weatherCondition',
  'weatherEmoji',
];

enum LocationRemovalStatus {
  /// Every saved location was removed and a final check found none left.
  complete,

  /// The device couldn't reach Firestore; some locations may remain.
  offline,

  /// A read or write failed; some locations may remain.
  failed,

  /// Locations kept reappearing (e.g. new adventures saved on another
  /// device while the setting is on); some may remain.
  incomplete,
}

@immutable
class LocationRemovalResult {
  const LocationRemovalResult(
    this.status, {
    required this.completionsCleared,
    required this.entriesCleared,
  });

  final LocationRemovalStatus status;

  /// Documents changed by this run (not counting ones already clean).
  final int completionsCleared;
  final int entriesCleared;

  bool get isComplete => status == LocationRemovalStatus.complete;
}

/// "Remove saved locations" (audit D-09, Phase 5): deletes the optional
/// location fields from the signed-in user's own completions and Journal
/// entries, and nothing else.
///
/// - **Server-enforced:** firestore.rules only accept an update that
///   deletes these fields from the caller's own documents — no value can be
///   set, and no other field (XP, photo, dates, caption…) can change.
/// - **Bounded:** documents are read in pages of [pageSize] and each page's
///   updates go in one batch (well under Firestore's 500-write limit).
/// - **Retry-safe:** only documents that still have a location are
///   updated, so a repeated or resumed run changes nothing it already did,
///   and each batch is atomic.
/// - **Verified:** it runs until a full pass finds nothing left to remove
///   (at most [maxPasses] passes), and reports [LocationRemovalStatus.
///   complete] only then.
/// - **Online only:** reads come from the server, never the offline cache,
///   so the result reflects what is actually stored.
///
/// Completions are cleared before Journal entries so a Journal repair
/// running at the same time can't copy a location back from a completion.
/// Never logs coordinates or place names — only counts.
class LocationHistoryRepository {
  LocationHistoryRepository({
    FirebaseFirestore? db,
    this.pageSize = 200,
    this.maxPasses = 3,
    @visibleForTesting Future<void> Function(WriteBatch batch)? commitBatch,
    @visibleForTesting GetOptions? getOptions,
  }) : assert(pageSize > 0 && pageSize <= 450),
       _dbOverride = db,
       _commit = commitBatch ?? ((b) => b.commit()),
       _getOptions = getOptions ?? const GetOptions(source: Source.server);

  final FirebaseFirestore? _dbOverride;
  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;
  final int pageSize;
  final int maxPasses;
  final Future<void> Function(WriteBatch batch) _commit;
  final GetOptions _getOptions;

  static const _timeout = Duration(seconds: AppConstants.networkTimeoutSeconds);

  Query<Map<String, dynamic>> _completions(String userId) => _db
      .collection(AppConstants.colCompletions)
      .where('userId', isEqualTo: userId);

  Query<Map<String, dynamic>> _entries(String userId) => _db
      .collection(AppConstants.colUsers)
      .doc(userId)
      .collection(AppConstants.colUserMemories);

  /// Never throws; the result says whether every location is gone.
  Future<LocationRemovalResult> removeSavedLocations(String userId) async {
    // Counted per committed batch, so a failure partway still reports
    // exactly what was removed.
    var completions = 0;
    var entries = 0;
    LocationRemovalResult result(LocationRemovalStatus s) =>
        LocationRemovalResult(
          s,
          completionsCleared: completions,
          entriesCleared: entries,
        );
    try {
      for (var pass = 0; pass < maxPasses; pass++) {
        final c = await _clear(
          _completions(userId),
          completionLocationKeys,
          (n) => completions += n,
        );
        final e = await _clear(
          _entries(userId),
          journalLocationKeys,
          (n) => entries += n,
        );
        if (c == 0 && e == 0) {
          dev.log(
            'Saved locations removed: $completions completions, '
            '$entries Journal entries',
            name: 'LocationHistory',
          );
          return result(LocationRemovalStatus.complete);
        }
      }
      return result(LocationRemovalStatus.incomplete);
    } on TimeoutException {
      return result(LocationRemovalStatus.offline);
    } on FirebaseException catch (e) {
      dev.log(
        'Removing saved locations stopped (${e.code}) after $completions '
        'completions, $entries Journal entries',
        name: 'LocationHistory',
      );
      return result(
        e.code == 'unavailable'
            ? LocationRemovalStatus.offline
            : LocationRemovalStatus.failed,
      );
    } catch (_) {
      return result(LocationRemovalStatus.failed);
    }
  }

  /// Deletes [keys] from every document of [base] that has any of them,
  /// reporting each committed batch's size to [onCommitted]. Returns how
  /// many documents were changed.
  Future<int> _clear(
    Query<Map<String, dynamic>> base,
    List<String> keys,
    void Function(int) onCommitted,
  ) async {
    final ordered = base.orderBy(FieldPath.documentId);
    DocumentSnapshot<Map<String, dynamic>>? last;
    var cleared = 0;
    for (;;) {
      final page = (last == null ? ordered : ordered.startAfterDocument(last))
          .limit(pageSize);
      final snap = await page.get(_getOptions).timeout(_timeout);
      final batch = _db.batch();
      var updates = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final present = keys.where(data.containsKey).toList();
        if (present.isEmpty) continue;
        batch.update(doc.reference, {
          for (final k in present) k: FieldValue.delete(),
        });
        updates++;
      }
      if (updates > 0) {
        await _commit(batch).timeout(_timeout);
        cleared += updates;
        onCommitted(updates);
      }
      if (snap.docs.length < pageSize) return cleared;
      last = snap.docs.last;
    }
  }
}

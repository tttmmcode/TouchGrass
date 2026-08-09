import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/adventure_memory_model.dart';
import '../repositories/memory_repository.dart';
import 'auth_providers.dart';

// ── Repository ────────────────────────────────────────────────────────────────

final memoryRepositoryProvider = Provider<MemoryRepository>(
  (_) => const MemoryRepository(),
);

// ── Paginated memory list ─────────────────────────────────────────────────────

/// State for [MemoriesController] — backs both the map markers and the
/// adventure journal so there's a single source of truth for "how much of
/// this user's history is currently loaded."
@immutable
class MemoriesState {
  const MemoriesState({
    this.memories = const [],
    this.initialLoading = true,
    this.loadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<AdventureMemoryModel> memories;
  final bool initialLoading;
  final bool loadingMore;
  final bool hasMore;
  final Object? error;

  MemoriesState copyWith({
    List<AdventureMemoryModel>? memories,
    bool? initialLoading,
    bool? loadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) =>
      MemoriesState(
        memories: memories ?? this.memories,
        initialLoading: initialLoading ?? this.initialLoading,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Merges two already-sorted (newest-first), possibly-overlapping memory
/// lists into one deduplicated, order-preserving list — [newer] entries win
/// on ID conflicts (e.g. a live page-1 update with an edited caption), and
/// [older] entries that aren't already present are appended after, keeping
/// the combined list's newest-first order intact. Extracted from
/// [MemoriesController] so pagination's core correctness property — no
/// duplicate memories, no dropped memories, no reordering — is directly
/// unit-testable without a Firestore fake.
@visibleForTesting
List<AdventureMemoryModel> mergeMemoryPages({
  required List<AdventureMemoryModel> newer,
  required List<AdventureMemoryModel> older,
}) {
  final merged = <String, AdventureMemoryModel>{
    for (final m in newer) m.memoryId: m,
  };
  for (final m in older) {
    merged.putIfAbsent(m.memoryId, () => m);
  }
  return merged.values.toList();
}

/// Loads a user's adventure memories newest-first with cursor pagination.
///
/// The first [AppConstants.memoryPageSize] memories stay live via a Firestore
/// snapshot listener (so a just-completed challenge or an edited caption
/// appears immediately); [loadMore] fetches older pages with one-time,
/// cursor-based queries so history never re-downloads and never needs a
/// single unbounded query. See [MemoryRepository.watchFirstPage] /
/// [MemoryRepository.fetchNextPage].
class MemoriesController extends StateNotifier<MemoriesState> {
  MemoriesController(this._repo, this._userId) : super(const MemoriesState()) {
    if (_userId == null) {
      state = state.copyWith(initialLoading: false, hasMore: false);
      return;
    }
    _subscribeFirstPage();
  }

  final MemoryRepository _repo;
  final String? _userId;

  StreamSubscription<MemoryPage>? _sub;
  QueryDocumentSnapshot<Map<String, dynamic>>? _cursor;

  /// Once true, the first-page listener stops driving [_cursor]/[hasMore] —
  /// ownership passes to [loadMore] so a live update to page 1 can never
  /// silently rewind pagination and re-serve already-loaded pages.
  bool _paginatedBeyondFirstPage = false;

  void _subscribeFirstPage() {
    _sub = _repo.watchFirstPage(_userId!).listen(
          _onFirstPage,
          onError: (Object e) =>
              state = state.copyWith(initialLoading: false, error: e),
        );
  }

  void _onFirstPage(MemoryPage page) {
    if (!_paginatedBeyondFirstPage) {
      _cursor = page.lastDoc;
    }
    state = state.copyWith(
      // Fresher page-1 items win on conflict (e.g. an edited caption).
      memories: mergeMemoryPages(newer: page.memories, older: state.memories),
      initialLoading: false,
      hasMore: _paginatedBeyondFirstPage ? state.hasMore : page.hasMore,
      clearError: true,
    );
  }

  /// Loads the next page of older memories. No-ops if already loading, if
  /// there's nothing more, or if the first page hasn't resolved yet.
  Future<void> loadMore() async {
    if (_userId == null || state.loadingMore || !state.hasMore) return;
    final cursor = _cursor;
    if (cursor == null) return;

    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final page = await _repo.fetchNextPage(userId: _userId, startAfter: cursor);
      _paginatedBeyondFirstPage = true;
      _cursor = page.lastDoc ?? _cursor;
      state = state.copyWith(
        // Existing (newer) items win here too — a stale re-fetch of an
        // already-loaded page can never duplicate or reorder them.
        memories: mergeMemoryPages(newer: state.memories, older: page.memories),
        loadingMore: false,
        hasMore: page.hasMore,
      );
    } catch (e) {
      state = state.copyWith(loadingMore: false, error: e);
    }
  }

  /// Retries after a failure — resumes pagination if the failure happened
  /// mid-scroll, or re-subscribes from scratch if the initial load failed.
  Future<void> retry() async {
    if (_userId == null) return;
    if (state.memories.isNotEmpty || _paginatedBeyondFirstPage) {
      await loadMore();
      return;
    }
    state = const MemoriesState();
    await _sub?.cancel();
    _subscribeFirstPage();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final memoriesControllerProvider =
    StateNotifierProvider.autoDispose<MemoriesController, MemoriesState>(
        (ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  final repo = ref.watch(memoryRepositoryProvider);
  return MemoriesController(repo, uid);
});

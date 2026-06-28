import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/adventure_memory_model.dart';
import '../repositories/memory_repository.dart';
import 'auth_providers.dart';

// ── Repository ────────────────────────────────────────────────────────────────

final memoryRepositoryProvider = Provider<MemoryRepository>(
  (_) => const MemoryRepository(),
);

// ── Real-time memory stream ───────────────────────────────────────────────────

/// Real-time list of [AdventureMemoryModel] for the signed-in user.
///
/// Ordered newest-first. Used by the map markers and the journal timeline.
final memoriesProvider = StreamProvider.autoDispose<List<AdventureMemoryModel>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(memoryRepositoryProvider).watchMemories(uid);
});

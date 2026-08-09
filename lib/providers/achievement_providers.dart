import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/achievement_model.dart';
import '../services/achievement_service.dart';
import 'user_providers.dart';

// ── Service ───────────────────────────────────────────────────────────────────

final achievementServiceProvider = Provider<AchievementService>((ref) {
  return const AchievementService();
});

// ── Primary provider — used by all screens ────────────────────────────────────

/// Full list of [AchievementModel] for the current user.
/// Earned achievements are sorted first, locked achievements follow.
final achievementModelsProvider = Provider<List<AchievementModel>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return [];
  return ref.watch(achievementServiceProvider).buildModels(user);
});

// ── Derived counts ────────────────────────────────────────────────────────────

/// How many achievements the current user has earned.
final earnedAchievementCountProvider = Provider<int>((ref) {
  return ref.watch(achievementModelsProvider).where((m) => m.isUnlocked).length;
});

import '../core/result.dart';
import '../models/completion_reward.dart';
import '../models/progression_model.dart';
import '../models/user_model.dart';
import '../repositories/user_repository.dart';

/// Single entry point for all progression mutations.
///
/// No screen or widget should call XP / streak / level calculations directly.
/// All updates flow through here so the logic stays in one place.
class ProgressionService {
  const ProgressionService({required UserRepository userRepository})
      : _repository = userRepository;

  final UserRepository _repository;

  // ── Award rewards after a challenge completion ─────────────────────────────

  /// Awards XP, updates streak, handles Rainy Days, persists everything.
  ///
  /// [xpAmount] is the challenge's declared XP reward (25 / 50 / 100).
  /// Returns a [CompletionReward] describing all changes made.
  Future<Result<CompletionReward>> awardCompletion({
    required String uid,
    required int xpAmount,
  }) =>
      _repository.awardCompletionRewards(uid: uid, xpAmount: xpAmount);

  // ── Progression view model ─────────────────────────────────────────────────

  /// Derives a [ProgressionModel] from a live [UserModel].
  ///
  /// Call this anywhere you need progression data — it computes instantly
  /// from the already-loaded user document, no extra Firestore reads.
  ProgressionModel progressionFor(UserModel user) =>
      ProgressionModel.fromUser(user);
}

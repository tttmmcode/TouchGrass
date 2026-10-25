import '../models/achievement_definition.dart';
import '../models/achievement_model.dart';
import '../models/user_model.dart';

/// Centralises all achievement progress calculation.
///
/// No screen or widget should call [AchievementDefinition] progress helpers
/// directly — go through this service (or a Riverpod provider backed by it).
class AchievementService {
  const AchievementService();

  /// Builds the full [AchievementModel] list for [user].
  ///
  /// Earned achievements are sorted first; locked achievements follow.
  List<AchievementModel> buildModels(UserModel user) {
    final earnedSet = user.achievements.toSet();
    final timestamps = user.achievementTimestamps;

    final List<AchievementModel> all = AchievementDefinition.catalog
        .map<AchievementModel>((def) {
          final isUnlocked = earnedSet.contains(def.id);
          return AchievementModel(
            def: def,
            isUnlocked: isUnlocked,
            unlockedAt: timestamps[def.id],
            progressFraction: isUnlocked
                ? 1.0
                : def.progressValue(
                    xp: user.xp,
                    streak: user.streak,
                    totalCompletions: user.totalCompletions,
                    level: user.level,
                  ),
            progressLabel: def.progressLabel(
              xp: user.xp,
              streak: user.streak,
              totalCompletions: user.totalCompletions,
              level: user.level,
            ),
          );
        })
        .toList();

    return [
      ...all.where((m) => m.isUnlocked),
      ...all.where((m) => !m.isUnlocked),
    ];
  }
}

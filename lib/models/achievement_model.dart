import 'package:flutter/foundation.dart';

import 'achievement_definition.dart';

/// Runtime view of an achievement that combines its static [AchievementDefinition]
/// with live user state (unlocked, progress, timestamp).
///
/// All screens must consume [AchievementModel] through [achievementModelsProvider]
/// rather than calling [AchievementDefinition] progress helpers directly.
@immutable
class AchievementModel {
  const AchievementModel({
    required this.def,
    required this.isUnlocked,
    required this.progressFraction,
    required this.progressLabel,
    this.unlockedAt,
  });

  final AchievementDefinition def;

  /// Whether the current user has earned this achievement.
  final bool isUnlocked;

  /// Progress towards unlock: 0.0–1.0 (clamped; 1.0 when unlocked).
  final double progressFraction;

  /// Human-readable label e.g. "3 / 7 days".
  final String progressLabel;

  /// UTC timestamp of when this achievement was unlocked, or null.
  final DateTime? unlockedAt;

  // ── Convenience pass-throughs ─────────────────────────────────────────────

  String get id => def.id;
  String get emoji => def.emoji;
  String get title => def.title;
  String get description => def.description;

  AchievementRarity get rarity => def.rarity;
  AchievementCategory get category => def.category;
  int get xpReward => def.xpReward;

  /// Percentage complete, 0–100.
  double get completionPercentage => (progressFraction * 100).clamp(0.0, 100.0);
}

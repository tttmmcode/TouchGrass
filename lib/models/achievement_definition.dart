import 'package:flutter/material.dart';

// ── Rarity ────────────────────────────────────────────────────────────────────

enum AchievementRarity { common, rare, epic, legendary, mythic }

extension AchievementRarityX on AchievementRarity {
  String get label => switch (this) {
        AchievementRarity.common    => 'Common',
        AchievementRarity.rare      => 'Rare',
        AchievementRarity.epic      => 'Epic',
        AchievementRarity.legendary => 'Legendary',
        AchievementRarity.mythic    => 'Mythic',
      };

  Color get color => switch (this) {
        AchievementRarity.common    => const Color(0xFF9BA8A3),
        AchievementRarity.rare      => const Color(0xFF4EA8DE),
        AchievementRarity.epic      => const Color(0xFF9B59B6),
        AchievementRarity.legendary => const Color(0xFFFFB703),
        AchievementRarity.mythic    => const Color(0xFFFC4E6F),
      };
}

// ── Category ──────────────────────────────────────────────────────────────────

enum AchievementCategory { explorer, consistency, progression, milestones }

extension AchievementCategoryX on AchievementCategory {
  String get label => switch (this) {
        AchievementCategory.explorer    => 'Explorer',
        AchievementCategory.consistency => 'Consistency',
        AchievementCategory.progression => 'Progression',
        AchievementCategory.milestones  => 'Milestones',
      };

  String get emoji => switch (this) {
        AchievementCategory.explorer    => '🗺️',
        AchievementCategory.consistency => '🔥',
        AchievementCategory.progression => '⭐',
        AchievementCategory.milestones  => '🏔️',
      };
}

// ── Definition ────────────────────────────────────────────────────────────────

@immutable
class AchievementDefinition {
  const AchievementDefinition._({
    required this.id,
    required this.emoji,
    required this.title,
    required this.description,
    required this.rarity,
    required this.category,
    required this.xpReward,
  });

  final String id;
  final String emoji;
  final String title;
  final String description;
  final AchievementRarity rarity;
  final AchievementCategory category;
  final int xpReward;

  // ── Catalog ───────────────────────────────────────────────────────────────

  static const List<AchievementDefinition> catalog = [
    AchievementDefinition._(
      id: 'first_touch',
      emoji: '🌿',
      title: 'First Step',
      description: 'Complete your first outdoor challenge.',
      rarity: AchievementRarity.common,
      category: AchievementCategory.explorer,
      xpReward: 25,
    ),
    AchievementDefinition._(
      id: 'challenges_5',
      emoji: '🎯',
      title: 'Getting Started',
      description: 'Complete 5 challenges.',
      rarity: AchievementRarity.common,
      category: AchievementCategory.explorer,
      xpReward: 50,
    ),
    AchievementDefinition._(
      id: 'challenges_10',
      emoji: '🌲',
      title: 'Ten Times Bold',
      description: 'Complete 10 challenges.',
      rarity: AchievementRarity.rare,
      category: AchievementCategory.explorer,
      xpReward: 100,
    ),
    AchievementDefinition._(
      id: 'challenges_25',
      emoji: '🏔️',
      title: 'Dedicated Explorer',
      description: 'Complete 25 challenges.',
      rarity: AchievementRarity.rare,
      category: AchievementCategory.explorer,
      xpReward: 150,
    ),
    AchievementDefinition._(
      id: 'challenges_50',
      emoji: '🗺️',
      title: 'Trail Blazer',
      description: 'Complete 50 challenges.',
      rarity: AchievementRarity.epic,
      category: AchievementCategory.explorer,
      xpReward: 200,
    ),
    AchievementDefinition._(
      id: 'challenges_100',
      emoji: '🗺️',
      title: 'Master Explorer',
      description: 'Complete 100 challenges.',
      rarity: AchievementRarity.legendary,
      category: AchievementCategory.explorer,
      xpReward: 500,
    ),
    AchievementDefinition._(
      id: 'streak_3',
      emoji: '🔥',
      title: 'On a Roll',
      description: 'Maintain a 3-day outdoor streak.',
      rarity: AchievementRarity.common,
      category: AchievementCategory.consistency,
      xpReward: 50,
    ),
    AchievementDefinition._(
      id: 'streak_7',
      emoji: '🔥',
      title: 'Week Warrior',
      description: 'Maintain a 7-day outdoor streak.',
      rarity: AchievementRarity.rare,
      category: AchievementCategory.consistency,
      xpReward: 100,
    ),
    AchievementDefinition._(
      id: 'streak_30',
      emoji: '🔥',
      title: 'Nature Devotee',
      description: 'Maintain a 30-day outdoor streak.',
      rarity: AchievementRarity.epic,
      category: AchievementCategory.consistency,
      xpReward: 300,
    ),
    AchievementDefinition._(
      id: 'streak_100',
      emoji: '🔥',
      title: '100 Day Streak',
      description: 'Maintain a 100-day outdoor streak.',
      rarity: AchievementRarity.mythic,
      category: AchievementCategory.consistency,
      xpReward: 1000,
    ),
    AchievementDefinition._(
      id: 'xp_100',
      emoji: '⭐',
      title: 'Greenhorn',
      description: 'Earn 100 total XP.',
      rarity: AchievementRarity.common,
      category: AchievementCategory.progression,
      xpReward: 25,
    ),
    AchievementDefinition._(
      id: 'xp_500',
      emoji: '🌟',
      title: 'Explorer',
      description: 'Earn 500 total XP.',
      rarity: AchievementRarity.rare,
      category: AchievementCategory.progression,
      xpReward: 75,
    ),
    AchievementDefinition._(
      id: 'xp_1000',
      emoji: '✨',
      title: 'Adventurer',
      description: 'Earn 1,000 total XP.',
      rarity: AchievementRarity.epic,
      category: AchievementCategory.progression,
      xpReward: 150,
    ),
    AchievementDefinition._(
      id: 'xp_2500',
      emoji: '🌿',
      title: 'Nature Explorer',
      description: 'Earn 2,500 total XP.',
      rarity: AchievementRarity.legendary,
      category: AchievementCategory.progression,
      xpReward: 400,
    ),
    AchievementDefinition._(
      id: 'level_5',
      emoji: '🏅',
      title: 'Leveling Up',
      description: 'Reach Level 5.',
      rarity: AchievementRarity.rare,
      category: AchievementCategory.milestones,
      xpReward: 100,
    ),
    AchievementDefinition._(
      id: 'level_10',
      emoji: '🥈',
      title: 'Seasoned Hiker',
      description: 'Reach Level 10.',
      rarity: AchievementRarity.epic,
      category: AchievementCategory.milestones,
      xpReward: 250,
    ),
  ];

  // ── Progress helpers ──────────────────────────────────────────────────────

  /// Fraction 0.0–1.0 towards unlocking this achievement given current stats.
  double progressValue({
    required int xp,
    required int streak,
    required int totalCompletions,
    required int level,
  }) {
    final double v = switch (id) {
      'first_touch'    => totalCompletions / 1,
      'challenges_5'   => totalCompletions / 5,
      'challenges_10'  => totalCompletions / 10,
      'challenges_25'  => totalCompletions / 25,
      'challenges_50'  => totalCompletions / 50,
      'challenges_100' => totalCompletions / 100,
      'streak_3'       => streak / 3,
      'streak_7'       => streak / 7,
      'streak_30'      => streak / 30,
      'streak_100'     => streak / 100,
      'xp_100'         => xp / 100,
      'xp_500'         => xp / 500,
      'xp_1000'        => xp / 1000,
      'xp_2500'        => xp / 2500,
      'level_5'        => level / 5,
      'level_10'       => level / 10,
      _                => 0.0,
    };
    return v.clamp(0.0, 1.0);
  }

  /// Human-readable progress label, e.g. "3 / 7 days".
  String progressLabel({
    required int xp,
    required int streak,
    required int totalCompletions,
    required int level,
  }) {
    return switch (id) {
      'first_touch'    => '$totalCompletions / 1 challenge',
      'challenges_5'   => '$totalCompletions / 5 challenges',
      'challenges_10'  => '$totalCompletions / 10 challenges',
      'challenges_25'  => '$totalCompletions / 25 challenges',
      'challenges_50'  => '$totalCompletions / 50 challenges',
      'challenges_100' => '$totalCompletions / 100 challenges',
      'streak_3'       => '$streak / 3 days',
      'streak_7'       => '$streak / 7 days',
      'streak_30'      => '$streak / 30 days',
      'streak_100'     => '$streak / 100 days',
      'xp_100'         => '$xp / 100 XP',
      'xp_500'         => '$xp / 500 XP',
      'xp_1000'        => '$xp / 1,000 XP',
      'xp_2500'        => '$xp / 2,500 XP',
      'level_5'        => 'Level $level / 5',
      'level_10'       => 'Level $level / 10',
      _                => '',
    };
  }

  // ── Unlock logic ──────────────────────────────────────────────────────────

  /// Returns IDs from [catalog] that should be newly unlocked given the
  /// user's post-completion state. Already-earned IDs are excluded.
  static List<String> computeNewlyEarned({
    required Set<String> alreadyEarned,
    required int newXp,
    required int newStreak,
    required int newLevel,
    required int newTotalCompletions,
  }) {
    final result = <String>[];

    void check(String id, bool condition) {
      if (!alreadyEarned.contains(id) && condition) result.add(id);
    }

    check('first_touch',    newTotalCompletions >= 1);
    check('challenges_5',   newTotalCompletions >= 5);
    check('challenges_10',  newTotalCompletions >= 10);
    check('challenges_25',  newTotalCompletions >= 25);
    check('challenges_50',  newTotalCompletions >= 50);
    check('streak_3',       newStreak >= 3);
    check('streak_7',       newStreak >= 7);
    check('streak_30',      newStreak >= 30);
    check('xp_100',         newXp >= 100);
    check('xp_500',         newXp >= 500);
    check('xp_1000',        newXp >= 1000);
    check('level_5',        newLevel >= 5);
    check('level_10',       newLevel >= 10);
    check('xp_2500',        newXp >= 2500);
    check('streak_100',     newStreak >= 100);
    check('challenges_100', newTotalCompletions >= 100);

    return result;
  }
}

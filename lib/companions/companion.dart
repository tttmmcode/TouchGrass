import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

// ── Types ─────────────────────────────────────────────────────────────────────

enum CompanionType { leafy, pebble, sunny, sprout }

enum CompanionMood {
  idle,       // gentle bob + periodic blink
  wave,       // arm waves hello
  bounce,     // springy up-down
  cheer,      // arms up + jump + big smile
  encourage,  // slight lean forward, warm expression
}

// ── Metadata ──────────────────────────────────────────────────────────────────

extension CompanionTypeX on CompanionType {
  String get displayName => switch (this) {
        CompanionType.leafy => 'Leafy',
        CompanionType.pebble => 'Pebble',
        CompanionType.sunny => 'Sunny',
        CompanionType.sprout => 'Sprout',
      };

  String get tagline => switch (this) {
        CompanionType.leafy => 'Your adventurous leaf pal',
        CompanionType.pebble => 'Cool, calm & always there',
        CompanionType.sunny => 'Bright as a summer day',
        CompanionType.sprout => 'A curious nature spirit',
      };

  Color get primaryColor => switch (this) {
        CompanionType.leafy => AppColors.grassGreen,
        CompanionType.pebble => const Color(0xFF9BA8A3),
        CompanionType.sunny => const Color(0xFFFFB703),
        CompanionType.sprout => AppColors.grassGreenLight,
      };

  Color get accentColor => switch (this) {
        CompanionType.leafy => AppColors.forestGreenDark,
        CompanionType.pebble => const Color(0xFF5F6B67),
        CompanionType.sunny => const Color(0xFFFF6B35),
        CompanionType.sprout => AppColors.forestGreen,
      };

  // ── Message pools ─────────────────────────────────────────────────────────

  List<String> get completionMessages => switch (this) {
        CompanionType.leafy => [
            'You did it! 🌿',
            'Nature lover right here!',
            'The outdoors loves you back!',
            'You crushed it! 💚',
            "That's the spirit!",
          ],
        CompanionType.pebble => [
            'Solid work.',
            'I knew you had it in you.',
            'Steady as a rock. ✊',
            'Well done, explorer.',
            'Nice and steady!',
          ],
        CompanionType.sunny => [
            "You're shining bright! ☀️",
            'Brilliant! Absolutely brilliant!',
            'The sun is proud of you!',
            'Golden work! ⭐',
            'You light up the world!',
          ],
        CompanionType.sprout => [
            "You're growing! 🌱",
            'Every step counts!',
            'Look at you go!',
            'Another day, another leaf!',
            'Keep sprouting! 🌿',
          ],
      };

  List<String> get levelUpMessages => switch (this) {
        CompanionType.leafy => [
            'LEVEL UP! Unstoppable! 🚀',
            'New level, same awesome you!',
            'Growing stronger every day! 🌿',
          ],
        CompanionType.pebble => [
            'Level up. Mountains tremble.',
            'Another level. Very impressive.',
            "You've leveled up. I'm proud.",
          ],
        CompanionType.sunny => [
            "LEVEL UP! You're BLAZING! ☀️",
            'Another level brighter! ⭐',
            "You're golden, literally!",
          ],
        CompanionType.sprout => [
            "Level up! You're really growing! 🌱",
            'Look how far you have come!',
            'New level unlocked! 🌿',
          ],
      };

  List<String> get encouragementMessages => switch (this) {
        CompanionType.leafy => [
            "Today's the day! 🌿",
            "You've got this, explorer!",
            'The trail awaits!',
            'Ready for an adventure?',
          ],
        CompanionType.pebble => [
            'Take it one step at a time.',
            'You can do this.',
            'Calm and steady wins.',
            'I believe in you.',
          ],
        CompanionType.sunny => [
            'Rise and shine! ☀️',
            'The sun is waiting for you!',
            'Go out there and glow!',
            'Another bright day ahead!',
          ],
        CompanionType.sprout => [
            'Every adventure starts with one step!',
            'The world is full of wonders! 🌱',
            'Your journey continues!',
            'Grow a little every day!',
          ],
      };

  List<String> get streakMessages => switch (this) {
        CompanionType.leafy => [
            '🔥 Hot streak! Keep it going!',
            "On fire! Don't stop now!",
            'Streak power! 🌿🔥',
          ],
        CompanionType.pebble => [
            'Consistent. That is the way.',
            'Unbreakable. Like a rock.',
            'Day after day. Respect.',
          ],
        CompanionType.sunny => [
            '☀️ Streak star! You are glowing!',
            'Shining every day! ⭐',
            'Golden streak! Keep shining!',
          ],
        CompanionType.sprout => [
            'Growing every day! 🌱',
            'Your streak is sprouting!',
            'Consistent grower! 🌿',
          ],
      };

  List<String> get onboardingMessages => switch (this) {
        CompanionType.leafy => [
            "Hi! I'm Leafy! 👋",
            "Let's go exploring! 🌿",
            'Adventure awaits us!',
          ],
        CompanionType.pebble => [
            "Hey there. I'm Pebble.",
            'Take it one step at a time.',
            "We've got this together.",
          ],
        CompanionType.sunny => [
            'Hello, sunshine! ☀️',
            'Today is a beautiful day!',
            "Let's make it golden! ⭐",
          ],
        CompanionType.sprout => [
            "Hi! I'm Sprout! 🌱",
            "We'll grow together!",
            'New adventures await! 🌿',
          ],
      };

  List<String> get achievementMessages => switch (this) {
        CompanionType.leafy => [
            'Achievement unlocked! 🏅',
            'You are on a roll, explorer!',
            'Badge earned — wear it proud! 🌿',
          ],
        CompanionType.pebble => [
            'Achievement acquired.',
            'You earned that. Well done.',
            'Solid milestone reached. 🏅',
          ],
        CompanionType.sunny => [
            'Achievement shining bright! ⭐',
            'You unlocked something golden!',
            'A new badge for a star! 🌟',
          ],
        CompanionType.sprout => [
            'New achievement! You are blooming! 🌸',
            'Look what you unlocked! 🌱',
            'Achievement get! Keep growing!',
          ],
      };

  List<String> get streakMilestoneMessages => switch (this) {
        CompanionType.leafy => [
            '🔥 Streak milestone! Incredible!',
            'Days in a row — legendary! 🌿',
            'Your streak is unstoppable! 🔥',
          ],
        CompanionType.pebble => [
            'Milestone streak. Very impressive.',
            'Consistent. Day after day.',
            'A true streak warrior.',
          ],
        CompanionType.sunny => [
            '☀️ Streak milestone! You are glowing!',
            'Shining every single day! ⭐',
            'Golden streak achieved! 🌟',
          ],
        CompanionType.sprout => [
            'Streak milestone! Keep sprouting! 🌱',
            'Days in a row — you are growing!',
            'Streak power! 🌿🔥',
          ],
      };
}

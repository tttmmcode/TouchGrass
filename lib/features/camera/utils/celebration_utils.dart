// Pure, testable logic backing the post-completion celebration screen
// (`_SuccessView` in camera_screen.dart). Extracted so confetti-tier and
// streak-copy decisions can be unit tested without instantiating widgets.

/// Relative intensity of the celebration (confetti volume/duration, not XP).
/// Ordinary completions stay subtle; rarer events escalate — mirrors the
/// achievement rarity ladder so the celebration always matches how
/// significant the moment actually is.
enum CelebrationTier { subtle, standard, strong, epic }

/// IDs whose unlock is a "major milestone" — reserved for legendary/mythic
/// achievements in [AchievementDefinition.catalog] (100-challenge / 100-day
/// streak / 2500 XP tier). Kept here as a literal set (not a rarity lookup)
/// so this file has no dependency on the achievement model.
const Set<String> majorMilestoneAchievementIds = {
  'challenges_100',
  'streak_100',
  'xp_2500',
};

/// Picks the celebration's confetti tier from what actually happened during
/// this completion. Never escalates for things that didn't happen — an
/// ordinary completion with no achievement/level-up always stays subtle.
CelebrationTier resolveCelebrationTier({
  required bool leveledUp,
  required List<String> newAchievements,
  required bool leagueChanged,
}) {
  final hasMajorMilestone =
      newAchievements.any(majorMilestoneAchievementIds.contains);
  if (hasMajorMilestone) return CelebrationTier.epic;
  if (leveledUp || leagueChanged) return CelebrationTier.strong;
  if (newAchievements.isNotEmpty) return CelebrationTier.standard;
  return CelebrationTier.subtle;
}

/// Confetti particle count for [tier]. Kept as a pure lookup so the "ordinary
/// completions get a subtle burst" rule (Part C11) can't silently drift into
/// "same big burst as everything else" as the widget evolves.
int confettiParticleCountFor(CelebrationTier tier) => switch (tier) {
      CelebrationTier.subtle => 14,
      CelebrationTier.standard => 26,
      CelebrationTier.strong => 42,
      CelebrationTier.epic => 60,
    };

/// Confetti burst duration for [tier], in seconds.
int confettiDurationSecondsFor(CelebrationTier tier) => switch (tier) {
      CelebrationTier.subtle => 2,
      CelebrationTier.standard => 3,
      CelebrationTier.strong => 4,
      CelebrationTier.epic => 6,
    };

/// The streak line shown on the celebration screen. Never claims the streak
/// "extended" unless it actually grew versus the last known value, and
/// never claims a Rainy Day protected it unless one was actually consumed —
/// both are read from the real [CompletionReward]/[CameraSuccess] fields,
/// never inferred.
String streakCelebrationLabel({
  required int newStreak,
  required bool streakIncreased,
  required bool rainyDayConsumed,
}) {
  if (rainyDayConsumed) return 'Rainy Day protected your streak';
  if (streakIncreased) return 'Streak extended!';
  return '$newStreak day streak';
}

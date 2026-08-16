import 'package:flutter/material.dart';

/// All color constants for the TouchGrass design system.
///
/// Never reference raw hex values outside this file — always use named tokens.
abstract final class AppColors {
  // ── Primary: Forest Green ─────────────────────────────────────────────────
  static const Color forestGreen = Color(0xFF2E7D32);
  static const Color forestGreenLight = Color(0xFF4CAF50);
  static const Color forestGreenDark = Color(0xFF1B5E20);

  // ── Secondary: Grass Green ────────────────────────────────────────────────
  static const Color grassGreen = Color(0xFF52B788);
  static const Color grassGreenLight = Color(0xFF74C69D);

  // ── Accents ───────────────────────────────────────────────────────────────
  static const Color skyBlue = Color(0xFF4EA8DE);
  static const Color skyBlueLight = Color(0xFF90C2E7);

  /// Golden Yellow — the app's secondary brand accent (CTAs, highlights,
  /// streak/gold gradients). Distinct from [xpGold] and [warning], which
  /// used to be aliased to this same value.
  static const Color warmYellow = Color(0xFFF9A825);
  static const Color achievementGold = Color(0xFFFFB703);

  /// Bright Gold used specifically for XP counters/badges — visually
  /// distinct from [achievementGold] (achievement rarity/stars) even
  /// though both sit in the same warm-gold family.
  static const Color xpGold = Color(0xFFFFD54F);
  static const Color streakOrange = Color(0xFFFF6B35);

  // ── Semantic ──────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF43A047);
  static const Color error = Color(0xFFE53935);
  static const Color warning = Color(0xFFFB8C00);
  static const Color info = Color(0xFF1E88E5);

  // ── Overlays ──────────────────────────────────────────────────────────────
  /// Modal barrier scrim behind loading overlays/dialogs.
  static const Color overlayScrim = Color(0x55000000);

  // ── Semantic opacities ────────────────────────────────────────────────────
  // Prefer the solid onSurfaceVariant/divider tokens below where a themed
  // color already exists; these are for one-off `.withValues(alpha: ...)`
  // derivations from an arbitrary foreground color.
  static const double secondaryTextOpacity = 0.60;
  static const double dividerOpacity = 0.12;
  static const double disabledOpacity = 0.38;

  // ── Neutrals – Light ──────────────────────────────────────────────────────
  static const Color backgroundLight = Color(0xFFEAF7EC);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceVariantLight = Color(0xFFE8F5EE);
  static const Color onSurfaceLight = Color(0xFF10251A);
  static const Color onSurfaceVariantLight = Color(0xFF4A6358);
  static const Color outlineLight = Color(0xFFB2CFBF);
  static const Color dividerLight = Color(0xFFDDEDE4);

  /// Soft sky-blue accent for light-mode illustrative backgrounds.
  static const Color skyAccentLight = Color(0xFFDCEFFF);

  // ── Neutrals – Dark ───────────────────────────────────────────────────────
  // Deep forest blue-green, never pure black — the app should feel like a
  // quiet forest at night, not an OLED void.
  static const Color backgroundDark = Color(0xFF132A1F);
  static const Color surfaceDark = Color(0xFF1C3A2A);
  static const Color surfaceVariantDark = Color(0xFF243B2C);
  static const Color onSurfaceDark = Color(0xFFF2F8F3);
  static const Color onSurfaceVariantDark = Color(0xFF8FB89E);
  static const Color outlineDark = Color(0xFF3D5E47);
  static const Color dividerDark = Color(0xFF2A3D30);

  // ── Shimmer (loading placeholders) ────────────────────────────────────────
  static const Color shimmerBaseLight = Color(0xFFE0EDE5);
  static const Color shimmerHighlightLight = Color(0xFFF4FAF6);
  static const Color shimmerBaseDark = Color(0xFF2A3D30);
  static const Color shimmerHighlightDark = Color(0xFF3A5040);

  static Color shimmerBase(bool isDark) =>
      isDark ? shimmerBaseDark : shimmerBaseLight;
  static Color shimmerHighlight(bool isDark) =>
      isDark ? shimmerHighlightDark : shimmerHighlightLight;

  // ── Achievement rarity tiers ──────────────────────────────────────────────
  // Common/Rare/Legendary intentionally reuse existing brand tokens rather
  // than introduce near-duplicate hex values — only Epic/Mythic need new,
  // dedicated colors.
  static const Color rarityCommon = Color(0xFF9BA8A3);
  static const Color rarityRare = skyBlue;
  static const Color rarityEpic = Color(0xFF9B59B6);
  static const Color rarityLegendary = achievementGold;
  static const Color rarityMythic = Color(0xFFFC4E6F);

  // ── Challenge category colors ─────────────────────────────────────────────
  // One entry per ChallengeCategory case (see ChallengeCategoryX.color in
  // challenge_model.dart) — reuses existing brand/rarity tokens for the same
  // reason the rarity tiers above do, rather than introduce near-duplicate
  // hex values. Kept in the same hue families as map_screen.dart's
  // _hueForCategory so category color reads consistently between the
  // Daily Challenge card and the map's category-colored markers.
  static const Color categoryNature = grassGreen;
  static const Color categoryObservation = skyBlue;
  static const Color categoryExercise = streakOrange;
  static const Color categoryExploration = warmYellow;
  static const Color categoryPhotography = Color(0xFF00B4D8);
  static const Color categoryMindfulness = rarityEpic;
  static const Color categoryEnvironmental = forestGreenDark;
  static const Color categoryMicroAdventure = rarityMythic;

  // ── Challenge path node states ────────────────────────────────────────────
  static const Color nodeCompleted = grassGreen;
  static const Color nodeActive = forestGreen;
  static const Color nodeLocked = Color(0xFFCDD5CF);
  static const Color nodeLockedDark = Color(0xFF3D4F44);

  // ── Gradients ─────────────────────────────────────────────────────────────
  static const LinearGradient gradientForest = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [forestGreen, grassGreen],
  );

  static const LinearGradient gradientSky = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [skyBlueLight, skyBlue],
  );

  static const LinearGradient gradientGold = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFE066), achievementGold],
  );

  static const LinearGradient gradientStreak = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [warmYellow, streakOrange],
  );
}

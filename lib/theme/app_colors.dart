import 'package:flutter/material.dart';

/// All color constants for the TouchGrass design system.
///
/// Never reference raw hex values outside this file — always use named tokens.
abstract final class AppColors {
  // ── Primary: Forest Green ─────────────────────────────────────────────────
  static const Color forestGreen = Color(0xFF2D6A4F);
  static const Color forestGreenLight = Color(0xFF40916C);
  static const Color forestGreenDark = Color(0xFF1B4332);

  // ── Secondary: Grass Green ────────────────────────────────────────────────
  static const Color grassGreen = Color(0xFF52B788);
  static const Color grassGreenLight = Color(0xFF74C69D);

  // ── Accents ───────────────────────────────────────────────────────────────
  static const Color skyBlue = Color(0xFF4EA8DE);
  static const Color skyBlueLight = Color(0xFF90C2E7);
  static const Color warmYellow = Color(0xFFF4A261);
  static const Color achievementGold = Color(0xFFFFB703);
  static const Color streakOrange = Color(0xFFFF6B35);

  // ── Semantic ──────────────────────────────────────────────────────────────
  static const Color success = grassGreen;
  static const Color error = Color(0xFFE63946);
  static const Color warning = warmYellow;

  // ── Neutrals – Light ──────────────────────────────────────────────────────
  static const Color backgroundLight = Color(0xFFF0F7F2);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceVariantLight = Color(0xFFE8F5EE);
  static const Color onSurfaceLight = Color(0xFF1B2E24);
  static const Color onSurfaceVariantLight = Color(0xFF4A6358);
  static const Color outlineLight = Color(0xFFB2CFBF);
  static const Color dividerLight = Color(0xFFDDEDE4);

  // ── Neutrals – Dark ───────────────────────────────────────────────────────
  static const Color backgroundDark = Color(0xFF0D1B14);
  static const Color surfaceDark = Color(0xFF1A2E22);
  static const Color surfaceVariantDark = Color(0xFF243B2C);
  static const Color onSurfaceDark = Color(0xFFDFF2E8);
  static const Color onSurfaceVariantDark = Color(0xFF8FB89E);
  static const Color outlineDark = Color(0xFF3D5E47);
  static const Color dividerDark = Color(0xFF2A3D30);

  // ── Challenge category colors ─────────────────────────────────────────────
  static const Color categoryNature = grassGreen;
  static const Color categoryExploration = skyBlue;
  static const Color categoryObservation = achievementGold;
  static const Color categoryActivity = streakOrange;

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

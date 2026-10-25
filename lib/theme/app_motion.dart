import 'package:flutter/animation.dart';

/// Animation duration and curve tokens for the TouchGrass design system.
///
/// Ambient/looping effects (companion idle bob, background particle drift)
/// are intentionally excluded — those are tuned per-effect, not part of the
/// UI-feedback tiers below.
abstract final class AppMotion {
  // ── Durations ─────────────────────────────────────────────────────────────
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 250);
  static const Duration long = Duration(milliseconds: 400);
  static const Duration hero = Duration(milliseconds: 700);

  /// Progress-bar / value reveal animations (achievement progress, XP fills).
  static const Duration reveal = Duration(milliseconds: 750);

  // ── Curves ────────────────────────────────────────────────────────────────
  /// Default for most feedback/entrance animation.
  static const Curve standardCurve = Curves.easeOut;

  /// Symmetric transitions (cross-fades, toggles).
  static const Curve transitionCurve = Curves.easeInOut;

  /// Playful overshoot for achievement/celebration moments.
  static const Curve achievementCurve = Curves.easeOutBack;

  /// Gentle default for page-level transitions.
  static const Curve pageCurve = Curves.ease;

  // ── Button press micro-interaction (Part G/L) ────────────────────────────
  static const double pressedScale = 0.97;
  static const Duration pressDuration = Duration(milliseconds: 120);
}

import 'package:flutter/material.dart';

/// Four-level elevation/shadow system for the TouchGrass design system.
///
/// Shadows use a dark forest tint rather than pure black — subtle and warm
/// rather than harsh. Pick one tier per surface; never hand-roll a one-off
/// `BoxShadow`.
abstract final class AppElevation {
  /// No shadow — flush surfaces (list rows, inline chips).
  static const List<BoxShadow> flat = [];

  /// Soft lift — pressed/secondary surfaces, nav bars.
  static const List<BoxShadow> low = [
    BoxShadow(color: Color(0x140B1A12), blurRadius: 6, offset: Offset(0, 2)),
  ];

  /// Standard card elevation.
  static const List<BoxShadow> medium = [
    BoxShadow(color: Color(0x1F0B1A12), blurRadius: 14, offset: Offset(0, 4)),
  ];

  /// Dialogs, sheets, anything that should feel like it's floating above
  /// the rest of the screen.
  static const List<BoxShadow> high = [
    BoxShadow(color: Color(0x2E0B1A12), blurRadius: 24, offset: Offset(0, 10)),
  ];

  /// A colored "glow" shadow for celebratory/branded surfaces (e.g. the
  /// primary CTA, streak/XP highlights) — layer over [medium] or [high]
  /// rather than replacing the neutral tiers above.
  static List<BoxShadow> glow(Color color, {double opacity = 0.35}) => [
        BoxShadow(
          color: color.withValues(alpha: opacity),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];
}

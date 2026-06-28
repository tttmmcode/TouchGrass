import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';

/// Breakpoint-aware layout utilities.
///
/// All helpers read [MediaQuery] via [MediaQuery.sizeOf] (cheap — no rebuild
/// unless the dimension actually changes).
///
/// Breakpoints:
///   small   < 360 dp  — compact Android or very small phone
///   medium  360–599   — standard phone (most devices)
///   large   600–767   — large phone / phablet / small tablet
///   tablet  >= 768    — tablet or desktop
abstract final class Responsive {
  static const double _breakSmall = 360;
  static const double _breakLarge = 600;
  static const double _breakTablet = 768;

  // ── Predicates ──────────────────────────────────────────────────────────────

  static bool isSmall(BuildContext context) =>
      MediaQuery.sizeOf(context).width < _breakSmall;

  static bool isMedium(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= _breakSmall && w < _breakLarge;
  }

  static bool isLarge(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= _breakLarge && w < _breakTablet;
  }

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= _breakTablet;

  // ── Convenience getters ─────────────────────────────────────────────────────

  static double screenWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static double screenHeight(BuildContext context) =>
      MediaQuery.sizeOf(context).height;

  // ── Adaptive values ─────────────────────────────────────────────────────────

  /// Returns [tablet] on tablets, [large] on large phones, otherwise [mobile].
  static T value<T>(
    BuildContext context, {
    required T mobile,
    T? large,
    T? tablet,
  }) {
    if (isTablet(context)) return tablet ?? large ?? mobile;
    if (isLarge(context)) return large ?? mobile;
    return mobile;
  }

  /// Horizontal screen padding that scales with screen width.
  static EdgeInsets screenPadding(BuildContext context) {
    if (isSmall(context)) {
      return const EdgeInsets.symmetric(horizontal: AppSpacing.md);
    }
    if (isTablet(context)) {
      return const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl);
    }
    return const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenHorizontal);
  }

  /// Scales a base font size slightly up on tablets.
  static double fontSize(BuildContext context, double base) {
    if (isTablet(context)) return base * 1.1;
    if (isSmall(context)) return base * 0.95;
    return base;
  }

  /// Number of grid columns for a given screen width.
  static int gridColumns(BuildContext context, {int mobile = 1}) {
    if (isTablet(context)) return mobile * 2;
    return mobile;
  }
}

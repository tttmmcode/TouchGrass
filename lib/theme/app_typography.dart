import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Semantic typography scale for the TouchGrass design system.
///
/// Each style resolves its color from the current [Theme] brightness unless
/// [color] is passed explicitly. Line height is fixed at 1.35x across the
/// scale; letter spacing is subtle and only applied to headings.
///
/// Prefer these over inline `TextStyle(fontFamily: 'Nunito', ...)` literals.
abstract final class AppTypography {
  static const double _lineHeight = 1.35;

  static Color _onSurface(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight;
  }

  static TextStyle _style(
    BuildContext context,
    double size,
    FontWeight weight, {
    Color? color,
    double letterSpacing = 0,
  }) => GoogleFonts.nunito(
    fontSize: size,
    fontWeight: weight,
    height: _lineHeight,
    letterSpacing: letterSpacing,
    color: color ?? _onSurface(context),
  );

  /// 40 / Bold — hero numbers, splash moments.
  static TextStyle display(BuildContext context, {Color? color}) =>
      _style(context, 40, FontWeight.w800, color: color, letterSpacing: -0.25);

  /// 32 / Bold — page title.
  static TextStyle pageTitle(BuildContext context, {Color? color}) =>
      _style(context, 32, FontWeight.w800, color: color, letterSpacing: -0.15);

  /// 24 / Bold — section title.
  static TextStyle sectionTitle(BuildContext context, {Color? color}) =>
      _style(context, 24, FontWeight.w800, color: color);

  /// 20 / SemiBold — card title.
  static TextStyle cardTitle(BuildContext context, {Color? color}) =>
      _style(context, 20, FontWeight.w700, color: color);

  /// 18 / Medium — subtitle.
  static TextStyle subtitle(BuildContext context, {Color? color}) =>
      _style(context, 18, FontWeight.w600, color: color);

  /// 16 / Regular — primary body text.
  static TextStyle body(BuildContext context, {Color? color}) =>
      _style(context, 16, FontWeight.w500, color: color);

  /// 14 / Regular — secondary/supporting text.
  static TextStyle secondaryText(BuildContext context, {Color? color}) =>
      _style(context, 14, FontWeight.w500, color: color);

  /// 12 / Medium — captions.
  static TextStyle caption(BuildContext context, {Color? color}) =>
      _style(context, 12, FontWeight.w600, color: color, letterSpacing: 0.1);

  /// 11 / Medium — micro labels (eyebrows, badges, timestamps).
  static TextStyle microLabel(BuildContext context, {Color? color}) =>
      _style(context, 11, FontWeight.w700, color: color, letterSpacing: 0.4);
}

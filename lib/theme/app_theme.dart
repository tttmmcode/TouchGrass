import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// Assembles the Material 3 [ThemeData] for both light and dark modes.
///
/// Use [AppTheme.light] and [AppTheme.dark] in [MaterialApp]. Never
/// construct ThemeData anywhere else in the app.
abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.forestGreen,
      brightness: brightness,
    ).copyWith(
      primary: AppColors.forestGreen,
      onPrimary: Colors.white,
      primaryContainer: isDark ? AppColors.forestGreenDark : const Color(0xFFD8F3DC),
      onPrimaryContainer: isDark ? AppColors.onSurfaceDark : AppColors.forestGreenDark,
      secondary: AppColors.grassGreen,
      onSecondary: Colors.white,
      secondaryContainer: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight,
      onSecondaryContainer: isDark ? AppColors.onSurfaceDark : AppColors.forestGreenDark,
      tertiary: AppColors.skyBlue,
      onTertiary: Colors.white,
      tertiaryContainer: isDark ? const Color(0xFF1A2E3A) : const Color(0xFFDEF0FA),
      onTertiaryContainer: isDark ? AppColors.skyBlueLight : const Color(0xFF0A2D45),
      error: AppColors.error,
      onError: Colors.white,
      surface: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      onSurface: isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight,
      surfaceContainerHighest: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight,
      onSurfaceVariant: isDark ? AppColors.onSurfaceVariantDark : AppColors.onSurfaceVariantLight,
      outline: isDark ? AppColors.outlineDark : AppColors.outlineLight,
      outlineVariant: isDark ? AppColors.dividerDark : AppColors.dividerLight,
    );

    final textTheme = _buildTextTheme(isDark, colorScheme);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,

      // ── AppBar ─────────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        foregroundColor: isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: _nunito(
          18, FontWeight.w800,
          isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight,
        ),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent)
            : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      ),

      // ── Bottom Navigation Bar ──────────────────────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        indicatorColor: AppColors.forestGreen.withValues(alpha: 0.15),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        elevation: 8,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? AppColors.forestGreen
                : (isDark ? AppColors.onSurfaceVariantDark : AppColors.onSurfaceVariantLight),
            size: AppSpacing.iconMd,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return _nunito(
            12,
            selected ? FontWeight.w800 : FontWeight.w600,
            selected
                ? AppColors.forestGreen
                : (isDark ? AppColors.onSurfaceVariantDark : AppColors.onSurfaceVariantLight),
          );
        }),
      ),

      // ── Cards ─────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceLight,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          side: BorderSide(
            color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
            width: 1.5,
          ),
        ),
      ),

      // ── Elevated Button ────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.forestGreen,
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              isDark ? AppColors.surfaceVariantDark : AppColors.dividerLight,
          minimumSize: const Size.fromHeight(AppSpacing.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          textStyle: _nunito(16, FontWeight.w800, Colors.white, ls: 0.5),
        ),
      ),

      // ── Outlined Button ────────────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.forestGreen,
          minimumSize: const Size.fromHeight(AppSpacing.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          side: const BorderSide(color: AppColors.forestGreen, width: 2),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          textStyle: _nunito(16, FontWeight.w800, AppColors.forestGreen, ls: 0.5),
        ),
      ),

      // ── Text Button ────────────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.forestGreen,
          textStyle: _nunito(14, FontWeight.w700, AppColors.forestGreen),
        ),
      ),

      // ── Input Decoration ───────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(
            color: isDark ? AppColors.outlineDark : AppColors.outlineLight,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(
            color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.forestGreen, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        labelStyle: _nunito(
          14, FontWeight.w600,
          isDark ? AppColors.onSurfaceVariantDark : AppColors.onSurfaceVariantLight,
        ),
        hintStyle: _nunito(
          14, FontWeight.w500,
          isDark ? AppColors.onSurfaceVariantDark : AppColors.onSurfaceVariantLight,
        ),
      ),

      // ── Chip ──────────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight,
        selectedColor: AppColors.forestGreen.withValues(alpha: 0.18),
        labelStyle: _nunito(
          13, FontWeight.w700,
          isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        ),
        side: BorderSide(
          color: isDark ? AppColors.outlineDark : AppColors.outlineLight,
        ),
      ),

      // ── SnackBar ──────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppColors.surfaceVariantDark : AppColors.onSurfaceLight,
        contentTextStyle: _nunito(14, FontWeight.w600, Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
      ),

      // ── Progress Indicator ────────────────────────────────────────────────
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.forestGreen,
        linearTrackColor: isDark ? AppColors.dividerDark : AppColors.dividerLight,
        linearMinHeight: 8,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),

      // ── Icon ─────────────────────────────────────────────────────────────
      iconTheme: IconThemeData(
        color: isDark ? AppColors.onSurfaceVariantDark : AppColors.onSurfaceVariantLight,
        size: AppSpacing.iconMd,
      ),

      // ── Divider ───────────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
        thickness: 1,
        space: 1,
      ),

      // ── Dialog ────────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXxl),
        ),
        titleTextStyle: _nunito(
          20, FontWeight.w800,
          isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight,
        ),
      ),

      // ── Bottom Sheet ──────────────────────────────────────────────────────
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusXxl),
          ),
        ),
        dragHandleColor: isDark ? AppColors.outlineDark : AppColors.outlineLight,
      ),
    );
  }

  // ── Typography helpers ──────────────────────────────────────────────────────

  static TextStyle _nunito(
    double size,
    FontWeight weight,
    Color color, {
    double? ls,
    double? height,
  }) =>
      GoogleFonts.nunito(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: ls,
        height: height,
      );

  static TextTheme _buildTextTheme(bool isDark, ColorScheme scheme) {
    final onSurface = isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight;
    final onSurfaceVariant =
        isDark ? AppColors.onSurfaceVariantDark : AppColors.onSurfaceVariantLight;

    TextStyle t(double size, FontWeight weight, Color color,
            {double? ls, double? h}) =>
        GoogleFonts.nunito(
            fontSize: size,
            fontWeight: weight,
            color: color,
            letterSpacing: ls,
            height: h);

    return TextTheme(
      displayLarge: t(57, FontWeight.w900, onSurface, ls: -0.25),
      displayMedium: t(45, FontWeight.w900, onSurface),
      displaySmall: t(36, FontWeight.w800, onSurface),
      headlineLarge: t(32, FontWeight.w800, onSurface),
      headlineMedium: t(28, FontWeight.w700, onSurface),
      headlineSmall: t(24, FontWeight.w700, onSurface),
      titleLarge: t(22, FontWeight.w700, onSurface),
      titleMedium: t(16, FontWeight.w700, onSurface, ls: 0.15),
      titleSmall: t(14, FontWeight.w700, onSurfaceVariant, ls: 0.1),
      bodyLarge: t(16, FontWeight.w500, onSurface, h: 1.5),
      bodyMedium: t(14, FontWeight.w500, onSurface, h: 1.5),
      bodySmall: t(12, FontWeight.w500, onSurfaceVariant, h: 1.5),
      labelLarge: t(14, FontWeight.w800, onSurface, ls: 0.1),
      labelMedium: t(12, FontWeight.w700, onSurfaceVariant, ls: 0.5),
      labelSmall: t(11, FontWeight.w700, onSurfaceVariant, ls: 0.5),
    );
  }

  /// Returns the correct [SystemUiOverlayStyle] for status/nav bars.
  static SystemUiOverlayStyle overlayStyleFor(Brightness brightness) {
    return brightness == Brightness.dark
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: AppColors.surfaceDark,
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: AppColors.surfaceLight,
          );
  }
}

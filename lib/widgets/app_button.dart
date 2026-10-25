import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'pressable_scale.dart';

enum AppButtonVariant { primary, secondary }

/// Standardized button per the TouchGrass design system: 56dp height, 16dp
/// corner radius, 24dp horizontal padding, 12dp icon-to-label spacing, and
/// the shared [PressableScale] press micro-interaction. Covers loading and
/// disabled states; hover/focus rely on [InkWell]'s built-in overlay
/// behavior.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonVariant variant;
  final bool loading;
  final bool expand;

  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPrimary = variant == AppButtonVariant.primary;

    final Color background;
    final Color foreground;
    final Border? border;
    if (!_enabled) {
      background = isDark
          ? AppColors.surfaceVariantDark
          : AppColors.dividerLight;
      foreground = isDark
          ? AppColors.onSurfaceVariantDark
          : AppColors.onSurfaceVariantLight;
      border = null;
    } else if (isPrimary) {
      background = AppColors.forestGreen;
      foreground = Colors.white;
      border = null;
    } else {
      background = Colors.transparent;
      foreground = AppColors.forestGreen;
      border = Border.all(color: AppColors.forestGreen, width: 2);
    }

    final content = loading
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: foreground,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, color: foreground, size: AppSpacing.iconMd),
                const SizedBox(width: AppSpacing.md),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: foreground,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          );

    return PressableScale(
      enabled: _enabled,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
          border: border,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
            child: Container(
              height: AppSpacing.buttonHeight,
              width: expand ? double.infinity : null,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              alignment: Alignment.center,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

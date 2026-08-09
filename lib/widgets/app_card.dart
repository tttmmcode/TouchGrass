import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_elevation.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';

/// Standardized card surface per the TouchGrass design system: 20dp corner
/// radius, 20dp padding, medium elevation, theme-aware surface color. Pass
/// [onTap] to get a tiny elevation-increase micro-interaction on hover/press.
class AppCard extends StatefulWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.betweenCards),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? AppColors.surfaceVariantDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.dividerDark : AppColors.dividerLight;

    final card = AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.standardCurve,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: border, width: 1.5),
        boxShadow:
            widget.onTap != null && _hovered ? AppElevation.high : AppElevation.medium,
      ),
      child: Padding(padding: widget.padding, child: widget.child),
    );

    if (widget.onTap == null) return card;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _hovered = v),
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          child: card,
        ),
      ),
    );
  }
}

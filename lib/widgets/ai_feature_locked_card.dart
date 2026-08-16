import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// "Coming Soon" messaging for an AI feature gated behind
/// [EntitlementTier.canUseAiVerification] — ready for use once the entitlement
/// system is actually wired into a real flow (see
/// providers/entitlement_providers.dart's doc comment for current status).
///
/// Deliberately not a dead-end: explains *why* clearly rather than just
/// hiding the feature, matching "do not make the UI look broken."
class AiFeatureLockedCard extends StatelessWidget {
  const AiFeatureLockedCard({
    super.key,
    required this.isDark,
    this.title = 'AI Verification — Coming Soon',
    this.message =
        "AI photo verification is being upgraded to run securely on our "
        'servers. This feature isn\'t available on your current plan yet '
        '— check back soon!',
  });

  final bool isDark;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final surface = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceVariantLight;
    final strong = isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight;
    final muted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    return Semantics(
      label: '$title. $message',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          border: Border.all(
            color: isDark ? AppColors.outlineDark : AppColors.outlineLight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    size: AppSpacing.iconMd,
                    color: AppColors.forestGreen,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: strong,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: muted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

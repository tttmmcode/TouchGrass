import 'package:flutter/material.dart';

import '../../../core/constants/privacy_copy.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';

/// Covers the Settings screen while `deleteAccount` runs (Phase 7H). The
/// call can take minutes for an account with many photos; without this the
/// screen looked idle, so it could be left or the deletion started again.
/// It blocks every tap underneath and announces itself to screen readers.
/// It claims nothing about the outcome — success is shown only after the
/// server confirms.
class AccountDeletionProgress extends StatelessWidget {
  const AccountDeletionProgress({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceLight;
    return Stack(
      children: [
        const ModalBarrier(dismissible: false, color: Colors.black54),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Semantics(
              liveRegion: true,
              label:
                  '${PrivacyCopy.deleteAccountProgress} '
                  '${PrivacyCopy.deleteAccountProgressDetail}',
              excludeSemantics: true,
              child: Material(
                color: surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                child: const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: AppSpacing.lg),
                      Text(
                        PrivacyCopy.deleteAccountProgress,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: AppSpacing.sm),
                      Text(
                        PrivacyCopy.deleteAccountProgressDetail,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../core/constants/privacy_copy.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// The Terms of Service and Privacy Policy dialogs, shared by Settings and
/// the sign-in screen (Phase 8: the sign-in footer said "you agree to our
/// Terms" without any way to read them there).
Future<void> showTermsDialog(BuildContext context) => _showLegalDialog(
  context,
  title: PrivacyCopy.termsTitle,
  text: PrivacyCopy.termsText,
);

Future<void> showPrivacyPolicyDialog(BuildContext context) => _showLegalDialog(
  context,
  title: PrivacyCopy.privacyPolicyTitle,
  text: PrivacyCopy.privacyPolicyText,
);

Future<void> _showLegalDialog(
  BuildContext context, {
  required String title,
  required String text,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final surface = isDark
      ? AppColors.surfaceVariantDark
      : AppColors.surfaceLight;
  final textStrong = isDark
      ? AppColors.onSurfaceDark
      : AppColors.onSurfaceLight;
  final textMuted = isDark
      ? AppColors.onSurfaceVariantDark
      : AppColors.onSurfaceVariantLight;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      backgroundColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontFamily: 'Nunito',
          fontWeight: FontWeight.w900,
          color: textStrong,
        ),
      ),
      content: Text(
        text,
        style: TextStyle(
          fontFamily: 'Nunito',
          fontSize: 13,
          fontWeight: FontWeight.w500,
          height: 1.5,
          color: textMuted,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text(
            'Got it',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w700,
              color: AppColors.forestGreenLight,
            ),
          ),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Which OS permission a [maybeShowPermissionPrimer] call is explaining.
///
/// Each case carries its own copy so callers never need to duplicate the
/// "why we're asking" text — matches the exact wording the product brief
/// specifies for each permission.
enum PermissionPrimerKind {
  camera(
    prefsKey: 'permission_primer_shown_camera',
    emoji: '📸',
    title: 'Capture your adventure',
    body: 'Use your camera to capture today\'s adventure.',
  ),
  location(
    prefsKey: 'permission_primer_shown_location',
    emoji: '📍',
    title: 'Local weather & memories',
    body:
        'TouchGrass uses your location to show local weather and save '
        'where your adventures happen.',
  ),
  notifications(
    prefsKey: 'permission_primer_shown_notifications',
    emoji: '🔔',
    title: 'Never miss an adventure',
    body: 'Get reminders when a new daily adventure is ready.',
  );

  const PermissionPrimerKind({
    required this.prefsKey,
    required this.emoji,
    required this.title,
    required this.body,
  });

  final String prefsKey;
  final String emoji;
  final String title;
  final String body;
}

/// Shows a short, friendly explanation of *why* TouchGrass is about to ask
/// for [kind] — once per permission, ever — immediately before the native
/// OS permission dialog fires. Native prompts give no room for context, so
/// dumping three of them on a user with zero explanation (the previous
/// behavior) reads as presumptuous; this closes that gap without adding
/// friction on every subsequent launch.
///
/// Always returns (never throws) so callers can safely proceed to the real
/// permission request afterward regardless of outcome — this is purely
/// educational, not a second gate the user must explicitly accept before
/// the OS dialog is allowed to appear.
Future<void> maybeShowPermissionPrimer(
  BuildContext context,
  PermissionPrimerKind kind,
) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(kind.prefsKey) ?? false) return;
  await prefs.setBool(kind.prefsKey, true);

  if (!context.mounted) return;

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

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      title: Row(
        children: [
          Text(kind.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              kind.title,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w900,
                fontSize: 17,
                color: textStrong,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        kind.body,
        style: TextStyle(
          fontFamily: 'Nunito',
          fontWeight: FontWeight.w500,
          fontSize: 14,
          height: 1.4,
          color: textMuted,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text(
            'Continue',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w900,
              color: AppColors.forestGreen,
            ),
          ),
        ),
      ],
    ),
  );
}

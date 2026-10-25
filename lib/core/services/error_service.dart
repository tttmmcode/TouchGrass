import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../errors/app_exception.dart';

/// Centralized error presentation.
///
/// Converts any [AppException] (or raw error) into a user-friendly string and
/// can display it as a floating SnackBar. Technical details never reach the UI.
abstract final class ErrorService {
  /// Maps any error to a human-readable message safe to show to users.
  static String friendlyMessage(Object error) {
    if (error is AppException) return error.message;
    return 'Something went wrong. Please try again.';
  }

  /// Shows a red error SnackBar. No-ops if [context] is no longer mounted.
  static void showError(BuildContext context, Object error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        _snackBar(context, friendlyMessage(error), AppColors.error),
      );
  }

  /// Shows a green success SnackBar. No-ops if [context] is no longer mounted.
  static void showSuccess(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(_snackBar(context, message, AppColors.success));
  }

  /// Shows a neutral info SnackBar. No-ops if [context] is no longer mounted.
  static void showInfo(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(_snackBar(context, message, AppColors.info));
  }

  static SnackBar _snackBar(
    BuildContext context,
    String message,
    Color backgroundColor,
  ) => SnackBar(
    content: Text(
      message,
      style: const TextStyle(
        fontFamily: 'Nunito',
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
    ),
    backgroundColor: backgroundColor,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    margin: const EdgeInsets.all(AppSpacing.md),
  );
}

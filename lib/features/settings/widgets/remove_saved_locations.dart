import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/privacy_copy.dart';
import '../../../repositories/location_history_repository.dart';

/// "Remove saved locations" (audit D-09, Phase 5): confirm → remove →
/// report. Cancelling changes nothing. Success is only shown when the
/// repository verified nothing is left; otherwise the user is told that
/// some locations may remain and can safely retry. [onChanged] runs after
/// any run that removed something (even partly), so cached Journal and map
/// data can be refreshed.
Future<void> confirmAndRemoveSavedLocations(
  BuildContext context, {
  required String uid,
  required bool locationSettingOn,
  required LocationHistoryRepository repository,
  VoidCallback? onChanged,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text(PrivacyCopy.removeLocationsDialogTitle),
      content: SingleChildScrollView(
        child: Text(
          PrivacyCopy.removeLocationsBody(settingOn: locationSettingOn),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await _runRemoval(
    context,
    uid: uid,
    repository: repository,
    onChanged: onChanged,
  );
}

Future<void> _runRemoval(
  BuildContext context, {
  required String uid,
  required LocationHistoryRepository repository,
  VoidCallback? onChanged,
}) async {
  // The ROOT navigator: showDialog puts the progress dialog there. Settings
  // lives in the Profile tab's nested navigator, so the nearest navigator
  // would pop the Settings page instead and leave the undismissable
  // progress dialog up for good (Phase 8, found in the browser run).
  final navigator = Navigator.of(context, rootNavigator: true);
  // Non-dismissible while running, so the operation can't be started twice.
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  semanticsLabel: PrivacyCopy.removeLocationsProgress,
                ),
              ),
              SizedBox(width: 16),
              Expanded(child: Text(PrivacyCopy.removeLocationsProgress)),
            ],
          ),
        ),
      ),
    ),
  );
  final result = await repository.removeSavedLocations(uid);
  navigator.pop(); // the progress dialog
  if (result.completionsCleared + result.entriesCleared > 0) onChanged?.call();
  if (!context.mounted) return;

  if (result.isComplete) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          PrivacyCopy.removeLocationsDone(
            anyRemoved: result.completionsCleared + result.entriesCleared > 0,
          ),
        ),
      ),
    );
    return;
  }

  final retry = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text(PrivacyCopy.removeLocationsFailedTitle),
      content: Text(switch (result.status) {
        LocationRemovalStatus.offline => PrivacyCopy.removeLocationsOffline,
        LocationRemovalStatus.incomplete =>
          PrivacyCopy.removeLocationsIncomplete,
        _ => PrivacyCopy.removeLocationsFailed,
      }),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Close'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Try again'),
        ),
      ],
    ),
  );
  if (retry == true && context.mounted) {
    await _runRemoval(
      context,
      uid: uid,
      repository: repository,
      onChanged: onChanged,
    );
  }
}

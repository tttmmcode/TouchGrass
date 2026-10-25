/// User-facing privacy wording, kept in one place so the settings toggle,
/// the explanation dialog and the privacy policy describe exactly what the
/// app does (audit D-09). `test/core/privacy_copy_test.dart` checks this
/// text against the behaviour it describes.
abstract final class PrivacyCopy {
  /// The `settings.locationEnabled` toggle.
  static const locationSettingTitle = 'Save location with adventures';

  static String locationSettingSubtitle({required bool enabled}) => enabled
      ? 'On: where you completed a challenge, its place name and weather are '
            'saved in your Journal, and your approximate location is used for '
            'local weather.'
      : 'Off: no location is saved, and none is sent for weather or place '
            'names. Your map still shows where you are.';

  static const locationOffDialogTitle = 'Turn off saving location?';

  /// What stops working when the setting is off. Shown before turning it off
  /// and when the user taps the "Location off" weather chip.
  static const locationOffEffects =
      'With this off, TouchGrass will not:\n'
      '• save where you completed a challenge, its place name or its weather '
      'with new completions and Journal entries;\n'
      '• send your location to the weather service or to look up place names.\n\n'
      'So these are unavailable while it is off:\n'
      '• local weather on Home, and local sunrise/sunset for the Automatic '
      'theme (it follows your device\'s light/dark setting instead);\n'
      '• map pins for new Journal entries (they still appear in your '
      'Journal);\n'
      '• weather-based challenges (challenges are not tailored to weather in '
      'this version either way).\n\n'
      'The map can still show your own position while you have it open; that '
      'stays on your device. Entries you saved earlier keep their location '
      'until you use "$removeLocationsTitle". You can turn this back on at '
      'any time in Settings → Privacy.';

  // ── "Remove saved locations" (historical data; separate from the setting,
  // which only controls what is saved from now on) ─────────────────────────

  static const removeLocationsTitle = 'Remove saved locations';

  static const removeLocationsSubtitle =
      'Delete the location, place name and weather saved with past '
      'adventures';

  static const removeLocationsDialogTitle = 'Remove saved locations?';

  /// What the removal does and doesn't do. [settingOn]: whether
  /// "Save location with adventures" is still on.
  static String removeLocationsBody({required bool settingOn}) =>
      'This permanently removes the location, place name and weather saved '
      "with all your past adventures and Journal entries. It can't be "
      'undone.\n\n'
      'Your Journal entries, photos, captions, XP, streak and challenge '
      'progress stay exactly as they are. Past adventures will no longer '
      'have a pin on the map.\n\n'
      '${settingOn ? _removeLocationsSettingStillOn : ''}'
      'Your photos themselves are not changed: photos saved with earlier '
      'versions of the app may still contain location details inside the '
      'image file.\n\n'
      'You need an internet connection. If it stops partway, anything '
      'already removed stays removed, and you can safely try again.';

  static const _removeLocationsSettingStillOn =
      '"$locationSettingTitle" is still on, so new adventures will keep '
      "saving their location. Turn it off if you don't want that.\n\n";

  static const removeLocationsProgress = 'Removing saved locations…';

  static String removeLocationsDone({required bool anyRemoved}) => anyRemoved
      ? 'Saved locations removed from your past adventures and Journal.'
      : 'There were no saved locations to remove.';

  static const removeLocationsFailedTitle = 'Not everything was removed';

  static const removeLocationsOffline =
      "We couldn't reach TouchGrass, so some saved locations may not have "
      'been removed. Anything already removed stays removed. Check your '
      'connection and try again.';

  static const removeLocationsFailed =
      'Something went wrong, so some saved locations may not have been '
      'removed. Anything already removed stays removed, and nothing else '
      'was changed. Please try again.';

  static const removeLocationsIncomplete =
      'New locations kept being saved while we were removing them — '
      'probably from another device where "$locationSettingTitle" is on — '
      'so some may remain. Turn that setting off, then try again.';

  static const locationOffChipLabel = 'Location off';

  static const privacyPolicyTitle = 'Privacy Policy';

  static const privacyPolicyText =
      'What TouchGrass stores (in Google Firebase):\n'
      '• Your account: email address, display name, username and profile photo.\n'
      '• Your challenge photos. Other TouchGrass users can\'t browse or open '
      'them in the app. Each photo is shown through a private web link, so '
      'anyone you share a photo\'s link with can see that photo.\n'
      '• Your completions, Journal entries, XP, streaks and achievements. Your '
      'display name, username, photo, XP, streak and league are shown on the '
      'leaderboard unless you turn off "Show on Leaderboard". Your profile '
      'photo is shown to other signed-in users, and anyone they share its '
      'link with can see it.\n'
      '• Feedback and bug reports you send from Settings.\n'
      '• A notification token, if you allow notifications.\n\n'
      'Location — only if "Save location with adventures" is on:\n'
      '• Where you completed a challenge is saved with that completion and '
      'Journal entry, with its place name and weather.\n'
      '• Your approximate location (about 1 km) is sent to Open-Meteo to show '
      'local weather, and your location is sent to your device\'s map '
      'service (Apple or Google) to look up place names.\n'
      'With it off, none of this happens. The map can still show your own '
      'position while you use it; that stays on your device.\n\n'
      'App diagnostics: Firebase Analytics, Crashlytics and Performance '
      'Monitoring collect usage events, crash reports and performance data '
      'to keep the app working.\n\n'
      'Your photos are not sent to any AI service: AI photo verification is '
      'turned off, and challenges use the honor system.\n\n'
      'We never sell your data. $deleteAccountScope Usage analytics and '
      'crash reports already sent to Firebase are kept for the period set '
      'for this app in Firebase. We also keep a record that the account was '
      'deleted (its internal ID and the time), so a device that was still '
      "signed in can't bring it back.";

  /// What Settings → Delete Account removes — exactly what the
  /// `deleteAccount` Cloud Function deletes (functions/src/accountDeletion.ts;
  /// pinned by privacy_copy_test.dart).
  static const deleteAccountScope =
      'Settings → Delete Account permanently deletes your account and the '
      'data saved with it: your profile, username, XP and streak, '
      'completions, Journal entries, photos, feedback and leaderboard entry.';

  static const deleteAccountWarning =
      'This permanently deletes your account and the data saved with it — '
      'your profile, XP and streak, challenge history, Journal entries and '
      'photos. This cannot be undone.';

  /// Shown while the server deletes the account (Phase 7H). Nothing is
  /// claimed yet: success is only reported after the server confirms.
  static const deleteAccountProgress = 'Deleting your account…';

  static const deleteAccountProgressDetail =
      'This can take a little while. Please keep TouchGrass open until it '
      'finishes.';

  /// Shown only once `deleteAccount` returned `{deleted: true}`.
  static const deleteAccountDone =
      'Your account and the data saved with it were deleted.';
}

// D-09: the settings label, the explanation and the privacy policy must
// describe what the app actually does. Behaviour itself is tested in
// location_privacy_test.dart, camera_flow_test.dart, journal_repair_test.dart
// and the emulator suite; this file pins the words to that behaviour.
// Also checks the D-13 camera UI states say what was (not) saved.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/core/constants/privacy_copy.dart';
import 'package:touchgrass/features/camera/screens/camera_screen.dart';
import 'package:touchgrass/providers/camera_providers.dart';

void main() {
  const policy = PrivacyCopy.privacyPolicyText;

  group('privacy policy lists every data flow', () {
    for (final mention in [
      PrivacyCopy.locationSettingTitle, // names the real setting
      'Open-Meteo', // weather (third party)
      'about 1 km', // coarse coordinates actually sent
      'place names', // platform geocoder
      'Firebase Analytics', 'Crashlytics', 'Performance Monitoring',
      'notification token',
      'leaderboard', 'Show on Leaderboard',
      'Feedback',
      'not sent to any AI service', // AI verification is off (D-06)
      'Delete Account',
    ]) {
      test('mentions "$mention"', () => expect(policy, contains(mention)));
    }
    test('no longer claims location is only used on completion', () {
      expect(policy, isNot(contains('only accessed when you complete')));
    });
    test('account deletion: says what is deleted and what Firebase keeps', () {
      expect(policy, contains(PrivacyCopy.deleteAccountScope));
      expect(policy, contains('Usage analytics and crash reports'));
      for (final item in [
        'Journal entries',
        'photos',
        'username',
        'feedback',
      ]) {
        expect(PrivacyCopy.deleteAccountScope, contains(item));
      }
      expect(PrivacyCopy.deleteAccountWarning, contains('cannot be undone'));
      expect(
        File(
          'lib/features/settings/screens/settings_screen.dart',
        ).readAsStringSync(),
        contains('PrivacyCopy.deleteAccountWarning'),
      );
    });
    test('the deletion promise matches what deleteAccount deletes', () {
      // Every data location the copy promises to delete is handled by the
      // server-side deletion (functions/src/accountDeletion.ts).
      final fn = File('functions/src/accountDeletion.ts').readAsStringSync();
      for (final path in [
        'completion_photos/', // photos
        'user_avatars/', // profile photo
        '"completions"', // completions
        '"usernames"', // username
        '"feedback"', // feedback
        '"leaderboard_public"', // leaderboard entry
        'recursiveDelete(db.collection("users")', // profile + Journal
        'deleteUser(uid)', // the account itself
      ]) {
        expect(fn, contains(path), reason: path);
      }
    });
    test('does not mention Gemini (no AI processing happens)', () {
      expect(policy.toLowerCase(), isNot(contains('gemini')));
    });
  });

  group('setting off → explanation of what is unavailable', () {
    for (final mention in [
      'weather',
      'place name',
      'map pins',
      'weather-based challenges',
      'stays on your device',
      'Settings → Privacy',
    ]) {
      test('mentions "$mention"', () {
        expect(PrivacyCopy.locationOffEffects, contains(mention));
      });
    }
    test('the subtitle states the off behaviour', () {
      expect(
        PrivacyCopy.locationSettingSubtitle(enabled: false),
        contains('no location is saved'),
      );
      expect(
        PrivacyCopy.locationSettingSubtitle(enabled: true),
        contains('approximate location'),
      );
    });
  });

  test('the settings toggle and permission texts use the shared wording', () {
    final settings = File(
      'lib/features/settings/screens/settings_screen.dart',
    ).readAsStringSync();
    expect(settings, contains('PrivacyCopy.locationSettingTitle'));
    // Phase 8: Settings and sign-in share one policy dialog.
    expect(settings, contains('showPrivacyPolicyDialog(context)'));
    expect(
      File('lib/widgets/legal_dialogs.dart').readAsStringSync(),
      contains('PrivacyCopy.privacyPolicyText'),
    );
    expect(settings, isNot(contains("'Store Location Data'")));
    // Phase 5: the historical-data control sits next to the setting.
    expect(settings, contains('PrivacyCopy.removeLocationsTitle'));
    expect(settings, contains('confirmAndRemoveSavedLocations('));
    expect(
      PrivacyCopy.locationOffEffects,
      contains(PrivacyCopy.removeLocationsTitle),
    );
    expect(
      File('lib/widgets/permission_primer.dart').readAsStringSync(),
      contains('Settings → Privacy'),
    );
    expect(
      File('ios/Runner/Info.plist').readAsStringSync(),
      contains('if you allow it in Settings'),
    );
  });

  group('camera UI states (D-13)', () {
    final bytes = Uint8List(1);
    test('headlines say what happened', () {
      expect(
        failureHeadline(
          CameraFailure(
            message: 'x',
            bytes: bytes,
            kind: CameraFailureKind.uploadFailed,
          ),
        ),
        'Photo not uploaded',
      );
      expect(
        failureHeadline(
          CameraFailure(
            message: 'x',
            bytes: bytes,
            kind: CameraFailureKind.saveFailed,
          ),
        ),
        'Not saved yet',
      );
      expect(
        failureHeadline(
          const CameraFailure(
            message: 'x',
            kind: CameraFailureKind.alreadyCompleted,
          ),
        ),
        'Already completed',
      );
      expect(
        failureHeadline(
          CameraFailure(message: 'x', bytes: bytes, confidence: 0.4),
        ),
        'Verification Failed',
      );
    });
    test(
      'retry is offered for upload/save failures but not when already completed',
      () {
        expect(
          CameraFailure(
            message: 'x',
            bytes: bytes,
            kind: CameraFailureKind.uploadFailed,
          ).canRetry,
          isTrue,
        );
        expect(
          CameraFailure(
            message: 'x',
            bytes: bytes,
            kind: CameraFailureKind.saveFailed,
          ).canRetry,
          isTrue,
        );
        expect(
          CameraFailure(
            message: 'x',
            bytes: bytes,
            kind: CameraFailureKind.alreadyCompleted,
          ).canRetry,
          isFalse,
        );
        expect(
          const CameraFailure(
            message: 'x',
            kind: CameraFailureKind.uploadFailed,
          ).canRetry,
          isFalse,
          reason: 'no photo to retry with',
        );
      },
    );
    test('"saved" is only claimed once the Journal entry was committed', () {
      expect(
        journalSavedLabel(savedToJournal: false, hasLocation: true),
        isNull,
      );
      expect(
        journalSavedLabel(savedToJournal: true, hasLocation: false),
        'Photo saved to your Journal',
      );
      expect(
        journalSavedLabel(savedToJournal: true, hasLocation: true),
        contains('location saved'),
      );
    });
  });

  // Phase 7D: user-facing text must not promise what the app doesn't do.
  group('no false privacy or AI claims (Phase 7D)', () {
    String src(String path) => File(path).readAsStringSync();
    test('challenge photos are not described as visible only to the owner', () {
      expect(policy, isNot(contains('only you can see')));
      // The truth: not browsable by other users, but delivered by link.
      expect(policy, contains("can't browse or open"));
      expect(policy, contains('link'));
    });
    test('profile-photo visibility is disclosed, including links', () {
      expect(
        policy,
        contains('profile photo is shown to other signed-in users'),
      );
    });
    test('deletion copy no longer says "everything"', () {
      expect(PrivacyCopy.deleteAccountScope, isNot(contains('everything')));
      expect(PrivacyCopy.deleteAccountWarning, isNot(contains('everything')));
    });
    test(
      'the policy discloses the deleted-account record deleteAccount keeps (Phase 7G)',
      () {
        expect(policy, contains('record that the account was deleted'));
        expect(policy, contains('internal ID and the time'));
      },
    );
    test('no screen claims AI verifies photos or that photos train AI', () {
      for (final path in [
        'lib/features/onboarding/screens/onboarding_screen.dart',
        'lib/features/settings/screens/settings_screen.dart',
        'lib/features/camera/screens/camera_screen.dart',
        'lib/features/challenges/screens/challenge_detail_screen.dart',
      ]) {
        final text = src(path);
        expect(text, isNot(contains('our AI will verify')), reason: path);
        expect(text, isNot(contains('improve AI verification')), reason: path);
        expect(text, isNot(contains("'AI Verdict'")), reason: path);
        expect(text, isNot(contains('access to verify your')), reason: path);
      }
    });
  });
}

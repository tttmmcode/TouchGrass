// Phase 8 (found in the real-browser run): controls must not promise what
// nothing delivers.
// - Reminders: no sender exists (no Cloud Function or scheduler publishes a
//   push message), and web can't receive topic messages — so no permission
//   prompt, no reminder toggles and no notification token while that's true.
// - Weather: the header shows a real reading or the "Location off"
//   explanation, never an empty "unavailable" placeholder.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/core/constants/app_constants.dart';
import 'package:touchgrass/core/constants/privacy_copy.dart';
import 'package:touchgrass/features/home/screens/home_screen.dart';
import 'package:touchgrass/models/weather_model.dart';

bool _anyFunctionSendsPush() => Directory('functions/src')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.ts') && !f.path.contains('.test.'))
    .any(
      (f) => RegExp(
        r'getMessaging|messaging\(\)|sendToTopic|sendEachForMulticast',
      ).hasMatch(f.readAsStringSync()),
    );

void main() {
  group('reminders', () {
    test('stay unavailable while nothing sends them', () {
      expect(_anyFunctionSendsPush(), isFalse);
      expect(
        AppConstants.remindersAvailable,
        isFalse,
        reason: 'turn reminders on only together with a real sender',
      );
    });
    test('no permission prompt, toggles or token while unavailable', () {
      final shell = File('lib/widgets/app_shell.dart').readAsStringSync();
      expect(shell, contains('if (AppConstants.remindersAvailable)'));
      final settings = File(
        'lib/features/settings/screens/settings_screen.dart',
      ).readAsStringSync();
      expect(
        settings.indexOf('if (AppConstants.remindersAvailable)'),
        lessThan(settings.indexOf("_SectionLabel('Notifications'")),
      );
      final tokens = File(
        'lib/providers/notification_providers.dart',
      ).readAsStringSync();
      expect(tokens, contains('if (!AppConstants.remindersAvailable) return;'));
    });
  });

  group('header weather', () {
    const reading = WeatherModel(temperatureCelsius: 21, weatherCode: 0);
    test('no placeholder chip without a reading', () {
      expect(showHeaderWeather(locationOff: false, weather: null), isFalse);
    });
    test('a real reading, or the Location-off explanation, is shown', () {
      expect(showHeaderWeather(locationOff: false, weather: reading), isTrue);
      expect(showHeaderWeather(locationOff: true, weather: null), isTrue);
    });
  });

  group('terms of service', () {
    test(
      'describe photo access like the privacy policy, with no "never" promise',
      () {
        const terms = PrivacyCopy.termsText;
        expect(terms, isNot(contains('never share')));
        expect(terms, contains("can't browse or open them"));
        expect(terms, contains('private web link'));
        expect(PrivacyCopy.privacyPolicyText, contains("can't browse or open"));
        expect(terms, contains('not sent to any AI service'));
      },
    );
    test('can be read from the sign-in screen and Settings', () {
      final login = File(
        'lib/features/auth/screens/login_screen.dart',
      ).readAsStringSync();
      expect(login, contains('showTermsDialog(context)'));
      expect(login, contains('showPrivacyPolicyDialog(context)'));
      final settings = File(
        'lib/features/settings/screens/settings_screen.dart',
      ).readAsStringSync();
      expect(settings, contains('showTermsDialog(context)'));
      expect(settings, isNot(contains('_showTermsDialog')));
    });
  });

  test('feedback: Send enables while typing (found in the browser run)', () {
    final settings = File(
      'lib/features/settings/screens/settings_screen.dart',
    ).readAsStringSync();
    final form = settings.substring(settings.indexOf('content: TextField('));
    final field = form.substring(0, form.indexOf('decoration:'));
    expect(field, contains('onChanged: (_) => setS(() {})'));
  });
}

/// How users can reach TouchGrass support.
///
/// The owner confirmed [confirmedEmail] as the support address on
/// 2026-10-25 (Phase 8). Before that the app pointed users to
/// Settings → Send Feedback, because the earlier proposed address was never
/// confirmed. A build can still name a different confirmed address:
///
///   `--dart-define=TG_SUPPORT_EMAIL=<confirmed address>`
///
/// Every place that names a support contact uses this class
/// (`test/core/support_contact_test.dart` checks that no other code
/// hard-codes an address).
abstract final class SupportContact {
  static const String confirmedEmail = 'toughpiprojects@gmail.com';

  static const String email = String.fromEnvironment(
    'TG_SUPPORT_EMAIL',
    defaultValue: confirmedEmail,
  );

  static bool get hasVerifiedEmail => email.isNotEmpty;

  /// For the Help dialog's "Contact us" entry.
  static String get contactLine => hasVerifiedEmail
      ? email
      : 'Use Settings → Send Feedback to send us a message.';

  /// Completes a sentence such as "If this keeps happening, …".
  static String get reachUs => hasVerifiedEmail
      ? 'email $email'
      : 'send us a message from Settings → Send Feedback';
}

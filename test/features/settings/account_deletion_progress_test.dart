// Account deletion progress (Phase 7H): while the server deletes the
// account the Settings screen is covered, can't be left or tapped, and says
// what is happening — without claiming the outcome. Success is announced
// only once the server confirmed it.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/core/constants/privacy_copy.dart';
import 'package:touchgrass/features/settings/widgets/account_deletion_progress.dart';

void main() {
  testWidgets('says what is happening and blocks every tap underneath', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Center(
                child: ElevatedButton(
                  onPressed: () => taps++,
                  child: const Text('Delete Account'),
                ),
              ),
              const Positioned.fill(child: AccountDeletionProgress()),
            ],
          ),
        ),
      ),
    );
    expect(find.text(PrivacyCopy.deleteAccountProgress), findsOneWidget);
    expect(find.text(PrivacyCopy.deleteAccountProgressDetail), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.text('Delete Account'), warnIfMissed: false);
    expect(taps, 0, reason: 'a second deletion cannot be started');
  });

  testWidgets('is announced to screen readers as a live region', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AccountDeletionProgress())),
    );
    expect(
      tester.getSemantics(
        find.bySemanticsLabel(RegExp(PrivacyCopy.deleteAccountProgress)),
      ),
      matchesSemantics(
        isLiveRegion: true,
        label:
            '${PrivacyCopy.deleteAccountProgress} '
            '${PrivacyCopy.deleteAccountProgressDetail}',
      ),
    );
    handle.dispose();
  });

  test('the progress copy never claims the account is already deleted', () {
    for (final text in [
      PrivacyCopy.deleteAccountProgress,
      PrivacyCopy.deleteAccountProgressDetail,
    ]) {
      expect(text.toLowerCase(), isNot(contains('deleted')));
    }
    expect(PrivacyCopy.deleteAccountDone, contains('deleted'));
  });

  test('Settings shows the overlay while deleting, and "deleted" only on the '
      "server's success", () {
    final src = File(
      'lib/features/settings/screens/settings_screen.dart',
    ).readAsStringSync();
    expect(src, contains('canPop: !_deletingAccount'));
    expect(src, contains('if (_deletingAccount)'));
    expect(src, contains('AccountDeletionProgress()'));
    expect(src, contains('|| _deletingAccount) return;'));
    // The success message is only in the `ok:` branch of the result.
    final ok = src.indexOf('ok: (_) => messenger');
    final done = src.indexOf('PrivacyCopy.deleteAccountDone');
    final err = src.indexOf('err: (e) {', ok);
    expect(ok, greaterThan(0));
    expect(done, inExclusiveRange(ok, err));
    expect('PrivacyCopy.deleteAccountDone'.allMatches(src).length, 1);
  });
}

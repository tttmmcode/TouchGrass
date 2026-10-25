// P6-A2: analytics and crash reports stop carrying a user's ID once they
// sign out or delete their account.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/providers/user_providers.dart';

void main() {
  test('a newly signed-in user is identified once', () {
    expect(
      analyticsIdentityAction(null, 'alice'),
      AnalyticsIdentityAction.identify,
    );
    expect(
      analyticsIdentityAction('alice', 'alice'),
      AnalyticsIdentityAction.none,
    );
  });

  test('switching accounts identifies the new user', () {
    expect(
      analyticsIdentityAction('alice', 'bob'),
      AnalyticsIdentityAction.identify,
    );
  });

  test('sign-out or deletion clears the ID exactly once', () {
    expect(
      analyticsIdentityAction('alice', null),
      AnalyticsIdentityAction.clear,
    );
    expect(analyticsIdentityAction(null, null), AnalyticsIdentityAction.none);
  });

  test('account deletion resets this device\'s analytics after the server '
      'confirms', () {
    final repo = File(
      'lib/repositories/user_repository.dart',
    ).readAsStringSync();
    final confirm = repo.indexOf(
      'await _accountDeletion.deleteCurrentAccount();',
    );
    final reset = repo.indexOf('AnalyticsService.resetAfterAccountDeletion();');
    expect(confirm, greaterThan(0));
    expect(reset, greaterThan(confirm));
  });
}

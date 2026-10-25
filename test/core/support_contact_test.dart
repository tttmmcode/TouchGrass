// Phase 8: one support address, confirmed by the owner, named in one place.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/core/constants/support_contact.dart';
import 'package:touchgrass/services/account_deletion_service.dart';

void main() {
  test('the confirmed address is the contact', () {
    expect(SupportContact.email, SupportContact.confirmedEmail);
    expect(SupportContact.hasVerifiedEmail, isTrue);
    expect(SupportContact.contactLine, SupportContact.confirmedEmail);
    expect(SupportContact.reachUs, 'email ${SupportContact.confirmedEmail}');
  });

  test('deletion errors use the configured contact', () {
    for (final code in ['not-found', 'internal']) {
      final message = mapAccountDeletionError(code).message;
      expect(message, contains(SupportContact.reachUs), reason: code);
    }
  });

  test('no other source file hard-codes an email address', () {
    final pattern = RegExp(
      r"""['"][^'"\n]*[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z]{2,}[^'"\n]*['"]""",
    );
    final offenders = <String>[];
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.path
          .replaceAll(r'\', '/')
          .endsWith('constants/support_contact.dart')) {
        continue;
      }
      for (final line in f.readAsLinesSync()) {
        if (line.trimLeft().startsWith('//')) continue;
        if (pattern.hasMatch(line)) offenders.add('${f.path}: $line');
      }
    }
    expect(offenders, isEmpty);
  });

  test('the retired, unconfirmed address appears nowhere in the app', () {
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      expect(
        f.readAsStringSync(),
        isNot(contains('support@touchgrass.app')),
        reason: f.path,
      );
    }
  });
}

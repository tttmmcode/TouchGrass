// Unit tests for the fail-closed/dev-only guard in
// challenge_verification_service.dart. The guard itself is extracted as a
// pure function specifically so it's testable here without needing to
// control EnvironmentConfig.isProduction, a compile-time --dart-define
// constant a normal `flutter test` run can't flip per-test.

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/services/challenge_verification_service.dart';

void main() {
  group('assertLocalVerificationAllowed', () {
    test('does not throw for a non-production build', () {
      expect(() => assertLocalVerificationAllowed(false), returnsNormally);
    });

    test('throws StateError for a production build', () {
      expect(
        () => assertLocalVerificationAllowed(true),
        throwsA(isA<StateError>()),
      );
    });
  });
}

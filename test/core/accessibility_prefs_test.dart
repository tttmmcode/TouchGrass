// Unit tests for the pure accessibility-preference composition helpers used
// by main.dart's root MediaQuery override (Section 7, Part C/J/G). These
// exist so an OS-level Dynamic Type / Reduce Motion / Increase Contrast
// setting is always honored alongside TouchGrass's own in-app equivalent,
// never silently discarded by it.

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/core/utils/accessibility_prefs.dart';

void main() {
  group('combinedTextScale', () {
    test('is a pure passthrough of the system scale when the app scale is '
        'left at its 1.0 default', () {
      expect(
        combinedTextScale(systemTextScale: 1.8, appTextScale: 1.0),
        1.8,
      );
    });

    test('stacks the app-level preference on top of the system scale', () {
      expect(
        combinedTextScale(systemTextScale: 1.5, appTextScale: 1.2),
        closeTo(1.8, 1e-9),
      );
    });

    test('a default system scale (1.0) still reflects a customized app '
        'scale', () {
      expect(
        combinedTextScale(systemTextScale: 1.0, appTextScale: 1.3),
        1.3,
      );
    });
  });

  group('combinedReducedMotion', () {
    test('is false only when neither source wants reduced motion', () {
      expect(
        combinedReducedMotion(
            systemReducedMotion: false, appReducedMotion: false),
        isFalse,
      );
    });

    test('an OS-level Reduce Motion setting is honored even if the '
        'in-app toggle was never touched', () {
      expect(
        combinedReducedMotion(
            systemReducedMotion: true, appReducedMotion: false),
        isTrue,
      );
    });

    test('the in-app toggle alone is still honored without OS support', () {
      expect(
        combinedReducedMotion(
            systemReducedMotion: false, appReducedMotion: true),
        isTrue,
      );
    });

    test('both enabled is still just reduced motion (no double effect to '
        'reason about)', () {
      expect(
        combinedReducedMotion(
            systemReducedMotion: true, appReducedMotion: true),
        isTrue,
      );
    });
  });

  group('combinedHighContrast', () {
    test('is false only when neither source wants high contrast', () {
      expect(
        combinedHighContrast(
            systemHighContrast: false, appHighContrast: false),
        isFalse,
      );
    });

    test('an OS-level Increase Contrast setting is honored on its own', () {
      expect(
        combinedHighContrast(systemHighContrast: true, appHighContrast: false),
        isTrue,
      );
    });

    test('the in-app toggle alone is still honored', () {
      expect(
        combinedHighContrast(systemHighContrast: false, appHighContrast: true),
        isTrue,
      );
    });
  });
}

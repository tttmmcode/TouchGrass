// Unit tests for nextCompanionMessage — the anti-repeat selection logic
// behind the mascot's tap-to-respond interaction (home_screen.dart's
// _TrailCompanion). Deterministic under test via the injectable [pickIndex]
// callback rather than depending on wall-clock Random.

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/companions/companion.dart';

void main() {
  group('nextCompanionMessage', () {
    test('excludes the previous message when alternatives exist', () {
      final result = nextCompanionMessage(
        pool: const ['a', 'b', 'c'],
        previous: 'a',
        pickIndex: (count) => 0, // always picks the first candidate
      );
      // Candidates after excluding 'a' are ['b', 'c']; index 0 -> 'b'.
      expect(result, 'b');
      expect(result, isNot('a'));
    });

    test('pickIndex only ever sees candidates, never the excluded message', () {
      final result = nextCompanionMessage(
        pool: const ['a', 'b', 'c', 'd'],
        previous: 'b',
        pickIndex: (count) {
          expect(count, 3); // 'b' excluded, 3 candidates remain
          return count - 1; // last candidate
        },
      );
      expect(result, 'd');
    });

    test(
      'a single-message pool returns that message (no alternative exists)',
      () {
        final result = nextCompanionMessage(
          pool: const ['only one'],
          previous: 'only one',
          pickIndex: (count) => fail('pickIndex should not be called'),
        );
        expect(result, 'only one');
      },
    );

    test(
      'previous not found in pool at all still returns a real pool entry',
      () {
        final result = nextCompanionMessage(
          pool: const ['x', 'y'],
          previous: 'not in the pool',
          pickIndex: (count) => 0,
        );
        expect(result, 'x');
      },
    );

    test('an empty pool returns an empty string rather than throwing', () {
      final result = nextCompanionMessage(pool: const [], previous: 'a');
      expect(result, '');
    });

    test('uses a real Random when pickIndex is not supplied', () {
      // No injected picker — exercise the default path and just assert it
      // terminates with a valid pool member, not a specific value.
      final result = nextCompanionMessage(
        pool: const ['a', 'b', 'c'],
        previous: 'a',
      );
      expect(['b', 'c'], contains(result));
    });
  });
}

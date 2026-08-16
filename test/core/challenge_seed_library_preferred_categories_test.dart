import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/core/data/challenge_seed_library.dart';
import 'package:touchgrass/models/challenge_model.dart';

void main() {
  group('ChallengeSeedLibrary preferred-category filtering', () {
    test(
      'empty preferredCategories (no preference) can return any category',
      () {
        // Sweep a wide range of userId/dayNumber combinations — with no filter,
        // more than one distinct category should appear across the sweep.
        final categoriesSeen = <ChallengeCategory>{};
        for (var day = 1; day <= 40; day++) {
          final seed = ChallengeSeedLibrary.selectSeed(
            dayNumber: day,
            userId: 'user-$day',
            difficulty: ChallengeDifficulty.easy,
          );
          categoriesSeen.add(seed.category);
        }
        expect(categoriesSeen.length, greaterThan(1));
      },
    );

    test(
      'a single preferred category is always honored when seeds exist for it',
      () {
        for (var day = 1; day <= 30; day++) {
          final seed = ChallengeSeedLibrary.selectSeed(
            dayNumber: day,
            userId: 'user-$day',
            difficulty: ChallengeDifficulty.easy,
            preferredCategories: {ChallengeCategory.mindfulness},
          );
          expect(seed.category, ChallengeCategory.mindfulness);
        }
      },
    );

    test(
      'a multi-category preference only ever returns one of those categories',
      () {
        const preferred = {
          ChallengeCategory.photography,
          ChallengeCategory.exploration,
        };
        for (var day = 1; day <= 30; day++) {
          final seed = ChallengeSeedLibrary.selectSeed(
            dayNumber: day,
            userId: 'user-$day',
            difficulty: ChallengeDifficulty.medium,
            preferredCategories: preferred,
          );
          expect(preferred.contains(seed.category), isTrue);
        }
      },
    );

    test('selectRerollSeed also honors preferredCategories', () {
      for (var reroll = 1; reroll <= 10; reroll++) {
        final seed = ChallengeSeedLibrary.selectRerollSeed(
          dayNumber: 5,
          userId: 'user-5',
          difficulty: ChallengeDifficulty.easy,
          rerollCount: reroll,
          preferredCategories: {ChallengeCategory.exercise},
        );
        expect(seed.category, ChallengeCategory.exercise);
      }
    });

    test(
      'never returns zero candidates — always produces a seed even with a narrow preference',
      () {
        // Every individual category should still be selectable on its own
        // across a range of difficulties without ever throwing or returning
        // null (there's no null case — a thrown exception or empty pool
        // handling failure would surface as a test failure here).
        for (final category in ChallengeCategory.values) {
          for (final difficulty in ChallengeDifficulty.values) {
            expect(
              () => ChallengeSeedLibrary.selectSeed(
                dayNumber: 1,
                userId: 'probe',
                difficulty: difficulty,
                preferredCategories: {category},
              ),
              returnsNormally,
            );
          }
        }
      },
    );
  });
}

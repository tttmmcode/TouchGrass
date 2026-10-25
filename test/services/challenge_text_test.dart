// Phase 8 (found in the browser run): the challenge text always started
// with "Go outside and", so seeds whose action already goes out read
// "Go outside and go outside and look for…". Checks every seed.
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/core/data/challenge_seed_library.dart';
import 'package:touchgrass/services/challenge_generation_service.dart';

void main() {
  final outdoors = RegExp(r'\b(outside|outdoors)\b', caseSensitive: false);

  test('no challenge text says "go outside" twice', () {
    expect(ChallengeSeedLibrary.all, hasLength(ChallengeSeedLibrary.count));
    for (final seed in ChallengeSeedLibrary.all) {
      final text = ChallengeGenerationService.describe(seed, 3);
      // The subject may say "outside" too ("…growing naturally outside");
      // the duplication came from the prefix plus the action.
      final actionGoesOut =
          outdoors.hasMatch(seed.action) || seed.action.startsWith('go ');
      final action = seed.action[0].toUpperCase() + seed.action.substring(1);
      expect(
        text,
        startsWith(
          actionGoesOut
              ? '$action ${seed.subject}.'
              : 'Go outside and ${seed.action} ${seed.subject}.',
        ),
      );
      expect(text.toLowerCase(), isNot(contains('and go ')), reason: text);
      expect(text, endsWith('Take a photo to complete your Day 3 challenge.'));
      expect(text[0], text[0].toUpperCase(), reason: text);
    }
  });

  test('actions that stay put still get "Go outside and"', () {
    final seed = ChallengeSeedLibrary.all.firstWhere(
      (s) => s.action == 'find and photograph',
    );
    expect(
      ChallengeGenerationService.describe(seed, 1),
      startsWith('Go outside and find and photograph '),
    );
  });

  test('the generator uses this text', () {
    final seed = ChallengeSeedLibrary.all.first;
    final c = const ChallengeGenerationService().generate(
      seed: seed,
      userId: 'synthetic-user',
      dayNumber: 2,
    );
    expect(c.description, ChallengeGenerationService.describe(seed, 2));
  });
}

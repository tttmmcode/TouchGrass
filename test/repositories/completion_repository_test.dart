// Unit test for CompletionRepository.completionDocId — the deterministic
// per-user-per-day document ID that both the client transaction and
// firestore.rules' completions `allow create` constraint depend on to make
// duplicate completions impossible. Firestore itself isn't testable here
// (no emulator/fake in this project — see test/models/game_logic_test.dart's
// header comment), but this ID-format contract is pure and worth locking in
// directly since firestore.rules re-derives the same formula independently
// and the two must stay byte-for-byte in sync.

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/repositories/completion_repository.dart';

void main() {
  group('CompletionRepository.completionDocId', () {
    test('is exactly userId_challengeId', () {
      expect(
        CompletionRepository.completionDocId('user123', '2026-03-10'),
        'user123_2026-03-10',
      );
    });

    test('is deterministic — same inputs always produce the same ID', () {
      final a = CompletionRepository.completionDocId('userA', '2026-03-10');
      final b = CompletionRepository.completionDocId('userA', '2026-03-10');
      expect(a, b);
    });

    test('different users completing the same challenge day never collide', () {
      final a = CompletionRepository.completionDocId('userA', '2026-03-10');
      final b = CompletionRepository.completionDocId('userB', '2026-03-10');
      expect(a, isNot(b));
    });

    test('the same user on different challenge days never collides', () {
      final a = CompletionRepository.completionDocId('userA', '2026-03-10');
      final b = CompletionRepository.completionDocId('userA', '2026-03-11');
      expect(a, isNot(b));
    });
  });
}

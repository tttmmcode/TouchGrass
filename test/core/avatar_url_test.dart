// N-6 (Phase 5): other users' profile photos are only loaded from the
// app's own avatar storage or Google's profile-photo host.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/core/utils/avatar_url.dart';

void main() {
  const bucket = 'touchgrass-today.firebasestorage.app';
  bool ok(String? url, {String? b = bucket}) =>
      isTrustedAvatarUrl(url, appStorageBucket: b);

  test('allows the app\'s own Storage avatars and Google profile photos', () {
    expect(
      ok(
        'https://firebasestorage.googleapis.com/v0/b/$bucket/o/user_avatars%2Falice.png?alt=media&token=abc',
      ),
      isTrue,
    );
    expect(ok('https://lh3.googleusercontent.com/a/ACg8ocK=s96-c'), isTrue);
  });

  for (final url in [
    null,
    '',
    'https://evil.example/pixel.png',
    'http://lh3.googleusercontent.com/a/x', // not https
    'https://googleusercontent.com.evil.example/x',
    'https://evilgoogleusercontent.com/x',
    'https://user@lh3.googleusercontent.com/a/x',
    'https://lh3.googleusercontent.com:8443/a/x',
    // Someone else's Firebase bucket (they could read its access logs).
    'https://firebasestorage.googleapis.com/v0/b/evil-bucket/o/user_avatars%2Fx.png?alt=media',
    // Another namespace in the app's own bucket.
    'https://firebasestorage.googleapis.com/v0/b/$bucket/o/completion_photos%2Falice%2F2026-10-01.jpg',
    'https://firebasestorage.googleapis.com/v0/b/$bucket/o/user_avatars%2F..%2Fcompletion_photos%2Fx.jpg',
    'javascript:alert(1)',
    'data:image/png;base64,AAAA',
  ]) {
    test('refuses $url', () => expect(ok(url), isFalse));
  }

  test('without a known bucket, Storage URLs are refused (fails closed)', () {
    expect(
      ok(
        'https://firebasestorage.googleapis.com/v0/b/$bucket/o/user_avatars%2Falice.png',
        b: null,
      ),
      isFalse,
    );
  });

  test('the leaderboard avatar goes through the filter', () {
    final src = File(
      'lib/features/leaderboard/screens/leaderboard_screen.dart',
    ).readAsStringSync();
    expect(src, contains('isTrustedAvatarUrl('));
    expect(src, isNot(contains('imageUrl: entry.photoUrl')));
  });
}

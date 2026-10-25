// N-6 (Phase 6): a new profile's photo is the verified ID token's `picture`
// claim — the only provider photo firestore.rules accept — or none.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/repositories/user_repository.dart';

class _Token implements IdTokenResult {
  _Token(this.claims);
  @override
  final Map<String, dynamic>? claims;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _User implements User {
  _User(this._token, {this.photoURL});
  final Object _token; // an IdTokenResult, or an error to throw
  @override
  final String? photoURL;
  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async {
    if (_token is IdTokenResult) return _token;
    throw _token;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  const google = 'https://lh3.googleusercontent.com/a/ACg8oc=s96-c';

  test('uses the token\'s picture claim (Google sign-in)', () async {
    expect(
      await UserRepository.signInProviderPhoto(
        _User(_Token({'picture': google}), photoURL: google),
      ),
      google,
    );
  });

  test('prefers the token claim over a differing Auth photoURL', () async {
    expect(
      await UserRepository.signInProviderPhoto(
        _User(_Token({'picture': google}), photoURL: 'https://other.example/x'),
      ),
      google,
    );
  });

  for (final (label, token) in [
    ('no picture claim (email / Apple)', _Token({'email': 'a@b.test'})),
    ('null claims', _Token(null)),
    ('an empty picture', _Token({'picture': ''})),
    ('a non-string picture', _Token({'picture': 42})),
    ('an over-long picture', _Token({'picture': 'https://x/${'a' * 2100}'})),
  ]) {
    test('no photo when there is $label', () async {
      expect(
        await UserRepository.signInProviderPhoto(
          _User(token, photoURL: google),
        ),
        isNull,
      );
    });
  }

  test(
    'no photo — and no sign-up failure — if the token can\'t be read',
    () async {
      expect(
        await UserRepository.signInProviderPhoto(
          _User(FirebaseAuthException(code: 'network-request-failed')),
        ),
        isNull,
      );
    },
  );
}

// Phase 8 (found in the real-browser run): the name typed at email sign-up
// was dropped — the credential's user object predates updateDisplayName —
// so every email account started as "Explorer".

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/repositories/user_repository.dart';
import 'package:touchgrass/services/account_deletion_service.dart';
import 'package:touchgrass/services/auth_service.dart';
import 'package:touchgrass/services/firestore_service.dart';
import 'package:touchgrass/services/storage_service.dart';

/// A just-created email user: like the real SDK's snapshot, it has no
/// display name yet.
class _NewUser implements User {
  @override
  String get uid => 'newbie';
  @override
  String? get displayName => null;
  @override
  String? get email => 'newbie@example.test';
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _Credential implements UserCredential {
  @override
  User? get user => _NewUser();
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _SignUpAuth implements AuthService {
  String? requestedName;
  @override
  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    requestedName = displayName;
    return _Credential();
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _NoStorage implements StorageService {
  @override
  dynamic noSuchMethod(Invocation i) => fail('storage must not be used');
}

class _NoDeletion implements AccountDeletionService {
  @override
  Future<void> deleteCurrentAccount() => fail('must not delete');
}

void main() {
  late FakeFirebaseFirestore db;
  late _SignUpAuth auth;
  late UserRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    auth = _SignUpAuth();
    repo = UserRepository(
      authService: auth,
      firestoreService: FirestoreService(db: db),
      storageService: _NoStorage(),
      db: db,
      accountDeletion: _NoDeletion(),
    );
  });

  test('the profile keeps the name typed at sign-up', () async {
    final result = await repo.signUpWithEmail(
      email: 'newbie@example.test',
      password: 'x',
      displayName: '  Maya Ortiz ',
    );
    expect(result.isOk, isTrue);
    final doc = (await db.collection('users').doc('newbie').get()).data()!;
    expect(doc['displayName'], 'Maya Ortiz');
    expect(auth.requestedName, '  Maya Ortiz ');
  });

  test('a blank name still falls back to "Explorer"', () async {
    await repo.signUpWithEmail(
      email: 'newbie@example.test',
      password: 'x',
      displayName: '   ',
    );
    final doc = (await db.collection('users').doc('newbie').get()).data()!;
    expect(doc['displayName'], 'Explorer');
  });

  test(
    'names are trimmed and capped at the 100 characters the rules allow',
    () {
      expect(signUpDisplayName(null), isNull);
      expect(signUpDisplayName(' \t'), isNull);
      expect(signUpDisplayName(' Sam '), 'Sam');
      expect(signUpDisplayName('x' * 150)!.length, 100);
    },
  );
}

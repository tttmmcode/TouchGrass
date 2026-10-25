// Avatar uploads vs. adventure-photo metrics (audit P2-9, Phase 5).
//
// An avatar is not an adventure photo: changing it must not touch
// `totalPhotosUploaded`, XP, streaks, completions or anything else that
// measures adventures. Adventure photos are counted by `totalCompletions`
// (exactly one photo per completion, validated by firestore.rules).
// Rules-level coverage is in firestore-tests/test/users.test.mjs.

import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/core/errors/app_exception.dart';
import 'package:touchgrass/models/achievement_definition.dart';
import 'package:touchgrass/models/challenge_model.dart';
import 'package:touchgrass/models/progression_model.dart';
import 'package:touchgrass/models/user_model.dart';
import 'package:touchgrass/repositories/completion_repository.dart';
import 'package:touchgrass/repositories/user_repository.dart';
import 'package:touchgrass/services/account_deletion_service.dart';
import 'package:touchgrass/services/auth_service.dart';
import 'package:touchgrass/services/firestore_service.dart';
import 'package:touchgrass/services/storage_service.dart';

/// Avatar storage that succeeds, or fails while [failuresLeft] > 0.
class _FakeAvatarStorage implements StorageService {
  int failuresLeft = 0;
  int uploads = 0;

  @override
  Future<String> uploadProfilePhoto({
    required String userId,
    required Uint8List bytes,
  }) async {
    if (failuresLeft > 0) {
      failuresLeft--;
      throw StorageException.uploadFailed(Exception('network'));
    }
    uploads++;
    return 'https://firebasestorage.googleapis.com/v0/b/x/o/user_avatars%2F$userId.png?v=$uploads';
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      fail('only uploadProfilePhoto may be used: ${i.memberName}');
}

class _NoAuth implements AuthService {
  @override
  dynamic noSuchMethod(Invocation i) => fail('auth must not be touched');
}

class _NoDeletion implements AccountDeletionService {
  @override
  Future<void> deleteCurrentAccount() => fail('must not delete');
}

void main() {
  const uid = 'alice';
  late FakeFirebaseFirestore db;
  late _FakeAvatarStorage storage;
  late UserRepository repo;
  final bytes = Uint8List.fromList(List.filled(32, 7));

  /// Progress fields an avatar change must never alter.
  const progressKeys = [
    'xp',
    'weeklyXp',
    'level',
    'streak',
    'longestStreak',
    'totalCompletions',
    'totalPhotosUploaded',
    'rainyDayCount',
    'currentLeague',
    'achievements',
    'lastActiveDate',
  ];

  Future<Map<String, dynamic>> userDoc() async =>
      (await db.collection('users').doc(uid).get()).data()!;

  Future<void> seed({bool withPhotoCounter = true}) async {
    final user =
        UserModel.initial(
          uid: uid,
          displayName: 'Alice',
          email: 'alice@example.test',
        ).copyWith(
          xp: 340,
          weeklyXp: 75,
          streak: 4,
          longestStreak: 6,
          totalCompletions: 9,
          totalPhotosUploaded: 3,
        );
    final data = user.toFirestore();
    if (!withPhotoCounter) data.remove('totalPhotosUploaded');
    await db.collection('users').doc(uid).set(data);
  }

  setUp(() {
    db = FakeFirebaseFirestore();
    storage = _FakeAvatarStorage();
    repo = UserRepository(
      authService: _NoAuth(),
      firestoreService: FirestoreService(db: db),
      storageService: storage,
      db: db,
      accountDeletion: _NoDeletion(),
    );
  });

  test('a successful avatar upload changes photoUrl only — no adventure '
      'count, XP, streak or completion', () async {
    await seed();
    final before = await userDoc();

    final result = await repo.uploadProfilePhoto(uid: uid, imageBytes: bytes);

    expect(result.isOk, isTrue);
    final after = await userDoc();
    expect(after['photoUrl'], result.valueOrThrow);
    for (final k in progressKeys) {
      expect(after[k], before[k], reason: '$k must not change');
    }
    expect((await db.collection('completions').get()).docs, isEmpty);
    // The public leaderboard mirror picks up the new avatar, nothing else.
    final mirror = (await db.collection('leaderboard_public').doc(uid).get())
        .data()!;
    expect(mirror['photoUrl'], result.valueOrThrow);
    expect(mirror['xp'], before['xp']);
    expect(mirror['streak'], before['streak']);
  });

  test('a failed avatar upload writes nothing', () async {
    await seed();
    final before = await userDoc();
    storage.failuresLeft = 1;

    final result = await repo.uploadProfilePhoto(uid: uid, imageBytes: bytes);

    expect(result.isErr, isTrue);
    expect(await userDoc(), before);
    expect(
      (await db.collection('leaderboard_public').doc(uid).get()).exists,
      isFalse,
    );
  });

  test('retrying after a failure, and uploading again, never counts '
      'anything', () async {
    await seed();
    storage.failuresLeft = 1;
    expect(
      (await repo.uploadProfilePhoto(uid: uid, imageBytes: bytes)).isErr,
      isTrue,
    );
    expect(
      (await repo.uploadProfilePhoto(uid: uid, imageBytes: bytes)).isOk,
      isTrue,
    );
    expect(
      (await repo.uploadProfilePhoto(uid: uid, imageBytes: bytes)).isOk,
      isTrue,
    );

    final after = await userDoc();
    expect(after['totalPhotosUploaded'], 3);
    expect(after['totalCompletions'], 9);
    expect(after['xp'], 340);
    expect(after['photoUrl'], endsWith('?v=2'));
  });

  test('an account with no totalPhotosUploaded field keeps none after an '
      'avatar upload, and reads as 0', () async {
    await seed(withPhotoCounter: false);

    await repo.uploadProfilePhoto(uid: uid, imageBytes: bytes);

    final after = await userDoc();
    expect(after.containsKey('totalPhotosUploaded'), isFalse);
    final model = UserModel.fromFirestore(
      await db.collection('users').doc(uid).get(),
    );
    expect(model.totalPhotosUploaded, 0);
  });

  test('an unrelated profile edit leaves the photo counter alone', () async {
    await seed();
    await repo.updateUserFields(uid, {'displayName': 'Alice B.'});
    final after = await userDoc();
    expect(after['displayName'], 'Alice B.');
    expect(after['totalPhotosUploaded'], 3);
  });

  test('adventure photos are counted once per completion by '
      'totalCompletions; a repeat on the same date counts nothing', () async {
    await seed();
    final today = ChallengeModel.docIdForDate(DateTime.now());
    final draft = CompletionRepository(db: db).buildCompletion(
      userId: uid,
      challengeId: today,
      challengeTitle: 'Find a leaf',
      challengeEmoji: '🍃',
      challengeCategory: ChallengeCategory.nature,
      photoUrl:
          'https://firebasestorage.googleapis.com/v0/b/x/o/completion_photos%2Falice%2F$today.jpg',
      verificationResult: const {'reason': 'Honor-system approved.'},
      xpAwarded: 25,
      overrideUsed: false,
    );

    expect((await repo.commitCompletion(draft)).isOk, isTrue);
    final once = await userDoc();
    expect(once['totalCompletions'], 10);
    expect(once['totalPhotosUploaded'], 3, reason: 'legacy field untouched');

    final again = await repo.commitCompletion(draft);
    expect(again.isErr, isTrue);
    final twice = await userDoc();
    expect(twice['totalCompletions'], 10);
    expect(twice['xp'], once['xp']);
    expect(twice['streak'], once['streak']);
  });

  test('progression and achievements do not depend on totalPhotosUploaded', () {
    final base = UserModel.initial(
      uid: uid,
      displayName: 'Alice',
      email: 'alice@example.test',
    ).copyWith(xp: 900, streak: 7, longestStreak: 7, totalCompletions: 10);
    final p0 = ProgressionModel.fromUser(base.copyWith(totalPhotosUploaded: 0));
    final p1 = ProgressionModel.fromUser(
      base.copyWith(totalPhotosUploaded: 999),
    );
    expect(p1.totalChallengesCompleted, p0.totalChallengesCompleted);
    expect(p1.totalXP, p0.totalXP);
    expect(p1.currentStreak, p0.currentStreak);
    // computeNewlyEarned has no photo-count input at all, so an avatar
    // change can never unlock an achievement; and no catalogued achievement
    // is about photos.
    expect(
      AchievementDefinition.catalog
          .map((a) => a.id)
          .where((id) => id.contains('photo')),
      isEmpty,
    );
  });
}

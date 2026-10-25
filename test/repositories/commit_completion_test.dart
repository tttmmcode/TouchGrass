// UserRepository.commitCompletion against fake_cloud_firestore — the real
// read/plan/batch-write flow (audit D-01 and D-02). Security-rule
// enforcement (create-only completions, concurrent submissions, denied
// batches writing nothing) is covered by the emulator suite in
// firestore-tests/; fake_cloud_firestore does not evaluate our rules.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/core/errors/app_exception.dart';
import 'package:touchgrass/core/result.dart';
import 'package:touchgrass/models/adventure_memory_model.dart';
import 'package:touchgrass/models/challenge_model.dart';
import 'package:touchgrass/models/completion_model.dart';
import 'package:touchgrass/models/user_model.dart';
import 'package:touchgrass/repositories/completion_repository.dart';
import 'package:touchgrass/repositories/memory_repository.dart';
import 'package:touchgrass/repositories/user_repository.dart';
import 'package:touchgrass/services/account_deletion_service.dart';
import 'package:touchgrass/services/auth_service.dart';
import 'package:touchgrass/services/firestore_service.dart';
import 'package:touchgrass/services/storage_service.dart';

class _FakeUser implements User {
  _FakeUser(this.uid);
  @override
  final String uid;
  @override
  String? get email => '$uid@example.test';
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Records the calls UserRepository makes on the auth layer.
class FakeAuthService implements AuthService {
  FakeAuthService(String? uid) : _user = uid == null ? null : _FakeUser(uid);
  final User? _user;
  final calls = <String>[];
  Object? reauthError;

  @override
  User? get currentUser => _user;
  @override
  Future<void> reauthenticateWithPassword({
    required String email,
    required String password,
  }) async {
    calls.add('reauth:password');
    if (reauthError != null) throw reauthError!;
  }

  @override
  Future<void> reauthenticateWithGoogle() async {
    calls.add('reauth:google');
    if (reauthError != null) throw reauthError!;
  }

  @override
  Future<void> reauthenticateWithApple() async => calls.add('reauth:apple');
  @override
  Future<void> signOut() async => calls.add('signOut');
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _NoStorage implements StorageService {
  @override
  dynamic noSuchMethod(Invocation i) => fail('storage must not be touched');
}

class FakeDeletionService implements AccountDeletionService {
  FakeDeletionService(this.calls);
  final List<String> calls;
  AppException? error;
  @override
  Future<void> deleteCurrentAccount() async {
    calls.add('serverDelete');
    if (error != null) throw error!;
  }
}

void main() {
  late FakeFirebaseFirestore db;
  late FakeAuthService auth;
  late FakeDeletionService deletion;
  late UserRepository repo;

  const uid = 'alice';
  final today = DateTime.now();
  final todayKey = ChallengeModel.docIdForDate(today);
  final yesterday = DateTime(today.year, today.month, today.day - 1, 12);

  UserRepository build() => UserRepository(
    authService: auth,
    firestoreService: FirestoreService(db: db),
    storageService: _NoStorage(),
    db: db,
    accountDeletion: deletion,
  );

  setUp(() {
    db = FakeFirebaseFirestore();
    auth = FakeAuthService(uid);
    deletion = FakeDeletionService(auth.calls);
    repo = build();
  });

  /// Seeds a user document exactly as the app stores one.
  Future<void> seedUser({
    int xp = 0,
    int streak = 0,
    int totalCompletions = 0,
    List<String> achievements = const [],
    DateTime? lastActive,
    DateTime? lastCompletion,
  }) async {
    final base =
        UserModel.initial(
          uid: uid,
          displayName: 'Alice',
          email: 'alice@example.test',
        ).copyWith(
          xp: xp,
          weeklyXp: xp,
          streak: streak,
          longestStreak: streak,
          totalCompletions: totalCompletions,
          achievements: achievements,
          lastActiveDate: (lastActive ?? DateTime.now()).toUtc(),
        );
    await db.collection('users').doc(uid).set({
      ...base.toFirestore(),
      if (lastCompletion != null)
        'lastCompletionDate': Timestamp.fromDate(lastCompletion),
    });
  }

  CompletionModel draft({
    String? challengeId,
    int xp = 25,
  }) => CompletionRepository(db: db).buildCompletion(
    userId: uid,
    challengeId: challengeId ?? todayKey,
    challengeTitle: 'Find a leaf',
    challengeEmoji: '🍃',
    challengeCategory: ChallengeCategory.nature,
    photoUrl:
        'https://firebasestorage.googleapis.com/v0/b/x/o/completion_photos%2Falice%2F${challengeId ?? todayKey}.jpg',
    verificationResult: const {'reason': 'Honor-system approved.'},
    xpAwarded: xp,
    overrideUsed: false,
  );

  Future<Map<String, dynamic>> userDoc() async =>
      (await db.collection('users').doc(uid).get()).data()!;

  group('commitCompletion — D-01 first-day rewards', () {
    test(
      'a brand-new user (signed up today) earns full XP and a streak of 1',
      () async {
        await seedUser(lastActive: DateTime.now());
        final result = await repo.commitCompletion(draft());
        final commit = result.valueOrThrow;

        expect(commit.reward.xpAwarded, 25);
        final u = await userDoc();
        expect(u['xp'], 50); // 25 challenge + 25 first_touch bonus
        expect(u['streak'], 1);
        expect(u['totalCompletions'], 1);
        expect(u['lastCompletionId'], '${uid}_$todayKey');
        expect(u['lastCompletionDate'], isA<Timestamp>());
      },
    );

    test(
      'the stored completion and the Journal-facing model record the XP actually granted',
      () async {
        await seedUser();
        final commit = (await repo.commitCompletion(draft())).valueOrThrow;
        final stored = await db
            .collection('completions')
            .doc('${uid}_$todayKey')
            .get();
        expect(stored.data()!['xpAwarded'], 25);
        expect(commit.completion.xpAwarded, 25);
      },
    );

    test(
      'a returning user who signed in today but completed yesterday gets XP and streak +1',
      () async {
        await seedUser(
          xp: 100,
          streak: 3,
          totalCompletions: 3,
          achievements: const ['first_touch', 'streak_3', 'xp_100'],
          lastActive: DateTime.now(),
          lastCompletion: yesterday,
        );
        final commit = (await repo.commitCompletion(draft())).valueOrThrow;
        expect(commit.reward.xpAwarded, 25);
        expect((await userDoc())['streak'], 4);
      },
    );

    test(
      'a legacy account without lastCompletionDate falls back to its latest completion',
      () async {
        await seedUser(
          xp: 100,
          streak: 3,
          totalCompletions: 3,
          achievements: const ['first_touch', 'streak_3', 'xp_100'],
          lastActive: DateTime.now(),
        );
        final yKey = ChallengeModel.docIdForDate(yesterday);
        await db.collection('completions').doc('${uid}_$yKey').set({
          'userId': uid,
          'challengeId': yKey,
          'completedAt': Timestamp.fromDate(yesterday),
          'xpAwarded': 25,
        });
        final commit = (await repo.commitCompletion(draft())).valueOrThrow;
        expect(commit.reward.xpAwarded, 25);
        expect(
          (await userDoc())['streak'],
          4,
          reason: 'continues from yesterday\'s completion',
        );
      },
    );

    test(
      'a legacy account with no completions at all is treated as a fresh start',
      () async {
        await seedUser(lastActive: DateTime.now());
        final commit = (await repo.commitCompletion(draft())).valueOrThrow;
        expect(commit.reward.xpAwarded, 25);
        expect((await userDoc())['streak'], 1);
      },
    );
  });

  group('commitCompletion — duplicates and retries', () {
    test(
      'a retry of the same submission is refused and awards nothing more',
      () async {
        await seedUser();
        (await repo.commitCompletion(draft())).valueOrThrow;
        final xpAfterFirst = (await userDoc())['xp'];

        final retry = await repo.commitCompletion(draft());
        expect(retry, isA<Err<CompletionCommit>>());
        expect(retry.exceptionOrThrow.message, contains('already completed'));
        expect((await userDoc())['xp'], xpAfterFirst);
        expect((await db.collection('completions').get()).size, 1);
      },
    );

    test(
      'a second completion on the same local day records 0 XP, not the challenge value',
      () async {
        await seedUser(lastCompletion: DateTime.now());
        final otherKey = ChallengeModel.docIdForDate(
          today.add(const Duration(days: 1)),
        );
        final commit = (await repo.commitCompletion(
          draft(challengeId: otherKey),
        )).valueOrThrow;
        expect(commit.reward.xpAwarded, 0);
        expect(commit.completion.xpAwarded, 0);
        final stored = await db
            .collection('completions')
            .doc('${uid}_$otherKey')
            .get();
        expect(
          stored.data()!['xpAwarded'],
          0,
          reason: 'Journal must never show XP that was not granted',
        );
      },
    );

    test(
      'a failed write (missing profile) reports an error and writes nothing',
      () async {
        final result = await repo.commitCompletion(draft());
        expect(result, isA<Err<CompletionCommit>>());
        expect((await db.collection('completions').get()).size, 0);
      },
    );
  });

  group('commitCompletion — D-13 Journal entry in the same batch', () {
    AdventureMemoryModel Function(CompletionModel) entry() =>
        (c) => journalEntryForCompletion(
          c,
          challengeDay: 2,
          includeLocation: false,
        );

    Future<Map<String, dynamic>?> journal(String id) async =>
        (await db.collection('users/$uid/memories').doc(id).get()).data();

    test(
      'writes the entry with the completion, mirroring photo and granted XP',
      () async {
        await seedUser();
        final commit = (await repo.commitCompletion(
          draft(),
          journalEntry: entry(),
        )).valueOrThrow;
        expect(commit.journalEntry, isNotNull);
        final m = (await journal('${uid}_$todayKey'))!;
        expect(m['photoUrl'], commit.completion.photoUrl);
        expect(m['xpEarned'], 25);
        expect(m['createdAt'], isA<Timestamp>());
      },
    );

    test(
      'a same-day completion records a 0-XP entry, never the challenge value',
      () async {
        await seedUser(lastCompletion: DateTime.now());
        final otherKey = ChallengeModel.docIdForDate(
          today.add(const Duration(days: 1)),
        );
        await repo.commitCompletion(
          draft(challengeId: otherKey),
          journalEntry: entry(),
        );
        expect((await journal('${uid}_$otherKey'))!['xpEarned'], 0);
      },
    );

    test('a retry writes no second entry and no extra XP', () async {
      await seedUser();
      await repo.commitCompletion(draft(), journalEntry: entry());
      final xp = (await userDoc())['xp'];
      final retry = await repo.commitCompletion(draft(), journalEntry: entry());
      expect(retry.isErr, isTrue);
      expect((await db.collection('users/$uid/memories').get()).size, 1);
      expect((await userDoc())['xp'], xp);
    });

    test('a failed save writes neither the completion nor the entry', () async {
      final result = await repo.commitCompletion(
        draft(),
        journalEntry: entry(),
      ); // no profile
      expect(result.isErr, isTrue);
      expect((await db.collection('completions').get()).size, 0);
      expect((await db.collection('users/$uid/memories').get()).size, 0);
    });

    test(
      'an entry that does not mirror its completion is refused before writing',
      () async {
        await seedUser();
        final result = await repo.commitCompletion(
          draft(),
          journalEntry: (c) => journalEntryForCompletion(
            c.withXpAwarded(100),
            challengeDay: 2,
            includeLocation: false,
          ),
        );
        expect(result.isErr, isTrue);
        expect((await db.collection('completions').get()).size, 0);
        expect((await db.collection('users/$uid/memories').get()).size, 0);
      },
    );
  });

  group('deleteAccount — D-04 orchestration', () {
    test('re-authenticates, deletes server-side, then signs out', () async {
      final result = await repo.deleteAccount(
        uid: uid,
        providerId: 'google.com',
      );
      expect(result.isOk, isTrue);
      expect(auth.calls, ['reauth:google', 'serverDelete', 'signOut']);
    });

    test('email users re-authenticate with their password', () async {
      await repo.deleteAccount(uid: uid, password: 'pw');
      expect(auth.calls.first, 'reauth:password');
    });

    test(
      'a failed re-authentication stops before anything is deleted',
      () async {
        auth.reauthError = const DataException(
          message: 'Email or password is incorrect.',
        );
        final result = await repo.deleteAccount(uid: uid, password: 'wrong');
        expect(result.isErr, isTrue);
        expect(auth.calls, ['reauth:password']);
      },
    );

    test(
      'a server failure is reported as an error and the user stays signed in to retry',
      () async {
        deletion.error = mapAccountDeletionError('internal');
        final result = await repo.deleteAccount(
          uid: uid,
          providerId: 'google.com',
        );
        expect(result.isErr, isTrue);
        expect(result.exceptionOrThrow.message, contains("couldn't finish"));
        expect(auth.calls, isNot(contains('signOut')));
      },
    );

    test('refuses to delete an account other than the signed-in one', () async {
      final result = await repo.deleteAccount(
        uid: 'bob',
        providerId: 'google.com',
      );
      expect(result.isErr, isTrue);
      expect(auth.calls, isEmpty);
    });
  });

  group('mapAccountDeletionError — never claims success', () {
    for (final code in [
      'failed-precondition',
      'unauthenticated',
      'unavailable',
      'deadline-exceeded',
      'not-found',
      'internal',
      'unknown',
    ]) {
      test(code, () {
        final msg = mapAccountDeletionError(code).message.toLowerCase();
        expect(msg, isNot(contains('deleted successfully')));
        expect(
          msg,
          anyOf(
            contains('not deleted'),
            contains('sign in'),
            contains("couldn't finish"),
            contains("couldn't confirm"),
          ),
        );
      });
    }

    // After a timeout or dropped connection the server may already have
    // deleted the account, so the client must not claim it wasn't.
    for (final code in ['unavailable', 'deadline-exceeded']) {
      test('$code: honest that the outcome is unknown, and retry is safe', () {
        final msg = mapAccountDeletionError(code).message.toLowerCase();
        expect(msg, contains("couldn't confirm"));
        expect(msg, isNot(contains('not deleted')));
        expect(msg, contains('try again'));
      });
    }
  });
}

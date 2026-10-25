// "Remove saved locations" (audit D-09, Phase 5) against fake_cloud_firestore.
// The security boundary — only the owner, only deleting location fields —
// is enforced by firestore.rules and tested in the emulator suite
// (firestore-tests/test/location_removal.test.mjs); fake_cloud_firestore
// does not evaluate rules.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/repositories/location_history_repository.dart';
import 'package:touchgrass/repositories/memory_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late int commits;

  LocationHistoryRepository repo({
    int pageSize = 200,
    Future<void> Function(WriteBatch b)? commit,
  }) => LocationHistoryRepository(
    db: db,
    pageSize: pageSize,
    // fake_cloud_firestore has no server/cache distinction.
    getOptions: const GetOptions(),
    commitBatch: (b) async {
      commits++;
      await (commit ?? (WriteBatch b) => b.commit())(b);
    },
  );

  String day(int i) =>
      '2026-0${1 + i ~/ 28}-${(1 + i % 28).toString().padLeft(2, '0')}';

  /// A completion + Journal entry pair as the app stores them.
  Future<void> seedAdventure(
    String uid,
    int i, {
    bool withLocation = true,
  }) async {
    final id = '${uid}_${day(i)}';
    await db.collection('completions').doc(id).set({
      'userId': uid,
      'challengeId': day(i),
      'photoUrl': 'https://example.test/$uid/${day(i)}.jpg',
      'xpAwarded': 50,
      'caption': 'walk $i',
      'futureField': 'kept',
      if (withLocation) 'location': const GeoPoint(51.5, -0.12),
    });
    await db.collection('users').doc(uid).collection('memories').doc(id).set({
      'userId': uid,
      'challengeId': day(i),
      'photoUrl': 'https://example.test/$uid/${day(i)}.jpg',
      'xpEarned': 50,
      'caption': 'walk $i',
      'futureField': 'kept',
      if (withLocation) ...{
        'latitude': 51.5,
        'longitude': -0.12,
        'locationName': 'Hyde Park',
        'weatherCondition': 'Clear',
        'weatherEmoji': '☀️',
      },
    });
  }

  Future<void> seedUser(String uid) => db.collection('users').doc(uid).set({
    'uid': uid,
    'xp': 420,
    'streak': 6,
    'totalCompletions': 12,
    'settings': {'locationEnabled': false},
  });

  Future<int> remainingLocations(String uid) async {
    var n = 0;
    final c = await db
        .collection('completions')
        .where('userId', isEqualTo: uid)
        .get();
    n += c.docs.where((d) => d.data().containsKey('location')).length;
    final m = await db
        .collection('users')
        .doc(uid)
        .collection('memories')
        .get();
    n += m.docs
        .where((d) => journalLocationKeys.any(d.data().containsKey))
        .length;
    return n;
  }

  setUp(() {
    db = FakeFirebaseFirestore();
    commits = 0;
  });

  test('removes every location field from the owner\'s completions and '
      'Journal entries, keeping everything else', () async {
    await seedUser('alice');
    for (var i = 0; i < 3; i++) {
      await seedAdventure('alice', i);
    }

    final r = await repo().removeSavedLocations('alice');

    expect(r.status, LocationRemovalStatus.complete);
    expect(r.completionsCleared, 3);
    expect(r.entriesCleared, 3);
    expect(await remainingLocations('alice'), 0);

    final c = (await db.collection('completions').doc('alice_${day(0)}').get())
        .data()!;
    expect(c, {
      'userId': 'alice',
      'challengeId': day(0),
      'photoUrl': 'https://example.test/alice/${day(0)}.jpg',
      'xpAwarded': 50,
      'caption': 'walk 0',
      'futureField': 'kept',
    });
    final m =
        (await db
                .collection('users')
                .doc('alice')
                .collection('memories')
                .doc('alice_${day(0)}')
                .get())
            .data()!;
    expect(m, {
      'userId': 'alice',
      'challengeId': day(0),
      'photoUrl': 'https://example.test/alice/${day(0)}.jpg',
      'xpEarned': 50,
      'caption': 'walk 0',
      'futureField': 'kept',
    });
  });

  test(
    'XP, streak and the profile are untouched; no record is deleted',
    () async {
      await seedUser('alice');
      await seedAdventure('alice', 0);
      final before = (await db.collection('users').doc('alice').get()).data();

      await repo().removeSavedLocations('alice');

      expect((await db.collection('users').doc('alice').get()).data(), before);
      expect((await db.collection('completions').get()).docs, hasLength(1));
      expect(
        (await db.collection('users').doc('alice').collection('memories').get())
            .docs,
        hasLength(1),
      );
    },
  );

  test('never touches another user\'s data', () async {
    await seedUser('alice');
    await seedUser('bob');
    await seedAdventure('alice', 0);
    await seedAdventure('bob', 0);

    await repo().removeSavedLocations('alice');

    expect(await remainingLocations('alice'), 0);
    expect(await remainingLocations('bob'), 2);
  });

  test('documents without a location are left alone (no writes)', () async {
    await seedUser('alice');
    await seedAdventure('alice', 0, withLocation: false);
    await seedAdventure('alice', 1, withLocation: false);

    final r = await repo().removeSavedLocations('alice');

    expect(r.status, LocationRemovalStatus.complete);
    expect(r.completionsCleared + r.entriesCleared, 0);
    expect(commits, 0);
  });

  test('an empty account succeeds with nothing to do', () async {
    final r = await repo().removeSavedLocations('nobody');
    expect(r.isComplete, isTrue);
    expect(commits, 0);
  });

  test('pages through large accounts in bounded batches', () async {
    await seedUser('alice');
    for (var i = 0; i < 23; i++) {
      await seedAdventure('alice', i, withLocation: i.isEven);
    }

    final r = await repo(pageSize: 5).removeSavedLocations('alice');

    expect(r.status, LocationRemovalStatus.complete);
    expect(r.completionsCleared, 12);
    expect(r.entriesCleared, 12);
    expect(await remainingLocations('alice'), 0);
    // ceil(23 / 5) = 5 pages per collection; the first page of each has
    // locations, so at least one batch per collection, never more than 5.
    expect(commits, inInclusiveRange(2, 10));
  });

  test('a failure partway reports "failed", and a retry finishes the job '
      'without damaging anything', () async {
    await seedUser('alice');
    for (var i = 0; i < 6; i++) {
      await seedAdventure('alice', i);
    }
    var calls = 0;
    final failing = repo(
      pageSize: 2,
      commit: (b) async {
        if (++calls == 2) {
          throw FirebaseException(plugin: 'cloud_firestore', code: 'aborted');
        }
        await b.commit();
      },
    );

    final first = await failing.removeSavedLocations('alice');
    expect(first.status, LocationRemovalStatus.failed);
    expect(first.completionsCleared, 2); // the first batch landed
    expect(await remainingLocations('alice'), greaterThan(0));

    final retry = await repo(pageSize: 2).removeSavedLocations('alice');
    expect(retry.status, LocationRemovalStatus.complete);
    expect(retry.completionsCleared, 4); // only what was still left
    expect(retry.entriesCleared, 6);
    expect(await remainingLocations('alice'), 0);
    expect((await db.collection('completions').get()).docs, hasLength(6));
    final c = (await db.collection('completions').doc('alice_${day(0)}').get())
        .data()!;
    expect(c['photoUrl'], 'https://example.test/alice/${day(0)}.jpg');
    expect(c['xpAwarded'], 50);
  });

  test('offline is reported as "offline", never as success', () async {
    await seedUser('alice');
    await seedAdventure('alice', 0);
    final offline = repo(
      commit: (_) async => throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      ),
    );

    final r = await offline.removeSavedLocations('alice');

    expect(r.status, LocationRemovalStatus.offline);
    expect(r.isComplete, isFalse);
    expect(await remainingLocations('alice'), 2);
  });

  test('running it again after success is a safe no-op', () async {
    await seedUser('alice');
    await seedAdventure('alice', 0);
    expect((await repo().removeSavedLocations('alice')).isComplete, isTrue);
    commits = 0;

    final again = await repo().removeSavedLocations('alice');

    expect(again.isComplete, isTrue);
    expect(again.completionsCleared + again.entriesCleared, 0);
    expect(commits, 0);
  });

  test('locations that keep reappearing are reported as incomplete', () async {
    await seedUser('alice');
    await seedAdventure('alice', 0);
    // Simulates another device saving a new located adventure after every
    // batch (the setting still on there).
    var n = 100;
    final r = await repo(
      commit: (b) async {
        await b.commit();
        await seedAdventure('alice', n++ % 50);
      },
    ).removeSavedLocations('alice');

    expect(r.status, LocationRemovalStatus.incomplete);
  });

  test('Journal repair after removal cannot copy a location back', () async {
    await seedUser('alice');
    await seedAdventure('alice', 0);
    // A missing Journal entry that repair would recreate.
    await db
        .collection('users')
        .doc('alice')
        .collection('memories')
        .doc('alice_${day(0)}')
        .delete();
    await db.collection('completions').doc('alice_${day(0)}').update({
      'challengeTitle': 'Find a leaf',
      'challengeCategory': 'nature',
      'verificationResult': {'reason': 'Honor-system approved.'},
      'completedAt': Timestamp.now(),
      'overrideUsed': false,
    });

    expect((await repo().removeSavedLocations('alice')).isComplete, isTrue);
    // Even with the setting on, repair copies from the (now clean) completion.
    final created = await MemoryRepository(
      db: db,
    ).repairMissingEntries(userId: 'alice', includeLocation: true);

    expect(created.valueOrThrow, 1);
    expect(await remainingLocations('alice'), 0);
  });
}

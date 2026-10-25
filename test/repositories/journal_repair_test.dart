// MemoryRepository.repairMissingEntries + journalEntryForCompletion (audit
// D-13) against fake_cloud_firestore. Create-only enforcement under
// concurrency is covered by firestore-tests/test/journal_location.test.mjs.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/models/challenge_model.dart';
import 'package:touchgrass/models/completion_model.dart';
import 'package:touchgrass/repositories/memory_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MemoryRepository repo;
  const uid = 'alice';

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = MemoryRepository(db: db);
  });

  /// A completion as stored, [daysAgo] days back.
  Future<void> completion(
    int daysAgo, {
    String user = uid,
    int xp = 50,
    bool withLocation = true,
  }) {
    final at = DateTime(2026, 10, 17 - daysAgo, 12);
    final day = ChallengeModel.docIdForDate(at);
    return db.collection('completions').doc('${user}_$day').set({
      'userId': user,
      'challengeId': day,
      'challengeTitle': 'Find a leaf',
      'challengeEmoji': '🍃',
      'challengeCategory': 'nature',
      'photoUrl':
          'https://firebasestorage.googleapis.com/v0/b/b/o/completion_photos%2F$user%2F$day.jpg',
      'verificationResult': {'reason': 'Honor-system approved.'},
      'completedAt': Timestamp.fromDate(at),
      'xpAwarded': xp,
      'overrideUsed': false,
      'caption': 'caption $day',
      if (withLocation) 'location': const GeoPoint(30.2, -97.7),
    });
  }

  Future<Map<String, Map<String, dynamic>>> entries([String user = uid]) async {
    final snap = await db.collection('users/$user/memories').get();
    return {for (final d in snap.docs) d.id: d.data()};
  }

  test(
    'creates the missing entries, mirroring each completion exactly',
    () async {
      await completion(0);
      await completion(1, xp: 0);
      await db.collection('users/$uid/challenges').doc('2026-10-17').set({
        'dayNumber': 9,
      });

      final created = (await repo.repairMissingEntries(
        userId: uid,
        includeLocation: true,
      )).valueOrThrow;
      expect(created, 2);
      final e = await entries();
      expect(e.keys, containsAll(['${uid}_2026-10-17', '${uid}_2026-10-16']));
      final today = e['${uid}_2026-10-17']!;
      expect(today['photoUrl'], contains('2026-10-17.jpg'));
      expect(today['xpEarned'], 50);
      expect(today['caption'], 'caption 2026-10-17');
      expect(today['challengeDay'], 9);
      expect(today['verificationMethod'], 'auto_approved');
      expect(
        e['${uid}_2026-10-16']!['xpEarned'],
        0,
        reason: 'never shows XP that was not granted',
      );
      expect(
        e['${uid}_2026-10-16']!['challengeDay'],
        0,
        reason: 'challenge gone → badge hidden',
      );
    },
  );

  test(
    'is idempotent: a second run creates nothing and changes nothing',
    () async {
      await completion(0);
      await repo.repairMissingEntries(userId: uid, includeLocation: true);
      final before = await entries();
      final again = (await repo.repairMissingEntries(
        userId: uid,
        includeLocation: true,
      )).valueOrThrow;
      expect(again, 0);
      expect(await entries(), before);
    },
  );

  test(
    'never touches an existing entry (e.g. one whose caption was edited)',
    () async {
      await completion(0);
      await db.collection('users/$uid/memories').doc('${uid}_2026-10-17').set({
        'caption': 'edited',
        'userId': uid,
      });
      expect(
        (await repo.repairMissingEntries(
          userId: uid,
          includeLocation: true,
        )).valueOrThrow,
        0,
      );
      expect((await entries())['${uid}_2026-10-17']!['caption'], 'edited');
    },
  );

  test('never writes completions, the user document, or XP', () async {
    await completion(0);
    await repo.repairMissingEntries(userId: uid, includeLocation: true);
    expect((await db.collection('completions').get()).size, 1);
    expect((await db.collection('users').doc(uid).get()).exists, isFalse);
  });

  test(
    'includes coordinates only when the location setting allows it (D-09)',
    () async {
      await completion(0);
      await repo.repairMissingEntries(userId: uid, includeLocation: false);
      final e = (await entries())['${uid}_2026-10-17']!;
      expect(e.containsKey('latitude'), isFalse);
      expect(e.containsKey('longitude'), isFalse);

      final db2 = FakeFirebaseFirestore();
      final repo2 = MemoryRepository(db: db2);
      db = db2;
      await completion(0);
      await repo2.repairMissingEntries(userId: uid, includeLocation: true);
      expect((await entries())['${uid}_2026-10-17']!['latitude'], 30.2);
    },
  );

  test('only repairs the caller\'s own completions', () async {
    await completion(0, user: 'bob');
    expect(
      (await repo.repairMissingEntries(
        userId: uid,
        includeLocation: true,
      )).valueOrThrow,
      0,
    );
    expect(await entries('bob'), isEmpty);
  });

  test(
    'checks the most recent ${MemoryRepository.repairScanLimit} completions',
    () async {
      for (var i = 0; i < MemoryRepository.repairScanLimit + 5; i++) {
        await completion(i, withLocation: false);
      }
      final created = (await repo.repairMissingEntries(
        userId: uid,
        includeLocation: false,
      )).valueOrThrow;
      expect(created, MemoryRepository.repairScanLimit);
      expect(
        (await entries()).keys,
        contains('${uid}_2026-10-17'),
        reason: 'newest first',
      );
    },
  );

  test(
    'journalEntryForCompletion drops place and weather without a location',
    () {
      final c = CompletionModel(
        id: '${uid}_2026-10-17',
        userId: uid,
        challengeId: '2026-10-17',
        challengeTitle: 't',
        challengeEmoji: 'e',
        challengeCategory: ChallengeCategory.nature,
        photoUrl: 'p',
        verificationResult: const {'reason': 'r'},
        completedAt: DateTime(2026, 10, 17),
        xpAwarded: 25,
        overrideUsed: true,
        location: const GeoPoint(1, 2),
      );
      final off = journalEntryForCompletion(
        c,
        challengeDay: 1,
        includeLocation: false,
        locationName: 'Park',
        weatherCondition: 'Clear',
        weatherEmoji: '☀️',
      );
      expect([
        off.latitude,
        off.locationName,
        off.weatherCondition,
        off.weatherEmoji,
      ], everyElement(isNull));
      expect(off.verificationMethod, 'manual_override');
      final on = journalEntryForCompletion(
        c,
        challengeDay: 1,
        includeLocation: true,
        locationName: 'Park',
      );
      expect(on.latitude, 1);
      expect(on.locationName, 'Park');
    },
  );
}

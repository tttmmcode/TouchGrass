// FeedbackRepository (audit N-1). Authorization (create-only, own uid,
// fixed fields, bounded message, daily cap, no reads) is enforced by
// firestore.rules and covered in firestore-tests/test/feedback.test.mjs;
// these tests cover the client: validation, payload shape, slot claiming.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/core/errors/app_exception.dart';
import 'package:touchgrass/repositories/feedback_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late FeedbackRepository repo;
  final now = DateTime.utc(2026, 10, 17, 9);

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = FeedbackRepository(db: db);
  });

  group('submit', () {
    test(
      'stores exactly the fields the rules allow, under a daily slot ID',
      () async {
        final result = await repo.submit(
          userId: 'alice',
          type: FeedbackType.bug,
          message: '  The map is blank  ',
          now: now,
        );
        expect(result.isOk, isTrue);
        final docs = (await db.collection('feedback').get()).docs;
        expect(docs.single.id, 'alice_2026-10-17_1');
        final data = docs.single.data();
        expect(data.keys.toSet(), {
          'type',
          'message',
          'userId',
          'createdAt',
          'appVersion',
        });
        expect(data['type'], 'bug');
        expect(data['message'], 'The map is blank', reason: 'trimmed');
        expect(data['userId'], 'alice');
        expect(data['createdAt'], isA<Timestamp>());
      },
    );

    test(
      'a signed-out user gets a clear error and nothing is written',
      () async {
        final result = await repo.submit(
          userId: null,
          type: FeedbackType.feedback,
          message: 'hi',
          now: now,
        );
        expect(result.exceptionOrThrow.message, contains('sign in'));
        expect((await db.collection('feedback').get()).size, 0);
      },
    );

    test(
      'an empty / whitespace-only message is rejected before any write',
      () async {
        final result = await repo.submit(
          userId: 'alice',
          type: FeedbackType.feedback,
          message: '   ',
          now: now,
        );
        expect(result.isErr, isTrue);
        expect((await db.collection('feedback').get()).size, 0);
      },
    );

    test(
      'a message over the limit is rejected before any write (boundary)',
      () async {
        final tooLong = 'x' * (FeedbackRepository.maxMessageLength + 1);
        final result = await repo.submit(
          userId: 'alice',
          type: FeedbackType.feedback,
          message: tooLong,
          now: now,
        );
        expect(result.isErr, isTrue);
        expect((await db.collection('feedback').get()).size, 0);
      },
    );

    test('a message exactly at the limit is accepted (boundary)', () async {
      final atLimit = 'x' * FeedbackRepository.maxMessageLength;
      final result = await repo.submit(
        userId: 'alice',
        type: FeedbackType.feedback,
        message: atLimit,
        now: now,
      );
      expect(result.isOk, isTrue);
    });
  });

  group('claimFeedbackSlot', () {
    test('takes the first free slot of the day', () async {
      final taken = {'alice_2026-10-17_1', 'alice_2026-10-17_2'};
      final id = await claimFeedbackSlot(
        userId: 'alice',
        day: '2026-10-17',
        tryCreate: (id) async => !taken.contains(id),
      );
      expect(id, 'alice_2026-10-17_3');
    });

    test('returns null once all daily slots are used (cap boundary)', () async {
      final tried = <String>[];
      final id = await claimFeedbackSlot(
        userId: 'alice',
        day: '2026-10-17',
        tryCreate: (id) async {
          tried.add(id);
          return false;
        },
      );
      expect(id, isNull);
      expect(tried.length, FeedbackRepository.maxPerDay);
      expect(tried.last, 'alice_2026-10-17_${FeedbackRepository.maxPerDay}');
    });
  });

  test('validateFeedbackMessage throws a friendly DataException', () {
    expect(() => validateFeedbackMessage(''), throwsA(isA<DataException>()));
  });

  test('utcDateKey is zero-padded yyyy-MM-dd', () {
    expect(utcDateKey(DateTime.utc(2026, 3, 5)), '2026-03-05');
  });
}

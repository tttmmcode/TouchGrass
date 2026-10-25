// Drift guard between the app's composite Firestore queries and
// firestore.indexes.json (Phase 7A).
//
// Production had NO composite indexes deployed (read-only check,
// 2026-10-19) and firebase.json didn't reference the index file, so no
// deploy would ever have created them. A query that needs a missing
// composite index fails in production with FAILED_PRECONDITION — and the
// emulators don't enforce indexes, so no other test catches it.
//
// Queries covered (equality on one field + orderBy on another):
//   completions: userId == uid, orderBy completedAt desc
//     - CompletionRepository.latestCompletedAt (saving a completion for an
//       account without lastCompletionDate)
//     - MemoryRepository.repairMissingEntries (Journal repair)
//     - ChallengeRepository.watchRecentCompletions (home path)

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final firebaseJson =
      jsonDecode(File('firebase.json').readAsStringSync())
          as Map<String, dynamic>;
  final indexes =
      (jsonDecode(File('firestore.indexes.json').readAsStringSync())
              as Map<String, dynamic>)['indexes']
          as List<dynamic>;

  bool hasIndex(String group, List<List<String>> fields) => indexes.any((i) {
    final m = i as Map<String, dynamic>;
    final f = (m['fields'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((x) => x['fieldPath'] != '__name__')
        .map((x) => [x['fieldPath'] as String, x['order'] as String])
        .toList();
    return m['collectionGroup'] == group &&
        (m['queryScope'] ?? 'COLLECTION') == 'COLLECTION' &&
        f.length == fields.length &&
        Iterable<int>.generate(
          f.length,
        ).every((k) => f[k][0] == fields[k][0] && f[k][1] == fields[k][1]);
  });

  test('firebase.json deploys firestore.indexes.json', () {
    final firestore = firebaseJson['firestore'] as Map<String, dynamic>;
    expect(firestore['indexes'], 'firestore.indexes.json');
  });

  test('completions (userId ASC, completedAt DESC) is defined', () {
    expect(
      hasIndex('completions', [
        ['userId', 'ASCENDING'],
        ['completedAt', 'DESCENDING'],
      ]),
      isTrue,
    );
  });

  test('the queries that need it still have that shape', () {
    String src(String path) => File(path).readAsStringSync();
    final shape = RegExp(
      r"""where\('userId', isEqualTo: \w+\)\s*\.orderBy\('completedAt', descending: true\)""",
    );
    expect(
      shape.hasMatch(src('lib/repositories/completion_repository.dart')),
      isTrue,
    );
    expect(
      shape.hasMatch(src('lib/repositories/memory_repository.dart')),
      isTrue,
    );
    final home = src('lib/repositories/challenge_repository.dart');
    expect(
      home,
      contains(
        "filters: [QueryFilter(field: 'userId', isEqualTo: uid)],\n"
        "          orderByField: 'completedAt',\n"
        '          descending: true,',
      ),
    );
  });
}

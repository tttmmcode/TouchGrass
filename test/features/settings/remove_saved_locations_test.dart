// "Remove saved locations" UI (audit D-09, Phase 5): cancel is safe, success
// is only claimed when the repository verified it, failures say that some
// locations may remain and offer a retry.

import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/core/constants/privacy_copy.dart';
import 'package:touchgrass/features/settings/widgets/remove_saved_locations.dart';
import 'package:touchgrass/repositories/location_history_repository.dart';

class _ScriptedRepo extends LocationHistoryRepository {
  _ScriptedRepo(this.results) : super(db: FakeFirebaseFirestore());
  final List<LocationRemovalResult> results;
  int calls = 0;
  Completer<void>? gate;

  @override
  Future<LocationRemovalResult> removeSavedLocations(String userId) async {
    calls++;
    await gate?.future;
    return results[calls - 1];
  }
}

LocationRemovalResult _r(LocationRemovalStatus s, [int c = 0, int e = 0]) =>
    LocationRemovalResult(s, completionsCleared: c, entriesCleared: e);

void main() {
  late int changed;

  Future<void> open(
    WidgetTester tester,
    _ScriptedRepo repo, {
    bool settingOn = false,
  }) async {
    changed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => confirmAndRemoveSavedLocations(
                context,
                uid: 'alice',
                locationSettingOn: settingOn,
                repository: repo,
                onChanged: () => changed++,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the confirmation explains what is and is not removed', (
    tester,
  ) async {
    await open(tester, _ScriptedRepo([]), settingOn: true);
    expect(find.text(PrivacyCopy.removeLocationsDialogTitle), findsOneWidget);
    final body = PrivacyCopy.removeLocationsBody(settingOn: true);
    expect(find.text(body), findsOneWidget);
    for (final mention in [
      'permanently',
      "can't be undone",
      'Journal entries, photos, captions, XP, streak',
      'still on',
      'internet connection',
      'safely try again',
      'inside the image file',
    ]) {
      expect(body, contains(mention));
    }
    expect(
      PrivacyCopy.removeLocationsBody(settingOn: false),
      isNot(contains('still on')),
    );
  });

  testWidgets('Cancel changes nothing', (tester) async {
    final repo = _ScriptedRepo([]);
    await open(tester, repo);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.calls, 0);
    expect(changed, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('shows progress while running, then confirms success', (
    tester,
  ) async {
    final repo = _ScriptedRepo([_r(LocationRemovalStatus.complete, 3, 3)])
      ..gate = Completer<void>();
    await open(tester, repo);
    await tester.tap(find.text('Remove'));
    await tester.pump();
    expect(find.text(PrivacyCopy.removeLocationsProgress), findsOneWidget);
    // Not dismissible while running: tapping outside does nothing.
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(find.text(PrivacyCopy.removeLocationsProgress), findsOneWidget);

    repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text(PrivacyCopy.removeLocationsProgress), findsNothing);
    expect(
      find.text(PrivacyCopy.removeLocationsDone(anyRemoved: true)),
      findsOneWidget,
    );
    expect(repo.calls, 1);
    expect(changed, 1);
  });

  testWidgets('nothing to remove says so', (tester) async {
    final repo = _ScriptedRepo([_r(LocationRemovalStatus.complete)]);
    await open(tester, repo);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(
      find.text(PrivacyCopy.removeLocationsDone(anyRemoved: false)),
      findsOneWidget,
    );
    expect(changed, 0);
  });

  for (final (status, message) in [
    (LocationRemovalStatus.offline, PrivacyCopy.removeLocationsOffline),
    (LocationRemovalStatus.failed, PrivacyCopy.removeLocationsFailed),
    (LocationRemovalStatus.incomplete, PrivacyCopy.removeLocationsIncomplete),
  ]) {
    testWidgets('${status.name}: says some may remain, never claims success, '
        'and Try again re-runs it', (tester) async {
      final repo = _ScriptedRepo([
        _r(status, 1, 0),
        _r(LocationRemovalStatus.complete, 2, 3),
      ]);
      await open(tester, repo);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.text(PrivacyCopy.removeLocationsFailedTitle), findsOneWidget);
      expect(find.text(message), findsOneWidget);
      expect(message, contains('may'));
      expect(
        find.text(PrivacyCopy.removeLocationsDone(anyRemoved: true)),
        findsNothing,
      );
      expect(changed, 1, reason: 'partial progress still refreshes caches');

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(repo.calls, 2);
      expect(
        find.text(PrivacyCopy.removeLocationsDone(anyRemoved: true)),
        findsOneWidget,
      );
    });
  }

  testWidgets('Close after a failure stops without retrying', (tester) async {
    final repo = _ScriptedRepo([_r(LocationRemovalStatus.failed)]);
    await open(tester, repo);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(repo.calls, 1);
    expect(find.byType(AlertDialog), findsNothing);
  });
}

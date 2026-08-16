// Widget tests for maybeShowPermissionPrimer — the one-time-ever contextual
// explanation shown immediately before each of camera/location/notification
// permission is first requested. Covers the two properties that matter:
// the dialog actually explains the right thing, and it never nags twice.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:touchgrass/widgets/permission_primer.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the correct explanation for the given permission', (
    tester,
  ) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    unawaited(
      maybeShowPermissionPrimer(capturedContext, PermissionPrimerKind.camera),
    );
    await tester.pumpAndSettle();

    expect(
      find.text("Use your camera to capture today's adventure."),
      findsOneWidget,
    );
  });

  testWidgets('never shows a second time for the same permission', (
    tester,
  ) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    // First call: shows and is dismissed via Continue.
    unawaited(
      maybeShowPermissionPrimer(capturedContext, PermissionPrimerKind.location),
    );
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Second call: already marked shown — must not show again.
    unawaited(
      maybeShowPermissionPrimer(capturedContext, PermissionPrimerKind.location),
    );
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsNothing);
  });

  testWidgets(
    'different permissions are tracked independently — priming one does '
    "not suppress another's explanation",
    (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      unawaited(
        maybeShowPermissionPrimer(
          capturedContext,
          PermissionPrimerKind.notifications,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      unawaited(
        maybeShowPermissionPrimer(capturedContext, PermissionPrimerKind.camera),
      );
      await tester.pumpAndSettle();
      expect(
        find.text("Use your camera to capture today's adventure."),
        findsOneWidget,
      );
    },
  );
}

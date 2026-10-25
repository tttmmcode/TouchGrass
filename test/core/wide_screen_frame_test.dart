// Phase 8: on wide (desktop) windows the app is shown in a centered column
// no wider than a large phone, and every screen measures that column.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/main.dart';

Future<double> _seenWidth(WidgetTester tester, Size window) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  double? seen;
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => wideScreenFrame(context, child!),
      home: Builder(
        builder: (context) {
          seen = MediaQuery.sizeOf(context).width;
          return const Scaffold(body: Text('screen'));
        },
      ),
    ),
  );
  return seen!;
}

void main() {
  testWidgets('a desktop window shows a centered phone-width column', (
    tester,
  ) async {
    expect(await _seenWidth(tester, const Size(1280, 900)), maxAppWidth);
    expect(tester.getSize(find.byType(Scaffold)).width, maxAppWidth);
    final left = tester.getTopLeft(find.byType(Scaffold)).dx;
    expect(left, (1280 - maxAppWidth) / 2);
  });

  testWidgets('phones are unchanged', (tester) async {
    expect(await _seenWidth(tester, const Size(390, 844)), 390);
    expect(await _seenWidth(tester, const Size(600, 900)), 600);
  });
}

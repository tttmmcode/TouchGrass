// Phase 8: the Settings switches were announced by screen readers with no
// name ("switch, on"); the title sat in a separate node. The row is now one
// node, so the switch carries its title and subtitle.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/features/settings/screens/settings_screen.dart';

void main() {
  testWidgets('the switch is announced with its title and subtitle', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final changes = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsToggleTile(
            icon: Icons.leaderboard_outlined,
            iconColor: Colors.green,
            title: 'Show on Leaderboard',
            subtitle: 'Appear in league rankings',
            value: true,
            isDark: false,
            onChanged: changes.add,
          ),
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(Switch));
    expect(node.label, contains('Show on Leaderboard'));
    expect(node.label, contains('Appear in league rankings'));
    expect(
      node,
      matchesSemantics(
        hasToggledState: true,
        isToggled: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
        label: node.label,
      ),
    );

    // A screen reader's activation of the named node toggles the switch.
    tester.semantics.tap(find.semantics.byLabel(RegExp('Show on Leaderboard')));
    await tester.pump();
    expect(changes, [false]);
    handle.dispose();
  });
}

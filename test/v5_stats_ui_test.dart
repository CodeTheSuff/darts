import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:darts_counter/ui/stats_screen.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Statistik: Spieler, Verlauf, Historie, Detail, Doppel, Erfolge, Direktvergleich', (t) async {
    SharedPreferences.setMockInitialValues({'sound': false});
    await Store.init();
    ThemeHost.apply(palettes.first);
    t.view.physicalSize = const Size(412, 915) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final a = Store.ensureProfile('Simon');
    final b = Store.ensureProfile('Max');
    for (var k = 0; k < 3; k++) {
      final c = MatchController(
        config: const GameConfig('x01', {'start': 101, 'doubleOut': true, 'legs': 1}),
        players: [GamePlayer(a.id, a.name, 0xFF5AA9FF), GamePlayer(b.id, b.name, 0xFFF5C84C)],
      );
      for (final d in const [Dart(20, 1), Dart(20, 1), Dart(1, 1), Dart(0, 1), Dart(0, 1), Dart(0, 1)]) {
        c.throwDart(d);
      }
      for (final d in const [Dart(20, 2), Dart(0, 1), Dart(10, 2)]) {
        c.throwDart(d);
      }
      c.commitStats();
    }
    await t.pumpWidget(MaterialApp(theme: buildTheme(C.p), home: const StatsScreen()));
    await t.pumpAndSettle();
    expect(find.text('Direktvergleich'), findsOneWidget);
    await t.tap(find.text('Simon'));
    await t.pumpAndSettle();
    expect(find.text('Verlauf'.toUpperCase()), findsOneWidget);
    await t.tap(find.text('30 Tage'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Match-Historie'), 300, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Match-Historie'));
    await t.pumpAndSettle();
    expect(find.text('gegen Max'), findsNWidgets(3));
    await t.tap(find.text('gegen Max').first);
    await t.pumpAndSettle();
    expect(find.text('LEG 1'), findsOneWidget);
    expect(find.text('Check'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.text('Doppel-Analyse'));
    await t.pumpAndSettle();
    expect(find.textContaining('Treffer bei'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Erfolge'), 300, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Erfolge'));
    await t.pumpAndSettle();
    expect(find.text('Erster Sieg'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.text('Direktvergleich'));
    await t.pumpAndSettle();
    expect(find.text('3 Matches · Siege'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}

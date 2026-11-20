import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/data/sync.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/main.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:darts_counter/ui/game_screen.dart';
import 'package:darts_counter/ui/share_screens.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _setup(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'onboarded': true, 'seenVersion': '2.9.2', 'sound': false});
  await Store.init();
  ThemeHost.apply(palettes.first);
  tester.view.physicalSize = const Size(412, 915) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _steps(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Widget _app(Widget home) => MaterialApp(theme: buildTheme(palettes.first), home: home);

void main() {
  testWidgets('Spiel-Tab: Kacheln X01 und Turnier, Turnier-Übersicht öffnet sich', (tester) async {
    await _setup(tester);
    await tester.pumpWidget(const DartsApp());
    await tester.pumpAndSettle();
    expect(find.text('X01'), findsOneWidget);
    expect(find.text('Match starten'), findsNothing);
    await tester.tap(find.text('Turnier'));
    await tester.pumpAndSettle();
    expect(find.text('Neues Turnier'), findsOneWidget);
    await tester.tap(find.text('Neues Turnier'));
    await tester.pumpAndSettle();
    expect(find.text('Name des Turniers'), findsOneWidget);
  });

  testWidgets('Gast-Spiel: Würfe vom Host erscheinen mit Animation', (tester) async {
    await _setup(tester);
    final ctl = MatchController(
      config: const GameConfig('x01', {'start': 501, 'doubleOut': true, 'legs': 1}),
      players: const [GamePlayer('a', 'Simon', 0xFF5AA9FF), GamePlayer('b', 'Max', 0xFFF5C84C)],
    )..remote = true;
    await tester.pumpWidget(_app(GameScreen(controller: ctl)));
    await tester.pump();
    expect(find.text('501'), findsWidgets);
    // Host meldet drei Würfe (T20 T20 T20)
    ctl.applyRemote(const [Dart(20, 3), Dart(20, 3), Dart(20, 3)]);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('ONE HUNDRED AND EIGHTY'), findsOneWidget);
    await _steps(tester, 20);
    expect(find.text('321'), findsWidgets);
    // Undo auf einem anderen Gerät → kompletter Neuaufbau
    ctl.applyRemote(const [Dart(20, 3), Dart(20, 3)]);
    await _steps(tester, 3);
    expect(find.text('381'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await _steps(tester, 2);
  });

  testWidgets('Teilen und Import-Vorschau', (tester) async {
    await _setup(tester);
    Store.ensureProfile('Simon');
    Store.ensureProfile('Max');
    await tester.pumpWidget(_app(const ShareScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Als Datei teilen'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(find.text('Max'));
    await tester.pump();
    expect(find.text('1 / 2'), findsOneWidget);

    final pkg = SharePackage(
      device: 'x',
      deviceName: 'Handy von Tom',
      created: DateTime(2026),
      profiles: const [Profile('r1', 'Simon'), Profile('r2', 'Tom')],
      entries: [
        LogEntry(rid: 'm1', oid: 'r1', pid: 'r1', t: 1, mode: 'x01', d: PlayerStats()..x01.matches = 1),
        LogEntry(rid: 'm1', oid: 'r2', pid: 'r2', t: 1, mode: 'x01', d: PlayerStats()..x01.matches = 1),
      ],
      tournaments: const [],
    );
    await tester.pumpWidget(_app(ImportPreviewScreen(pkg: pkg)));
    await tester.pumpAndSettle();
    expect(find.text('Von Handy von Tom'), findsOneWidget);
    expect(find.text('mit Simon'), findsOneWidget); // Vorschlag: zusammenführen
    expect(find.text('Neu anlegen'), findsOneWidget); // Tom ist neu
    await tester.tap(find.bySemanticsLabel('Übernehmen'));
    await tester.pumpAndSettle();
    final simon = Store.profiles.firstWhere((p) => p.name == 'Simon');
    expect(Store.statsFor(simon.id).x01.matches, 1);
    expect(Store.profiles.any((p) => p.name == 'Tom'), isTrue);
  });

  testWidgets('Koppeln-Bildschirm öffnet sich', (tester) async {
    await _setup(tester);
    await tester.pumpWidget(const DartsApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Handys koppeln'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(tester.takeException(), isNull);
    expect(find.text('Raum eröffnen'), findsOneWidget);
    expect(find.text('Adresse und Code eingeben'), findsOneWidget);
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 500));
  });
}

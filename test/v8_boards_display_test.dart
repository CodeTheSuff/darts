// Anzeigegerät mit mehreren gleichzeitig laufenden Spielen („Scheiben“).
import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:darts_counter/ui/board_grid.dart';
import 'package:darts_counter/ui/link_coordinator.dart';
import 'package:darts_counter/ui/scoreboard_screen.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const pA = GamePlayer('a', 'Simon', 0xFF5AA9FF);
const pB = GamePlayer('b', 'Max', 0xFFF5C84C);
const pC = GamePlayer('c', 'Lena', 0xFF7BE07B);
const pD = GamePlayer('d', 'Tom', 0xFFFF7A7A);

Future<void> _setup(WidgetTester t, {Size size = const Size(1280, 800), Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues({'sound': false, ...prefs});
  await Store.init();
  ThemeHost.apply(palettes.first);
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
}

Future<void> _steps(WidgetTester t, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

MatchController _match(List<GamePlayer> players, {List<Dart> darts = const []}) {
  final c = MatchController(
    config: const GameConfig('x01', {'start': 501, 'doubleOut': true, 'legs': 3}),
    players: players,
  );
  for (final d in darts) {
    c.throwDart(d);
  }
  return c;
}

Map<String, dynamic> _state(List<MatchController> boards) => {
  'match': boards.first.toJson(),
  'boards': [
    for (var i = 0; i < boards.length; i++) {'n': i + 1, 'name': 'Scheibe ${i + 1}', 'match': boards[i].toJson()},
  ],
};

void main() {
  for (final size in const [Size(1280, 800), Size(412, 915)]) {
    testWidgets('Anzeige mit 2 Scheiben: Raster, Auswahl, Fortschreiben (${size.width.toInt()}×${size.height.toInt()})', (
      t,
    ) async {
      await _setup(t, size: size);
      final b1 = _match(const [pA, pB], darts: const [Dart(20, 3), Dart(20, 3), Dart(20, 1)]);
      final b2 = _match(const [pC, pD]);
      LinkCoordinator.viewerState.value = _state([b1, b2]);
      await t.pumpWidget(MaterialApp(theme: buildTheme(C.p), home: const ScoreboardScreen()));
      await _steps(t);

      // Leiste mit „Alle“, „Scheibe 1“, „Scheibe 2“ und geteilter Bildschirm
      expect(find.byKey(const ValueKey('board-chip-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('board-chip-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('board-chip-2')), findsOneWidget);
      expect(find.text('Alle'), findsOneWidget);
      expect(find.byType(BoardTile), findsNWidgets(2));
      expect(find.text('SCHEIBE 1'), findsOneWidget);
      expect(find.text('SCHEIBE 2'), findsOneWidget);
      for (final n in ['Simon', 'Max', 'Lena', 'Tom']) {
        expect(find.text(n), findsOneWidget);
      }
      expect(find.text('361'), findsOneWidget);
      expect(t.takeException(), isNull);

      // Auf Scheibe 2 wechseln: gespeichert, Vollbild nur dieses Spiels
      // (Test-Schrift ist breiter – auf dem Handy ggf. erst hinscrollen)
      await t.ensureVisible(find.byKey(const ValueKey('board-chip-2')));
      await _steps(t, 2);
      await t.tap(find.byKey(const ValueKey('board-chip-2')));
      await _steps(t);
      expect(Store.viewerBoard, 2);
      expect(find.byType(BoardTile), findsNothing);
      expect(find.text('Lena'), findsOneWidget);
      expect(find.text('Simon'), findsNothing);
      expect(find.text('SCHEIBE 2'), findsOneWidget); // Hinweis neben dem Modus
      expect(find.text('501'), findsNWidgets(2));

      // Neuer Stand: ein Dart auf Scheibe 2
      b2.throwDart(const Dart(20, 3));
      LinkCoordinator.viewerState.value = _state([b1, b2]);
      await _steps(t);
      expect(find.text('441'), findsOneWidget);
      expect(find.text('T20'), findsOneWidget);
      expect(t.takeException(), isNull);

      // Zurück zu „Alle“
      await t.ensureVisible(find.byKey(const ValueKey('board-chip-0')));
      await _steps(t, 2);
      await t.tap(find.byKey(const ValueKey('board-chip-0')));
      await _steps(t);
      expect(Store.viewerBoard, 0);
      expect(find.byType(BoardTile), findsNWidgets(2));
      expect(find.text('441'), findsOneWidget);
      expect(t.takeException(), isNull);

      await t.pumpWidget(const SizedBox());
      await _steps(t, 2);
    });
  }

  testWidgets('Gewählte Scheibe fehlt → „Alle“; eine Scheibe → Vollbild ohne Leiste; ohne boards wie bisher', (t) async {
    await _setup(t, prefs: {'viewerBoard': 3});
    final b1 = _match(const [pA, pB]);
    final b2 = _match(const [pC, pD]);
    LinkCoordinator.viewerState.value = _state([b1, b2]);
    await t.pumpWidget(MaterialApp(theme: buildTheme(C.p), home: const ScoreboardScreen()));
    await _steps(t);
    expect(find.byType(BoardTile), findsNWidgets(2));
    expect(Store.viewerBoard, 3); // Wert bleibt erhalten

    LinkCoordinator.viewerState.value = _state([b2]);
    await _steps(t);
    expect(find.byType(BoardTile), findsNothing);
    expect(find.byKey(const ValueKey('board-chip-0')), findsNothing);
    expect(find.text('Lena'), findsOneWidget);

    // Ohne boards: das Match des Host-Geräts
    LinkCoordinator.viewerState.value = {'match': b1.toJson(), 'boards': const []};
    await _steps(t);
    expect(find.text('Simon'), findsOneWidget);
    expect(find.text('Lena'), findsNothing);
    expect(t.takeException(), isNull);

    await t.pumpWidget(const SizedBox());
    await _steps(t, 2);
  });
}

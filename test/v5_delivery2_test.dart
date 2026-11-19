import 'package:darts_counter/data/caller.dart';
import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/games/tournament.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:darts_counter/ui/game_screen.dart';
import 'package:darts_counter/ui/link_coordinator.dart';
import 'package:darts_counter/ui/scoreboard_screen.dart';
import 'package:darts_counter/ui/share_card.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const pA = GamePlayer('a', 'Simon', 0xFF5AA9FF);
const pB = GamePlayer('b', 'Max', 0xFFF5C84C);

Future<void> _setup(WidgetTester t, {Size size = const Size(412, 915), Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues({'sound': false, ...prefs});
  await Store.init();
  ThemeHost.apply(palettes.first);
  t.view.physicalSize = size * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

Future<void> _steps(WidgetTester t, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

MatchController _match({List<Dart> darts = const []}) {
  final c = MatchController(
    config: const GameConfig('x01', {'start': 501, 'doubleOut': true, 'format': 'sets', 'sets': 2, 'legs': 3}),
    players: const [pA, pB],
  );
  for (final d in darts) {
    c.throwDart(d);
  }
  return c;
}

void main() {
  test('Caller: Ansagen auf Englisch und Deutsch', () {
    expect(Caller.phraseFor(180), 'One hundred and eighty!');
    expect(Caller.phraseFor(180, lang: 'de'), 'Hundertachtzig!');
    expect(Caller.phraseFor(60), '60');
    expect(Caller.phraseFor(45, bust: true), 'No score');
    expect(Caller.phraseFor(0, lang: 'de'), 'Kein Score');
  });

  testWidgets('Caller an: Spiel läuft ohne Fehler, auch ohne Sprachausgabe', (t) async {
    await _setup(t, prefs: {'caller': true, 'sound': true});
    final c = _match();
    await t.pumpWidget(MaterialApp(theme: buildTheme(C.p), home: GameScreen(controller: c)));
    await _steps(t, 2);
    for (var i = 0; i < 3; i++) {
      await t.tap(find.byWidgetPredicate((w) => w is Key3 && w.semantics == '20'));
      await t.pump(const Duration(milliseconds: 100));
    }
    await _steps(t, 8);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await _steps(t, 2);
  });

  for (final size in const [Size(412, 915), Size(915, 412)]) {
    testWidgets('Scoreboard zeigt Match und Turnier (${size.width.toInt()}×${size.height.toInt()})', (t) async {
      await _setup(t, size: size);
      LinkCoordinator.viewerState.value = null;
      await t.pumpWidget(MaterialApp(theme: buildTheme(C.p), home: const ScoreboardScreen()));
      await _steps(t, 2);
      expect(find.text('Scoreboard'), findsOneWidget);
      final c = _match(darts: const [Dart(20, 3), Dart(20, 3), Dart(20, 1)]);
      LinkCoordinator.viewerState.value = {'match': c.toJson()};
      await _steps(t, 2);
      expect(find.text('361'), findsOneWidget);
      expect(find.text('501'), findsOneWidget);
      final tour = Tournament(
        id: 't',
        name: 'Abend',
        created: DateTime(2026),
        system: TSystem.ko,
        players: [for (final n in ['A', 'B', 'C', 'D', 'E']) TPlayer(n, n)],
        start: 501,
        doubleOut: true,
        formats: const {},
      )..build();
      LinkCoordinator.viewerState.value = {'tournament': tour.toJson()};
      await _steps(t, 2);
      expect(find.text('Abend'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await _steps(t, 2);
    });
  }

  testWidgets('Ergebniskarten für Match und Turnier', (t) async {
    await _setup(t);
    final c = MatchController(
      config: const GameConfig('x01', {'start': 101, 'doubleOut': true, 'legs': 1}),
      players: const [pA, pB],
    );
    for (final d in const [Dart(20, 3), Dart(1, 1), Dart(20, 2)]) {
      c.throwDart(d);
    }
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(C.p),
      home: ShareCardScreen(card: MatchShareCard(engine: c.engine, date: DateTime(2026, 11, 19)), fileName: 'x.png'),
    ));
    await _steps(t, 2);
    expect(find.text('Simon'), findsWidgets);
    expect(find.text('SIEG'), findsOneWidget);
    final tour = Tournament(
      id: 't',
      name: 'Liga',
      created: DateTime(2026),
      system: TSystem.league,
      players: [for (final n in ['A', 'B', 'C']) TPlayer(n, n)],
      start: 501,
      doubleOut: true,
      formats: const {},
    )..build();
    while (!tour.finished) {
      tour.record(tour.playable.first.id, winnerSide: 0, legs: [3, 0]);
    }
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(C.p),
      home: ShareCardScreen(card: TournamentShareCard(t: tour), fileName: 't.png'),
    ));
    await _steps(t, 2);
    expect(find.text('Liga'), findsWidgets);
    expect(t.takeException(), isNull);
  });
}

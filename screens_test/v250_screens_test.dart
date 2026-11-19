// Version 2.5.0: 8 Spieler, Ausbullen-Reihenfolge, Stell-Tipp, Weiterspielen
import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:darts_counter/ui/about_screen.dart';
import 'package:darts_counter/ui/bull_off.dart';
import 'package:darts_counter/ui/game_screen.dart';
import 'package:darts_counter/ui/link_coordinator.dart';
import 'package:darts_counter/ui/scoreboard_screen.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'v4_screens_test.dart' show loadFonts, shot, prep, settle;

const names = ['Simon', 'Max', 'Lena', 'Tom', 'Andi', 'Jule', 'Paul', 'Mia'];

MatchController _eight({int start = 501}) => MatchController(
      config: GameConfig('x01', {'start': start, 'doubleOut': true, 'legs': 1}),
      players: [for (var i = 0; i < 8; i++) GamePlayer('p$i', names[i], C.players[i].toARGB32())],
    );

void main() {
  setUpAll(loadFonts);

  testWidgets('Spiel mit 8 Spielern + Stell-Tipp', (t) async {
    await prep(t, {'onboarded': true, 'seenVersion': appVersion});
    final c = _eight(start: 101);
    // jeder Spieler eine Aufnahme, dann Simon auf 47 mit 1 Dart übrig
    for (var k = 0; k < 8; k++) {
      for (final d in const [Dart(20, 1), Dart(20, 1), Dart(14, 1)]) {
        c.throwDart(d);
      }
    }
    c.throwDart(const Dart(0, 1));
    c.throwDart(const Dart(0, 1));
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(C.p), home: GameScreen(controller: c)));
    await settle(t, 4);
    await shot(t, 'v250_game8');
    await t.pumpWidget(const SizedBox());
    await settle(t, 2);
  });

  testWidgets('Anzeige mit 8 Spielern (Tablet quer)', (t) async {
    await prep(t, {'onboarded': true, 'seenVersion': appVersion}, size: const Size(1280, 800));
    final c = _eight();
    for (var k = 0; k < 9; k++) {
      for (final d in const [Dart(20, 3), Dart(19, 1), Dart(5, 1)]) {
        c.throwDart(d);
      }
    }
    LinkCoordinator.viewerState.value = {'match': c.toJson()};
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(C.p), home: const ScoreboardScreen()));
    await settle(t, 3);
    await shot(t, 'v250_board8');
    await t.pumpWidget(const SizedBox());
    await settle(t, 2);
  });

  testWidgets('Ausbullen mit 5 Spielern, zwei schon getippt', (t) async {
    await prep(t, {'onboarded': true, 'seenVersion': appVersion});
    final players = [for (var i = 0; i < 5; i++) GamePlayer('p$i', names[i], C.players[i].toARGB32())];
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(C.p),
      home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(onPressed: () => showBullOffOrder(ctx, players), child: const Text('los'))))),
    ));
    await t.tap(find.text('los'));
    await settle(t, 4);
    await t.tap(find.bySemanticsLabel('Lena als Nächster'));
    await settle(t, 2);
    await t.tap(find.bySemanticsLabel('Simon als Nächster'));
    await settle(t, 3);
    await shot(t, 'v250_bulloff');
  });
}

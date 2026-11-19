// Version 2.6.0: Leg-/Match-Statistik, Wartebildschirm der Anzeige
import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:darts_counter/ui/about_screen.dart';
import 'package:darts_counter/ui/game_screen.dart';
import 'package:darts_counter/ui/link_coordinator.dart';
import 'package:darts_counter/ui/scoreboard_screen.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'v4_screens_test.dart' show loadFonts, shot, prep, settle;

const t20 = Dart(20, 3), miss = Dart(0, 1);

MatchController _match() => MatchController(
      config: const GameConfig('x01', {'start': 301, 'doubleOut': true, 'legs': 2}),
      players: const [GamePlayer('a', 'Simon', 0xFF5AA9FF), GamePlayer('b', 'Max', 0xFFF5C84C)],
    );

void _visit(MatchController c, List<Dart> ds) {
  for (final d in ds) {
    c.throwDart(d);
  }
}

/// Leg 1: Simon 180, Max 60, Simon checkt 121.
void _leg1(MatchController c) {
  _visit(c, const [t20, t20, t20]);
  _visit(c, const [Dart(20, 1), Dart(20, 1), Dart(20, 1)]);
  _visit(c, const [t20, Dart(11, 3), Dart(14, 2)]);
}

void main() {
  setUpAll(loadFonts);

  testWidgets('Leg-Statistik im Spiel (Handy)', (t) async {
    await prep(t, {'onboarded': true, 'seenVersion': appVersion, 'celebrations': false});
    final c = _match();
    _visit(c, const [t20, t20, t20]);
    _visit(c, const [Dart(20, 1), Dart(20, 1), Dart(20, 1)]);
    _visit(c, const [t20, Dart(11, 3)]);
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(C.p), home: GameScreen(controller: c)));
    await settle(t, 2);
    await t.tap(find.text('Double'));
    await t.pump();
    await t.tap(find.bySemanticsLabel('Double 14'));
    await settle(t, 12);
    await shot(t, 'v260_leg_phone');
    await t.tap(find.bySemanticsLabel('Weiter'));
    await settle(t, 4);
    // Match zu Ende spielen: Leg 2 Max, Leg 3 Simon
    _visit(c, const [t20, t20, t20]);
    _visit(c, const [miss, miss, miss]);
    _visit(c, const [Dart(19, 3), Dart(16, 3), Dart(8, 2)]);
    await settle(t, 12);
    if (find.bySemanticsLabel('Weiter').evaluate().isNotEmpty) {
      await t.tap(find.bySemanticsLabel('Weiter'));
      await settle(t, 4);
    }
    _visit(c, const [t20, t20, t20]);
    _visit(c, const [miss, miss, miss]);
    _visit(c, const [t20, Dart(11, 3)]);
    await settle(t, 2);
    await t.tap(find.text('Double'));
    await t.pump();
    await t.tap(find.bySemanticsLabel('Double 14'));
    await settle(t, 16);
    await shot(t, 'v260_match_phone');
    await t.pumpWidget(const SizedBox());
    await settle(t, 2);
  });

  testWidgets('Anzeige: Warten, Leg-Statistik, Match-Statistik (Tablet)', (t) async {
    await prep(t, {'onboarded': true, 'seenVersion': appVersion, 'celebrations': false}, size: const Size(1280, 800));
    LinkCoordinator.viewerState.value = null;
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(C.p), home: const ScoreboardScreen()));
    await t.pump(const Duration(milliseconds: 900));
    await shot(t, 'v260_board_wait');

    final c = _match();
    _visit(c, const [t20, t20, t20]);
    _visit(c, const [Dart(20, 1), Dart(20, 1), Dart(20, 1)]);
    _visit(c, const [t20, Dart(11, 3)]);
    LinkCoordinator.viewerState.value = {'match': c.toJson()};
    await settle(t, 2);
    c.throwDart(const Dart(14, 2));
    LinkCoordinator.viewerState.value = {'match': c.toJson()};
    await settle(t, 3);
    await shot(t, 'v260_board_leg');

    final m = _match();
    _leg1(m);
    _visit(m, const [t20, t20, t20]);
    _visit(m, const [miss, miss, miss]);
    _visit(m, const [Dart(19, 3), Dart(16, 3), Dart(8, 2)]);
    _leg1(m);
    LinkCoordinator.viewerState.value = {'match': m.toJson()};
    await settle(t, 3);
    await shot(t, 'v260_board_match');
    await t.pumpWidget(const SizedBox());
    await settle(t, 2);
  });
}

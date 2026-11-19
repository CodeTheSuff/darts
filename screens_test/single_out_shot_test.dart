import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:darts_counter/ui/about_screen.dart';
import 'package:darts_counter/ui/game_screen.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'v4_screens_test.dart' show loadFonts, shot, prep, settle;

void main() {
  setUpAll(loadFonts);
  testWidgets('Single Out im Spiel', (t) async {
    await prep(t, {'onboarded': true, 'seenVersion': appVersion});
    final c = MatchController(
      config: const GameConfig('x01', {'start': 101, 'doubleOut': true, 'legs': 2}),
      players: const [GamePlayer('a', 'Simon', 0xFF5AA9FF), GamePlayer('b', 'Max', 0xFFF5C84C)],
    );
    for (final d in const [Dart(20, 3), Dart(1, 1), Dart(0, 1), Dart(20, 1), Dart(1, 1), Dart(0, 1)]) {
      c.throwDart(d);
    }
    for (var v = 0; v < 10; v++) {
      for (var k = 0; k < 3; k++) {
        c.throwDart(const Dart(0, 1));
      }
    }
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(C.p), home: GameScreen(controller: c)));
    await settle(t, 4);
    await shot(t, 'so_offer_bar');
    c.setSingleOut(true);
    await settle(t, 4);
    await shot(t, 'so_on_bar');
    await t.pumpWidget(const SizedBox());
    await settle(t, 2);
  });
}

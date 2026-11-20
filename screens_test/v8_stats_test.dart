// Bildschirmfotos der neuen Statistikseiten: flutter test screens_test/v8_stats_test.dart
import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/games/catalog.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:darts_counter/ui/about_screen.dart';
import 'package:darts_counter/ui/game_screen.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'v4_screens_test.dart' show loadFonts, shot, prep;

const _players = [GamePlayer('a', 'Simon', 0xFF5AA9FF), GamePlayer('b', 'Max', 0xFFF5C84C)];

Future<void> _tapKey(WidgetTester t, String sem) async {
  await t.tap(find.byWidgetPredicate((w) => w is Key3 && w.semantics == sem).first);
  await t.pump(const Duration(milliseconds: 120));
}

Future<void> _wait(WidgetTester t, int seconds) async {
  for (var i = 0; i < seconds * 4; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  setUpAll(loadFonts);
  for (final size in const [Size(1280, 800), Size(412, 900)]) {
    final tag = size.width > 600 ? 'tab' : 'phone';
    testWidgets('Leg-Statistik mit Trefferbild $tag', (t) async {
      await prep(t, {'onboarded': true, 'seenVersion': appVersion}, size: size);
      final ctl = MatchController(
          config: const GameConfig('x01', {'start': 301, 'doubleOut': true, 'legs': 2}), players: _players);
      for (final d in const [Dart(20, 3), Dart(19, 1), Dart(5, 1), Dart(1, 1), Dart(20, 1), Dart(0, 1)]) {
        ctl.throwDart(d);
      }
      await t.pumpWidget(MaterialApp(theme: buildTheme(C.p), home: GameScreen(controller: ctl)));
      await t.pump(const Duration(milliseconds: 500));
      // Simon (217 Rest): T20 T20 T19 → 40
      for (final k in ['Triple', 'Triple 20', 'Triple', 'Triple 20', 'Triple', 'Triple 19']) {
        k == 'Triple' ? await t.tap(find.text('Triple').first) : await _tapKey(t, k);
        await t.pump(const Duration(milliseconds: 120));
      }
      await _wait(t, 5);
      for (final k in ['20', '20', 'Miss']) {
        await _tapKey(t, k);
      }
      await _wait(t, 2);
      // Simon: 40 Rest → D20
      await t.tap(find.text('Double').first);
      await t.pump(const Duration(milliseconds: 120));
      await _tapKey(t, 'Double 20');
      await _wait(t, 6);
      expect(find.text('TREFFERBILD DIESES LEGS'), findsOneWidget);
      await shot(t, 'v8_legstats_$tag');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Minispiel-Statistik $tag', (t) async {
      await prep(t, {'onboarded': true, 'seenVersion': appVersion}, size: size);
      final ctl = MatchController(config: GameConfig('shanghai', {...modeById('shanghai').defaults}), players: _players);
      for (final d in const [Dart(1, 1), Dart(5, 1), Dart(0, 1), Dart(1, 3), Dart(1, 1), Dart(20, 1), Dart(2, 1), Dart(2, 2)]) {
        ctl.throwDart(d);
      }
      await t.pumpWidget(MaterialApp(theme: buildTheme(C.p), home: GameScreen(controller: ctl)));
      await t.pump(const Duration(milliseconds: 500));
      await _tapKey(t, 'T2, Triple · +6');
      await _wait(t, 12);
      expect(find.text('STATISTIK'), findsOneWidget);
      await shot(t, 'v8_ministats_$tag');
      await t.pumpWidget(const SizedBox());
    });
  }
}

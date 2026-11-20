// Bildschirmfotos der Anzeige mit mehreren Scheiben: flutter test screens_test/v8_boards_display_shots_test.dart
import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:darts_counter/ui/link_coordinator.dart';
import 'package:darts_counter/ui/scoreboard_screen.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'v4_screens_test.dart' show loadFonts, shot, prep;

const _players = [
  GamePlayer('a', 'Simon', 0xFF5AA9FF),
  GamePlayer('b', 'Max', 0xFFF5C84C),
  GamePlayer('c', 'Lena', 0xFF7BE07B),
  GamePlayer('d', 'Tom', 0xFFFF7A7A),
  GamePlayer('e', 'Jana', 0xFFC38BFF),
  GamePlayer('f', 'Paul', 0xFF4FD6C8),
  GamePlayer('g', 'Andi', 0xFFFF9F43),
];

MatchController _m(List<int> who, Map<String, dynamic> opts, List<Dart> darts) {
  final c = MatchController(
    config: GameConfig('x01', {'start': 501, 'doubleOut': true, ...opts}),
    players: [for (final i in who) _players[i]],
  );
  for (final d in darts) {
    c.throwDart(d);
  }
  return c;
}

List<MatchController> _boards(int n) => [
  _m([0, 1], {'legs': 3}, const [Dart(20, 3), Dart(20, 3), Dart(20, 1), Dart(19, 3), Dart(19, 1), Dart(3, 1), Dart(20, 3)]),
  _m([2, 3], {'format': 'sets', 'sets': 2, 'legs': 3}, const [Dart(20, 1), Dart(5, 1), Dart(1, 1), Dart(25, 2)]),
  if (n > 2) _m([4, 5, 6], {'legs': 2}, const [Dart(20, 3), Dart(20, 3), Dart(20, 3), Dart(19, 1)]),
];

Map<String, dynamic> _state(List<MatchController> b) => {
  'match': b.first.toJson(),
  'boards': [
    for (var i = 0; i < b.length; i++) {'n': i + 1, 'name': 'Scheibe ${i + 1}', 'match': b[i].toJson()},
  ],
};

void main() {
  setUpAll(loadFonts);
  for (final size in const [Size(1280, 800), Size(412, 915)]) {
    for (final n in const [2, 3]) {
      final tag = '${n}_${size.width.toInt()}x${size.height.toInt()}';
      testWidgets('Anzeige $n Scheiben $tag', (tester) async {
        await prep(tester, {}, size: size);
        final b = _boards(n);
        LinkCoordinator.viewerState.value = _state(b);
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(C.p),
          home: const ScoreboardScreen(),
        ));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        await shot(tester, 'v8_boards_alle_$tag');
        expect(tester.takeException(), isNull);
        // Einzelne Scheibe gewählt
        await tester.tap(find.byKey(const ValueKey('board-chip-2')));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        await shot(tester, 'v8_boards_einzeln_$tag');
        expect(tester.takeException(), isNull);
        // Zurück zu „Alle“, Jubel auf Scheibe 2 (mit Hinweis, welche Scheibe)
        await tester.tap(find.byKey(const ValueKey('board-chip-0')));
        await tester.pump(const Duration(milliseconds: 300));
        b[1]
          ..throwDart(const Dart(20, 3))
          ..throwDart(const Dart(20, 3));
        LinkCoordinator.viewerState.value = _state(b);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        await shot(tester, 'v8_boards_jubel_$tag');
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 300));
      });
    }
  }
}

// Scoreboard-Ansicht (Tablet): flutter test screens_test/board_v6_test.dart
import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:darts_counter/ui/about_screen.dart';
import 'package:darts_counter/ui/link_coordinator.dart';
import 'package:darts_counter/ui/scoreboard_screen.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'v4_screens_test.dart' show loadFonts, shot, prep, settle;

MatchController _match(int start) => MatchController(
      config: GameConfig('x01', {'start': start, 'doubleOut': true, 'legs': 1}),
      players: const [GamePlayer('a', 'Simon', 0xFF5AA9FF), GamePlayer('b', 'Max', 0xFFF5C84C)],
    );

void main() {
  setUpAll(loadFonts);

  for (final size in const [Size(1280, 800), Size(800, 1280)]) {
    testWidgets('Board ${size.width}', (t) async {
      await prep(t, {'onboarded': true, 'seenVersion': appVersion}, size: size);
      final c = _match(501);
      for (final d in const [Dart(20, 3), Dart(20, 1), Dart(5, 1), Dart(19, 3), Dart(19, 3), Dart(19, 1), Dart(20, 3)]) {
        c.throwDart(d);
      }
      LinkCoordinator.viewerState.value = {'match': c.toJson()};
      await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(C.p), home: const ScoreboardScreen()));
      await settle(t, 3);
      await shot(t, 'v6_board_${size.width.toInt()}');

      // Max wirft weiter: 180 → Animation
      for (final d in const [Dart(20, 3), Dart(20, 3)]) {
        c.throwDart(d);
      }
      // Simon zuerst: T20 T20 T20
      final c2 = _match(501);
      for (final d in const [Dart(20, 3), Dart(20, 3), Dart(20, 3)]) {
        c2.throwDart(d);
      }
      LinkCoordinator.viewerState.value = {'match': c2.toJson()};
      await settle(t, 2);
      for (final d in const [Dart(20, 1), Dart(20, 1), Dart(20, 1), Dart(20, 3), Dart(20, 3), Dart(20, 3)]) {
        c2.throwDart(d);
      }
      LinkCoordinator.viewerState.value = {'match': c2.toJson()};
      await settle(t, 6);
      await shot(t, 'v6_board_180_${size.width.toInt()}');
      await settle(t, 30);

      // Finish-Weg groß
      final c4 = _match(301);
      for (final d in const [Dart(20, 3), Dart(20, 3), Dart(20, 3), Dart(19, 3), Dart(5, 1), Dart(1, 1)]) {
        c4.throwDart(d);
      }
      LinkCoordinator.viewerState.value = {'match': c4.toJson()};
      await settle(t, 3);
      await shot(t, 'v6_board_finish_${size.width.toInt()}');
      // Single Out in diesem Leg
      c4.setSingleOut(true);
      LinkCoordinator.viewerState.value = {'match': c4.toJson()};
      await settle(t, 3);
      await shot(t, 'v6_board_so_${size.width.toInt()}');

      // Match zu Ende
      final c3 = _match(101);
      LinkCoordinator.viewerState.value = {'match': c3.toJson()};
      await settle(t, 2);
      for (final d in const [Dart(20, 3), Dart(1, 1), Dart(20, 2)]) {
        c3.throwDart(d);
      }
      LinkCoordinator.viewerState.value = {'match': c3.toJson()};
      await settle(t, 60);
      await shot(t, 'v6_board_win_${size.width.toInt()}');
      await t.pumpWidget(const SizedBox());
      await settle(t, 2);
    });
  }
}

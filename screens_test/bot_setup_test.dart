import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/games/catalog.dart';
import 'package:darts_counter/ui/setup_screen.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'v4_screens_test.dart' show loadFonts, shot, prep, settle;

void main() {
  setUpAll(loadFonts);
  testWidgets('Eigener Bot', (t) async {
    await prep(t, {}, size: const Size(412, 1100));
    Store.lastSetup = {
      'players': [
        {'name': 'Simon', 'color': C.players[0].toARGB32()},
        {'bot': 'custom', 'avg': 68, 'dbl': 28, 'color': C.players[1].toARGB32()},
      ],
    };
    await t.pumpWidget(MaterialApp(theme: buildTheme(C.p), home: SetupScreen(mode: modes.firstWhere((m) => m.id == 'x01'))));
    await settle(t);
    await shot(t, 'bot_custom');
  });
}

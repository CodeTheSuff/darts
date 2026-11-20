// Bildschirmfotos der Turnier-Anzeige: flutter test screens_test/v8_tournament_display_test.dart
import 'package:darts_counter/games/tournament.dart';
import 'package:darts_counter/ui/about_screen.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:darts_counter/ui/tournament_display.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'v4_screens_test.dart' show loadFonts, shot, prep;

const _names = ['Simon', 'Max', 'Lena', 'Tom', 'Jana', 'Paul', 'Andi', 'Matze'];

Tournament _t(TSystem s, int n, int played, {String name = 'Darts-Abend'}) {
  final t = Tournament(
    id: s.name,
    name: name,
    created: DateTime(2026, 11, 20),
    system: s,
    players: [for (final x in _names.take(n)) TPlayer(x, x)],
    start: 501,
    doubleOut: true,
    formats: const {},
  )..build();
  for (var i = 0; i < played && !t.finished; i++) {
    final m = t.playable.first;
    t.record(m.id, winnerSide: i % 3 == 0 ? 1 : 0, legs: i.isEven ? [3, 1] : [2, 3], points: [400 + i * 7, 350], darts: [18, 18]);
  }
  return t;
}

void main() {
  setUpAll(loadFonts);
  for (final (tag, t) in [
    ('ko', _t(TSystem.ko, 8, 5)),
    ('liga', _t(TSystem.league, 6, 7, name: 'Liga-Abend')),
    ('gruppen', _t(TSystem.groups, 8, 6, name: 'Vereinsmeisterschaft')),
    ('ende', _t(TSystem.ko, 6, 99)),
  ]) {
    testWidgets('Turnier-Anzeige $tag', (tester) async {
      await prep(tester, {'onboarded': true, 'seenVersion': appVersion}, size: const Size(1280, 800));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(C.p),
        home: Scaffold(body: SafeArea(child: TournamentDisplay(t: t, interval: const Duration(seconds: 2)))),
      ));
      for (var page = 0; page < 3; page++) {
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pump(const Duration(milliseconds: 800));
        await shot(tester, 'v8_tdisp_${tag}_$page');
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}

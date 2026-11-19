import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/data/tournament_store.dart';
import 'package:darts_counter/games/tournament.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/ui/about_screen.dart';
import 'package:darts_counter/ui/link_coordinator.dart';
import 'package:darts_counter/ui/scoreboard_screen.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'v4_screens_test.dart' show loadFonts, shot, prep, settle;

void main() {
  setUpAll(loadFonts);
  testWidgets('Anzeige im Turnier mit nächster Paarung', (t) async {
    await prep(t, {'onboarded': true, 'seenVersion': appVersion}, size: const Size(1280, 800));
    MatchController.onTournamentMatchDone = TournamentStore.onMatchDone;
    final tour = Tournament(
      id: 'tn',
      name: 'Freitagsliga',
      created: DateTime(2026),
      system: TSystem.league,
      players: const [TPlayer('a', 'Simon'), TPlayer('b', 'Max'), TPlayer('c', 'Lena'), TPlayer('d', 'Tom')],
      start: 501,
      doubleOut: true,
      formats: const {TStage.group: TFormat(legs: 2)},
    )..build();
    TournamentStore.save(tour);
    final m = tour.playable.first;
    final c = TournamentStore.controllerFor(tour, m, 0);
    for (final d in const [Dart(20, 3), Dart(20, 1), Dart(5, 1)]) {
      c.throwDart(d);
    }
    expect(nextMatchLabel(tour, exceptMatch: m.id), isNotNull);
    LinkCoordinator.viewerState.value = {'match': c.toJson(), 'tournament': tour.toJson()};
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(C.p), home: const ScoreboardScreen()));
    await settle(t, 3);
    await shot(t, 'board_next_1280');
    await t.pumpWidget(const SizedBox());
    await settle(t, 2);
  });
}

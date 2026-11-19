// Belastung: Host im Turnier, gekoppelt mit einer Anzeige – wie lange dauert ein Dart?
import 'dart:convert';
import 'dart:math';

import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/data/tournament_store.dart';
import 'package:darts_counter/games/tournament.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/net/link.dart';
import 'package:darts_counter/ui/link_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Tournament _tournament(String id, int n, {bool playAll = false}) {
  final t = Tournament(
    id: id,
    name: 'Turnier $id',
    created: DateTime(2026),
    system: TSystem.league,
    players: [for (var i = 0; i < n; i++) TPlayer('p$i', 'Spieler $i')],
    start: 501,
    doubleOut: true,
    formats: const {TStage.group: TFormat(legs: 3)},
  )..build();
  if (playAll) {
    final rng = Random(1);
    while (t.playable.isNotEmpty) {
      final m = t.playable.first;
      t.record(m.id, winnerSide: rng.nextInt(2), legs: [2, 1], points: [1400, 1300], darts: [60, 60]);
    }
  }
  return t;
}

void main() {
  test('Dart im Turnier mit Anzeige bleibt schnell', () async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    MatchController.onTournamentMatchDone = TournamentStore.onMatchDone;
    // Viele alte Turniere im Speicher + ein laufendes Liga-Turnier mit 16 Spielern
    for (var k = 0; k < 15; k++) {
      TournamentStore.save(_tournament('old$k', 16, playAll: true));
    }
    final t = _tournament('live', 16);
    TournamentStore.save(t);
    final size = (Store.tournaments.map(jsonEncode).join()).length;

    LinkCoordinator.init();
    Link.I.trustAll = true;
      await Link.I.startHost(preferredPort: 0);
    final viewer = Link.forTest();
    var states = 0;
    var bytes = 0;
    var lastDarts = 0;
    viewer.onState = (m) {
      states++;
      bytes = jsonEncode(m).length;
      final mj = m['match'];
      if (mj is Map) lastDarts = (mj['darts'] as List).length;
    };
    expect(await viewer.join('127.0.0.1', Link.I.port, Link.I.code!, viewer: true), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    LinkCoordinator.tournamentOpened('live');
    final m = t.playable.first;
    final ctl = TournamentStore.controllerFor(t, m, 0);
    LinkCoordinator.gameOpened(ctl);

    final sw = Stopwatch()..start();
    var worst = 0;
    var thrown = 0;
    for (var i = 0; i < 300 && !ctl.engine.finished; i++) {
      final s = Stopwatch()..start();
      ctl.throwDart(Dart(i % 7 == 0 ? 0 : 20, 1));
      worst = max(worst, s.elapsedMilliseconds);
      thrown++;
    }
    final perDart = sw.elapsedMilliseconds / thrown;
    final wait = Stopwatch()..start();
    while (lastDarts < thrown && wait.elapsedMilliseconds < 5000) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    // ignore: avoid_print
    print('Anzeige hat $states Stände nach ${wait.elapsedMilliseconds} ms, letzter Stand ${(bytes / 1024).toStringAsFixed(1)} KB');
    // ignore: avoid_print
    print('Turnierdaten ${(size / 1024).round()} KB · $thrown Darts · Ø ${perDart.toStringAsFixed(1)} ms/Dart · '
        'max $worst ms · Stände empfangen: $states');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    LinkCoordinator.gameClosed(ctl);
    await viewer.stop();
    await Link.I.stop();
    expect(perDart, lessThan(30));
    expect(lastDarts, thrown, reason: 'Anzeige hat den letzten Stand bekommen');
  });
}

import 'dart:async';

import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/data/tournament_store.dart';
import 'package:darts_counter/games/tournament.dart';
import 'package:darts_counter/games/x01.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/net/link.dart';
import 'package:darts_counter/ui/link_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Spielt ein Turnierspiel zu Ende: Spieler 0 checkt 101 mit T17 + Bull, Spieler 1 wirft daneben.
void finish(MatchController c) {
  var guard = 0;
  while (!c.engine.finished && guard++ < 200) {
    final e = c.engine as X01Game;
    if (e.cur == 0) {
      c.throwDart(e.scores[0] == 101 ? const Dart(17, 3) : const Dart(25, 2));
    } else {
      c.throwDart(const Dart(0, 1));
    }
  }
}

Map<String, dynamic> boardMsg(MatchController c, {bool closed = false}) => {
      't': 'board',
      'mid': c.matchId,
      'tid': c.tournamentId,
      'tmid': c.tournamentMatchId,
      'match': c.toJson(),
      if (closed) 'closed': true,
    };

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    Store.deviceName = 'Host';
  });

  test('Zwei Scheiben: Nummern, Sperre, Ablehnung, Ergebnis landet im Turnier', () async {
    final t = Tournament(
      id: 'tb',
      name: 'Zwei Scheiben',
      created: DateTime(2026, 11, 20),
      system: TSystem.league,
      players: [for (final n in ['Simon', 'Max', 'Lena', 'Tom']) TPlayer(n, n)],
      start: 101,
      doubleOut: true,
      formats: const {TStage.group: TFormat(legs: 1)},
    )..build();
    TournamentStore.save(t);

    LinkCoordinator.init();
    Link.I.trustAll = true;
    await Link.I.startHost(preferredPort: 0);
    LinkCoordinator.tournamentOpened(t.id);

    // Zwei Eingabe-Handys verbinden sich
    final g1 = Link.forTest()..deviceForTest = 'handy-1';
    final g2 = Link.forTest()..deviceForTest = 'handy-2';
    final s1 = StreamController<Map<String, dynamic>>.broadcast();
    final s2 = StreamController<Map<String, dynamic>>.broadcast();
    final d2 = StreamController<Map<String, dynamic>>.broadcast();
    g1.onState = s1.add;
    g2.onState = s2.add;
    g2.onDirect = d2.add;
    expect(await g1.join('127.0.0.1', Link.I.port, Link.I.code!), isTrue);
    expect(await g2.join('127.0.0.1', Link.I.port, Link.I.code!), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // Nummern: Host 1, Gäste 2 und 3
    Link.I.broadcastState();
    final st = await s1.stream.firstWhere((s) => (s['boardOf'] as Map).length == 3).timeout(const Duration(seconds: 3));
    final numbers = (st['boardOf'] as Map).values.toSet();
    expect(numbers, {1, 2, 3});

    // Gast 1 startet das erste Turnierspiel → Sperre für seine Scheibe
    final m1 = t.playable.first;
    final c1 = TournamentStore.controllerFor(t, m1, 0)..throwDart(const Dart(20, 1));
    g1.sendToHost(boardMsg(c1));
    final claimed = await s2.stream
        .firstWhere((s) => (s['claims'] as Map).containsKey(m1.id))
        .timeout(const Duration(seconds: 3));
    final board1 = (claimed['claims'] as Map)[m1.id];
    expect(board1, isNot(1));
    expect((claimed['boards'] as List).length, 1, reason: 'eine laufende Scheibe');

    // Gast 2 will dasselbe Spiel → abgelehnt
    final denied = d2.stream.first;
    final c1b = TournamentStore.controllerFor(t, m1, 1);
    g2.sendToHost(boardMsg(c1b));
    final d = await denied.timeout(const Duration(seconds: 3));
    expect(d['kind'], 'boardDenied');
    expect(d['by'], board1);

    // Gast 2 spielt parallel ein anderes Spiel → zwei Scheiben laufen
    final m2 = t.playable.firstWhere((m) => m.id != m1.id && LinkCoordinator.claims[m.id] == null);
    final c2 = TournamentStore.controllerFor(t, m2, 0)..throwDart(const Dart(19, 1));
    g2.sendToHost(boardMsg(c2));
    final two = await s1.stream.firstWhere((s) => (s['boards'] as List).length == 2).timeout(const Duration(seconds: 3));
    expect((two['claims'] as Map).length, 2);

    // Gast 1 beendet sein Spiel → Ergebnis steht im Turnier des Hosts, Sperre weg
    finish(c1);
    g1.sendToHost(boardMsg(c1));
    await s1.stream
        .firstWhere((s) => !(s['claims'] as Map).containsKey(m1.id))
        .timeout(const Duration(seconds: 3));
    final saved = TournamentStore.byId(t.id)!;
    expect(saved.matches.firstWhere((m) => m.id == m1.id).played, isTrue);

    // Gast 1 verlässt den Ergebnisbildschirm → Scheibe verschwindet von der Anzeige
    g1.sendToHost(boardMsg(c1, closed: true));
    final one = await s1.stream.firstWhere((s) => (s['boards'] as List).length == 1).timeout(const Duration(seconds: 3));
    expect(((one['boards'] as List).first as Map)['match']['mid'], c2.matchId);

    // Gast 2 unterbricht (verlässt das Spiel) → bleibt gesperrt, Host gibt frei
    g2.sendToHost(boardMsg(c2, closed: true));
    await s1.stream.firstWhere((s) => (s['boards'] as List).isEmpty).timeout(const Duration(seconds: 3));
    expect(LinkCoordinator.claims.containsKey(m2.id), isTrue, reason: 'unterbrochen = weiter gesperrt');
    final released = d2.stream.first;
    LinkCoordinator.releaseClaim(m2.id);
    expect((await released.timeout(const Duration(seconds: 3)))['kind'], 'boardReleased');
    expect(LinkCoordinator.claims.containsKey(m2.id), isFalse);

    // Scheiben-Nummer ändern: 1 ist vom Host belegt → abgelehnt; 7 ist frei
    final taken = d2.stream.first;
    g2.sendToHost({'t': 'boardNo', 'n': 1});
    expect((await taken.timeout(const Duration(seconds: 3)))['kind'], 'boardNoTaken');
    g2.sendToHost({'t': 'boardNo', 'n': 7});
    await s2.stream.firstWhere((s) => (s['boardOf'] as Map).values.contains(7)).timeout(const Duration(seconds: 3));

    await g1.stop();
    await g2.stop();
    LinkCoordinator.tournamentClosed(t.id);
    await Link.I.stop();
  });
}

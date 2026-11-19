import 'dart:math';

import 'package:darts_counter/games/tournament.dart';
import 'package:flutter_test/flutter_test.dart';

Tournament make(TSystem system, int n, {bool homeAway = false, int? groups, int? advance}) {
  final (g, a) = suggestGroups(n);
  final t = Tournament(
    id: 't',
    name: 'Test',
    created: DateTime(2026),
    system: system,
    players: [for (var i = 0; i < n; i++) TPlayer('p$i', 'Spieler $i')],
    start: 501,
    doubleOut: true,
    formats: const {},
    homeAway: homeAway,
    groupCount: groups ?? g,
    advance: advance ?? a,
  );
  t.build();
  return t;
}

/// Spielt alle Matches zufällig durch (der Stärkere gewinnt mit 70 %).
Map<int, int> playOut(Tournament t, Random rng, {int Function(int a, int b)? pick}) {
  final losses = <int, int>{};
  var guard = 0;
  while (!t.finished && guard++ < 2000) {
    final open = t.playable;
    expect(open, isNotEmpty, reason: 'Turnier hängt (${t.system}, ${t.n} Spieler)');
    final m = open[rng.nextInt(open.length)];
    final (a, b) = t.participants(m);
    final side = pick != null ? pick(a!, b!) : (rng.nextDouble() < (a! < b! ? 0.7 : 0.3) ? 0 : 1);
    t.record(m.id, winnerSide: side, legs: side == 0 ? [3, rng.nextInt(3)] : [rng.nextInt(3), 3]);
    final loser = side == 0 ? b : a;
    losses[loser] = (losses[loser] ?? 0) + 1;
  }
  expect(t.finished, isTrue);
  return losses;
}

void checkPlacements(Tournament t) {
  final pl = t.placements();
  expect(pl.map((p) => p.player).toSet().length, t.n, reason: 'jeder genau einmal platziert');
  expect(pl.length, t.n);
  expect(pl.where((p) => p.rank == 1).length, 1);
  expect(pl.every((p) => p.rank >= 1 && p.rank <= t.n), isTrue);
}

void main() {
  test('Setzpositionen', () {
    expect(seedPositions(8), [1, 8, 4, 5, 2, 7, 3, 6]);
    expect(nextPow2(5), 8);
  });

  test('K.o.: 1 vs 8, Freilose an die Besten', () {
    final t = make(TSystem.ko, 6);
    final r1 = t.matches.where((m) => m.bracket == 'W' && m.round == 1).toList();
    expect(r1.first.a.index, 0);
    expect(r1.first.b.index, -1); // Freilos für Nummer 1
    expect(t.isDecided(r1.first), isTrue);
    expect(t.winnerOf(r1.first), 0);
  });

  for (final system in TSystem.values) {
    for (var n = 3; n <= 32; n++) {
      if (system == TSystem.groups && n < 4) continue;
      test('${system.name} mit $n Spielern läuft komplett durch', () {
        final rng = Random(n * 31 + system.index);
        final t = make(system, n);
        final losses = playOut(t, rng);
        checkPlacements(t);
        final champ = t.champion!;
        if (system == TSystem.ko) {
          // Jeder außer dem Sieger verliert im Baum genau einmal (+ evtl. Spiel um Platz 3).
          final wbLosses = <int, int>{};
          for (final m in t.matches.where((m) => m.bracket == 'W' && m.played)) {
            final l = t.loserOf(m)!;
            wbLosses[l] = (wbLosses[l] ?? 0) + 1;
          }
          expect(wbLosses[champ], isNull);
          expect(wbLosses.values.every((v) => v == 1), isTrue);
          expect(wbLosses.length, n - 1);
        }
        if (system == TSystem.doubleKo) {
          for (var p = 0; p < n; p++) {
            if (p == champ) {
              expect(losses[p] ?? 0, lessThanOrEqualTo(1));
            } else {
              expect(losses[p], 2, reason: 'Spieler $p muss genau 2x verloren haben');
            }
          }
        }
        if (system == TSystem.league) {
          expect(t.matches.length, n * (n - 1) ~/ 2);
        }
      });
    }
  }

  test('Doppel-K.o.: Entscheidungsspiel, wenn der Verliererrunden-Sieger das Finale gewinnt', () {
    final t = make(TSystem.doubleKo, 4);
    // Spieler 0 gewinnt die Hauptrunde, verliert dann das erste Finale.
    final rng = Random(3);
    var guard = 0;
    while (!t.finished && guard++ < 100) {
      final m = t.playable.first;
      final (a, b) = t.participants(m);
      int side;
      if (m.id == 'F-1') {
        side = 1;
      } else if (m.id == 'F-2') {
        side = 0;
      } else {
        side = a == 0 ? 0 : (b == 0 ? 1 : rng.nextInt(2));
      }
      t.record(m.id, winnerSide: side, legs: side == 0 ? [3, 1] : [1, 3]);
    }
    expect(t.matchById('F-2').played, isTrue);
    expect(t.champion, 0);
  });

  test('Doppel-K.o.: kein Entscheidungsspiel, wenn der Hauptrunden-Sieger gewinnt', () {
    final t = make(TSystem.doubleKo, 5);
    playOut(t, Random(1), pick: (a, b) => a < b ? 0 : 1);
    expect(t.matchById('F-2').played, isFalse);
    expect(t.isSkipped(t.matchById('F-2')), isTrue);
    expect(t.champion, 0);
  });

  test('Liga mit Hin- und Rückspiel', () {
    final t = make(TSystem.league, 5, homeAway: true);
    expect(t.matches.length, 20);
    playOut(t, Random(2));
    checkPlacements(t);
  });

  test('Tabelle: Siege vor Legdifferenz vor direktem Vergleich', () {
    final t = make(TSystem.league, 3);
    // 0 schlägt 1, 1 schlägt 2, 2 schlägt 0 – alle 1 Sieg; Legdifferenz entscheidet.
    for (final m in t.matches) {
      final (a, b) = t.participants(m);
      final pair = {a, b};
      int winner;
      if (pair.containsAll([0, 1])) {
        winner = 0;
      } else if (pair.containsAll([1, 2])) {
        winner = 1;
      } else {
        winner = 2;
      }
      final side = winner == a ? 0 : 1;
      // Spieler 1 gewinnt deutlich (3:0), die anderen knapp (3:2).
      final big = winner == 1;
      t.record(m.id, winnerSide: side, legs: side == 0 ? [3, big ? 0 : 2] : [big ? 0 : 2, 3]);
    }
    final table = t.standings();
    expect(table.first.player, 1);
    expect(table.every((s) => s.wins == 1), isTrue);
  });

  test('Gruppen: Schlangenverteilung und Aufsteiger über Kreuz', () {
    final t = make(TSystem.groups, 8, groups: 2, advance: 2);
    expect(t.groupMembers(), [
      [0, 3, 4, 7],
      [1, 2, 5, 6],
    ]);
    final firstKo = t.matches.firstWhere((m) => m.bracket == 'W' && m.round == 1);
    expect(firstKo.a.kind, 'q');
    expect((firstKo.a.group, firstKo.a.place), (0, 0)); // A1
    expect((firstKo.b.group, firstKo.b.place), (1, 1)); // gegen B2
  });

  test('JSON-Rundreise', () {
    final t = make(TSystem.doubleKo, 7);
    playOut(t, Random(5));
    final copy = Tournament.fromJson(t.toJson());
    expect(copy.finished, isTrue);
    expect(copy.champion, t.champion);
    expect(copy.placements().map((p) => p.rank).toList(), t.placements().map((p) => p.rank).toList());
  });

  test('Ergebnis zurücknehmen nur ohne gespielte Folge-Matches', () {
    final t = make(TSystem.ko, 4);
    final sf = t.playable.first;
    t.record(sf.id, winnerSide: 0, legs: [3, 0]);
    expect(t.canReset(t.matchById(sf.id)), isTrue);
    final other = t.playable.firstWhere((m) => m.id != sf.id && m.round == 1);
    t.record(other.id, winnerSide: 0, legs: [3, 0]);
    final fin = t.matches.firstWhere((m) => m.bracket == 'W' && m.round == 2);
    t.record(fin.id, winnerSide: 0, legs: [3, 1]);
    expect(t.canReset(t.matchById(sf.id)), isFalse);
  });
}

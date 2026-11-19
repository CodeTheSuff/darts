import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/data/match_report.dart';
import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const t20 = Dart(20, 3), miss = Dart(0, 1);

MatchReport _report(MatchController c) => MatchReport.build(
      config: c.config,
      players: c.players,
      startIndex: c.startIndex,
      seed: c.seed,
      darts: c.darts,
    )!;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });

  test('Handgerechnetes Match: 301, A gewinnt 2:1', () {
    final c = MatchController(
      config: const GameConfig('x01', {'start': 301, 'doubleOut': true, 'legs': 2}),
      players: const [GamePlayer('a', 'A', 0), GamePlayer('b', 'B', 1)],
    );
    void visit(List<Dart> ds) {
      for (final d in ds) {
        c.throwDart(d);
      }
    }

    // Leg 1 (A beginnt): A 180, B 60, A checkt 121 (T20 T11 D14)
    visit(const [t20, t20, t20]);
    visit(const [Dart(20, 1), Dart(20, 1), Dart(20, 1)]);
    visit(const [t20, Dart(11, 3), Dart(14, 2)]);
    // Leg 2 (B beginnt): B 180, A 0, B checkt 121 (T19 T16 D8)
    visit(const [t20, t20, t20]);
    visit(const [miss, miss, miss]);
    visit(const [Dart(19, 3), Dart(16, 3), Dart(8, 2)]);
    // Leg 3 (A beginnt): A 180, B 0, A checkt 121
    visit(const [t20, t20, t20]);
    visit(const [miss, miss, miss]);
    visit(const [t20, Dart(11, 3), Dart(14, 2)]);
    expect(c.engine.finished, isTrue);

    final r = _report(c);
    expect(r.legs.length, 3);
    expect([for (final l in r.legs) l.winner], [0, 1, 0]);

    final l1 = r.legs.first;
    expect(l1.players[0].darts, 6);
    expect(l1.players[0].average, closeTo(150.5, 0.01));
    expect(l1.players[0].finish, 121);
    expect(l1.players[0].coAttempts, 1);
    expect(l1.players[0].coHits, 1);
    expect(l1.players[0].c180, 1);
    expect(l1.players[0].c100, 1); // die 121 als Aufnahme
    expect(l1.players[1].darts, 3);
    expect(l1.players[1].average, closeTo(60, 0.01));
    expect(l1.players[1].finish, isNull);

    final a = r.total[0], b = r.total[1];
    expect(a.legsWon, 2);
    expect(b.legsWon, 1);
    expect(a.darts, 15);
    expect(a.average, closeTo(120.4, 0.01));
    expect(a.first9, closeTo(120.4, 0.01));
    expect(b.darts, 12);
    expect(b.average, closeTo(90.25, 0.01));
    expect(a.c180, 2);
    expect(b.c180, 1);
    expect(a.coRate, 100);
    expect(a.bestLeg, 6);
    expect(b.bestLeg, 6);
    expect(a.highestFinish, 121);

    // Tabelle: A hat den besseren Average, Gleichstand beim besten Leg ohne Hervorhebung
    final rows = matchRows(r);
    expect(rows.firstWhere((x) => x.label == 'Average').best, 0);
    expect(rows.firstWhere((x) => x.label == 'Bestes Leg').best, isNull);
    expect(legRows(r.legs[1]).firstWhere((x) => x.label == 'Average').best, 1);
  });

  test('Überworfen zählt 0 Punkte, aber alle Darts', () {
    final c = MatchController(
      config: const GameConfig('x01', {'start': 101, 'doubleOut': true, 'legs': 1}),
      players: const [GamePlayer('a', 'A', 0)],
    );
    c.throwDart(t20); // 41 übrig
    c.throwDart(t20); // überworfen → zurück auf 101
    final r = _report(c);
    expect(r.legs.single.players[0].darts, 2);
    expect(r.legs.single.players[0].points, 0);
  });
}

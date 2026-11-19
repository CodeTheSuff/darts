import 'package:darts_counter/data/analytics.dart';
import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/games/x01.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const miss = Dart(0, 1);

MatchController _ctl({int legs = 2}) => MatchController(
      config: GameConfig('x01', {'start': 101, 'doubleOut': true, 'legs': legs}),
      players: const [GamePlayer('a', 'Simon', 0xFF5AA9FF)],
    );

/// Auf 40 stellen (eine Aufnahme), danach [n] Aufnahmen nur Fehlwürfe.
List<ThrowEvent> _stuckAt40(MatchController c, int n) {
  final evs = <ThrowEvent>[];
  for (final d in const [Dart(20, 3), Dart(1, 1), miss]) {
    evs.add(c.throwDart(d));
  }
  for (var v = 0; v < n; v++) {
    for (var k = 0; k < 3; k++) {
      evs.add(c.throwDart(miss));
    }
  }
  return evs;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });

  test('Nach 5 Aufnahmen ohne Änderung wird Single Out angeboten – genau einmal', () {
    final c = _ctl();
    final evs = _stuckAt40(c, 4);
    expect(evs.where((e) => e.offerSingleOut != null), isEmpty);
    final g = c.engine as X01Game;
    expect(g.singleOutOffered, isFalse);
    var more = <ThrowEvent>[for (var k = 0; k < 3; k++) c.throwDart(miss)];
    expect(more.last.offerSingleOut, 0);
    expect(g.singleOutOffered, isTrue);
    more = [for (var k = 0; k < 6; k++) c.throwDart(miss)];
    expect(more.where((e) => e.offerSingleOut != null), isEmpty);
  });

  test('Ändert sich der Rest, beginnt die Zählung neu', () {
    final c = _ctl();
    _stuckAt40(c, 4);
    // 40 → 20 (Single 20, dann zwei Fehlwürfe)
    for (final d in const [Dart(20, 1), miss, miss]) {
      c.throwDart(d);
    }
    final g = c.engine as X01Game;
    expect(g.scores[0], 20);
    expect(g.stuck[0], 0);
    final evs = [for (var k = 0; k < 12; k++) c.throwDart(miss)];
    expect(evs.where((e) => e.offerSingleOut != null), isEmpty);
    expect(g.stuck[0], 4);
  });

  test('Überwerfen zählt als unveränderte Aufnahme', () {
    final c = _ctl();
    for (final d in const [Dart(20, 3), Dart(1, 1), miss]) {
      c.throwDart(d);
    }
    for (var v = 0; v < 5; v++) {
      c.throwDart(const Dart(20, 3)); // 60 auf 40 → Bust
    }
    expect((c.engine as X01Game).singleOutOffered, isTrue);
  });

  test('Single Out: Finish ohne Double, zählt nicht als Double und nicht als High-Finish; nächstes Leg wieder Double',
      () {
    final c = _ctl();
    _stuckAt40(c, 5);
    final g0 = c.engine as X01Game;
    expect(g0.hint!.text, 'D20');
    c.setSingleOut(true);
    final g = c.engine as X01Game;
    expect(g.singleOutLeg, isTrue);
    expect(g.doubleOutNow, isFalse);
    expect(g.title, contains('Single Out'));
    expect(g.hint!.text, '20 · 20'); // Weg ohne Double
    final coBefore = g.stats[0].coHits;
    c.throwDart(const Dart(20, 1));
    final ev = c.throwDart(const Dart(20, 1)); // 40 single gecheckt
    expect(ev.singleOutFinish, isTrue);
    expect(g.legs[0], 1);
    expect(g.stats[0].coHits, coBefore);
    expect(g.stats[0].highestFinish, 0);
    // Neues Leg: wieder Double Out, Zählung neu
    expect(g.singleOutLeg, isFalse);
    expect(g.singleOutOffered, isFalse);
    expect(g.doubleOutNow, isTrue);
    expect(g.stats[0].legsWon, 1);
  });

  test('Rückgängig nimmt das Umschalten mit zurück', () {
    final c = _ctl();
    _stuckAt40(c, 5);
    final n = c.darts.length;
    c.setSingleOut(true);
    expect(c.darts.length, n + 1);
    c.undo(); // letzter Fehlwurf + Umschalten
    expect(c.darts.length, n - 1);
    expect((c.engine as X01Game).singleOutLeg, isFalse);
  });

  test('Schalter aus macht wieder Double Out; Neuaufbau, Archiv und Analyse kennen Single Out', () {
    final c = _ctl(legs: 1);
    _stuckAt40(c, 5);
    c.setSingleOut(true);
    c.setSingleOut(false);
    expect((c.engine as X01Game).doubleOutNow, isTrue);
    c.setSingleOut(true);
    // Neuaufbau aus JSON (Neustart / gekoppeltes Gerät)
    final copy = MatchController.fromJson(c.toJson())!;
    expect((copy.engine as X01Game).singleOutLeg, isTrue);
    c.throwDart(const Dart(20, 1));
    c.throwDart(const Dart(20, 1));
    expect(c.engine.finished, isTrue);
    // Archiv
    final r = c.toRecord(1);
    final e = MatchController.replay(r) as X01Game;
    expect(e.finished, isTrue);
    expect(e.legs[0], 1);
    final legs = Analytics.legs(r);
    expect(legs.single.visits.last.singleOut, isTrue);
    expect(legs.single.visits.last.checkout, isTrue);
  });

  test('Steuer-Markierung im kompakten Code', () {
    expect(Dart.fromCode(Dart.singleOutOn.code).mult, 1);
    expect(Dart.fromCode(Dart.singleOutOff.code).mult, 0);
    expect(Dart.fromCode(Dart.singleOutOn.code).isControl, isTrue);
    expect(Dart.fromCode(const Dart(20, 3).code).value, 60);
    expect(Dart.fromCode(const Dart(0, 1).code).isMiss, isTrue);
  });
}

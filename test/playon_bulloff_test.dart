import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/games/x01.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:darts_counter/ui/bull_off.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const miss = Dart(0, 1);

MatchController _ctl(int n) => MatchController(
      config: const GameConfig('x01', {'start': 101, 'doubleOut': true, 'legs': 1}),
      players: [for (var i = 0; i < n; i++) GamePlayer('p$i', 'Spieler$i', i)],
    );

/// Wirft eine komplette Aufnahme.
List<ThrowEvent> _visit(MatchController c, List<Dart> darts) => [for (final d in darts) c.throwDart(d)];

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });

  test('Ausbullen: Reihenfolge, der Letzte kommt automatisch', () {
    expect(completeOrder([2], 3), [2]);
    expect(completeOrder([2, 0], 3), [2, 0, 1]);
    expect(completeOrder([1], 2), [1, 0]);
    expect(completeOrder([3, 1, 0], 8), [3, 1, 0]);
  });

  test('3 Spieler: Sieger, dann um Platz 2 weiterspielen, der Letzte wird automatisch 3.', () {
    final c = _ctl(3);
    final g = c.engine as X01Game;
    // Spieler0 checkt 101: T20 1 D20
    final evs = _visit(c, const [Dart(20, 3), Dart(1, 1), Dart(20, 2)]);
    expect(g.finished, isTrue);
    expect(evs.last.offerPlayOn, 1);
    expect(g.placed, [0]);
    c.playOn();
    expect(g.finished, isFalse);
    expect(g.playingOn, isTrue);
    expect(g.cur, 1); // nach dem Sieger geht es mit Spieler1 weiter
    // Spieler1 checkt ebenfalls 101 → Platz 2, Spieler2 automatisch Platz 3
    final ev2 = _visit(c, const [Dart(20, 3), Dart(1, 1), Dart(20, 2)]);
    expect(g.finished, isTrue);
    expect(g.placed, [0, 1, 2]);
    expect(ev2.last.offerPlayOn, isNull);
    final res = g.results();
    expect([for (final r in res) r.playerIndex], [0, 1, 2]);
    expect([for (final r in res) r.rank], [1, 2, 3]);
    expect(res.first.won, isTrue);
  });

  test('4 Spieler: nach Platz 2 wird erneut gefragt; ausgeschiedene Spieler werden übersprungen', () {
    final c = _ctl(4);
    final g = c.engine as X01Game;
    _visit(c, const [Dart(20, 3), Dart(1, 1), Dart(20, 2)]); // Spieler0 gewinnt
    c.playOn();
    _visit(c, const [miss, miss, miss]); // Spieler1
    final ev = _visit(c, const [Dart(20, 3), Dart(1, 1), Dart(20, 2)]); // Spieler2 → Platz 2
    expect(g.placed, [0, 2]);
    expect(ev.last.offerPlayOn, 2);
    c.playOn();
    expect(g.cur, 3);
    _visit(c, const [miss, miss, miss]); // Spieler3
    expect(g.cur, 1, reason: 'Spieler0 und Spieler2 sind raus');
  });

  test('Beenden: übrige Plätze nach Restpunkten; Rückgängig nimmt das Weiterspielen zurück', () {
    final c = _ctl(3);
    final g = c.engine as X01Game;
    _visit(c, const [Dart(20, 3), Dart(1, 1), Dart(20, 2)]);
    c.playOn();
    expect(c.darts.last, Dart.playOn);
    c.undo(); // nimmt Weiterspielen und den letzten Dart zurück
    final g2 = c.engine as X01Game; // Neuaufbau nach Rückgängig
    expect(g2.finished, isFalse);
    expect(g2.placed, isEmpty);
    expect(g2.scores[0], 40);
    expect(g.placed, [0], reason: 'altes Objekt unverändert');
    // Neuaufbau aus JSON nach Weiterspielen
    c.throwDart(const Dart(20, 2));
    c.playOn();
    final copy = MatchController.fromJson(c.toJson())!;
    expect((copy.engine as X01Game).playingOn, isTrue);
    expect(copy.decided, isTrue);
    // Archiv-Code der Markierung
    expect(Dart.fromCode(Dart.playOn.code), Dart.playOn);
  });
}

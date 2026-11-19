import 'package:darts_counter/data/analytics.dart';
import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

late GamePlayer simon;
late GamePlayer max;

/// 101 Double Out, First to 2 Legs. Simon: Leg 1 in 6 Darts (Fehlversuch auf D20, dann D20),
/// Max wirft dazwischen Nullen. Leg 2: Simon 180 … nein, 101 = T20 S1 D20.
MatchController playKnownMatch() {
  final c = MatchController(
    config: const GameConfig('x01', {'start': 101, 'doubleOut': true, 'legs': 2}),
    players: [simon, max],
  );
  void t(int f, int m) => c.throwDart(Dart(f, m));
  // Leg 1: Simon T20, 1, D10 verfehlt (S10)  → Rest 30… einfacher: T20 1 (Rest 40), dann Miss auf D20 (Rest 40)
  t(20, 3);
  t(1, 1);
  t(0, 1); // Fehlwurf auf D20 (Rest 40)
  // Max: drei Nullen
  t(0, 1);
  t(0, 1);
  t(0, 1);
  // Simon checkt D20
  t(20, 2);
  // Leg 2 (Max beginnt): Max Nullen, Simon T20 1 D20
  t(0, 1);
  t(0, 1);
  t(0, 1);
  t(20, 3);
  t(1, 1);
  t(20, 2);
  return c;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    final a = Store.ensureProfile('Simon');
    final b = Store.ensureProfile('Max');
    simon = GamePlayer(a.id, a.name, 0xFF5AA9FF);
    max = GamePlayer(b.id, b.name, 0xFFF5C84C);
  });

  test('Match wird archiviert und lässt sich in Legs mit Aufnahmen zerlegen', () {
    final c = playKnownMatch();
    expect(c.engine.finished, isTrue);
    c.commitStats();
    expect(Store.archive.length, 1);
    final legs = Analytics.legs(Store.archive.single);
    expect(legs.length, 2);
    final l1 = legs.first;
    expect(l1.winner, 0);
    expect(l1.dartsOfWinner, 4);
    expect(l1.visits.first.score, 61);
    expect(l1.visits.first.rest, 40);
    expect(l1.visits.last.checkout, isTrue);
    expect(l1.visits.last.score, 40);
    expect(legs[1].visits.first.player, 1); // Max beginnt Leg 2
    expect(legs[1].dartsOfWinner, 3);
  });

  test('Historie und Direktvergleich', () {
    playKnownMatch().commitStats();
    playKnownMatch().commitStats();
    final h = Analytics.history(simon.profileId);
    expect(h.length, 2);
    expect(h.first.won, isTrue);
    expect(h.first.myAverage, closeTo(86.57, 0.01));
    final v = Analytics.headToHead(simon.profileId, max.profileId);
    expect(v.matches, 2);
    expect(v.wins, [2, 0]);
    expect(v.legs, [4, 0]);
  });

  test('Doppel-Analyse: Versuche und Treffer auf D20', () {
    playKnownMatch().commitStats();
    final d = Analytics.doubles(simon.profileId, Period.all);
    final d20 = d.firstWhere((x) => x.label == 'D20');
    expect(d20.attempts, 3); // Miss (Rest 40), D20-Treffer, D20-Treffer
    expect(d20.hits, 2);
    expect(d.firstWhere((x) => x.label == 'D16').attempts, 0);
  });

  test('Zeitraum: alte Einträge zählen nur zu „Gesamt“', () {
    playKnownMatch().commitStats();
    final old = PlayerStats()..x01.matches = 5;
    Store.addEntries([
      LogEntry(rid: 'alt', oid: simon.profileId, pid: simon.profileId, t: 0, mode: 'x01', d: old),
    ]);
    expect(Analytics.statsFor(simon.profileId, Period.all).x01.matches, 6);
    expect(Analytics.statsFor(simon.profileId, Period.d7).x01.matches, 1);
    expect(Analytics.statsFor(simon.profileId, Period.today).x01.matches, 1);
    expect(Analytics.timeline(simon.profileId, Period.d30).length, 1);
  });

  test('Erfolge', () {
    playKnownMatch().commitStats();
    final a = Analytics.achievements(simon.profileId);
    expect(a.length, 25);
    bool done(String t) => a.firstWhere((x) => x.title == t).done;
    expect(done('Erster Sieg'), isTrue);
    expect(done('9-Darter'), isTrue); // 3-Dart-Leg
    expect(done('Average 60'), isFalse); // zählt erst ab 9 Darts im Match
    expect(done('Average 100'), isFalse);
    expect(done('Erste 180'), isFalse);
    expect(done('Bullseye-Finish'), isFalse);
  });
}

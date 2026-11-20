import '../games/catalog.dart';
import '../games/engine.dart';
import '../games/x01.dart';
import '../models/dart.dart';
import '../models/player.dart';

/// Werte eines Spielers in einem Leg (oder summiert über das Match).
class PlayerLegStats {
  int darts = 0;
  int points = 0;
  int visits = 0;
  int f9Darts = 0;
  int f9Points = 0;

  /// Darts, die auf ein Double geworfen wurden, als ein Finish möglich war.
  int coAttempts = 0;
  int coHits = 0;
  int highestFinish = 0;
  int c100 = 0;
  int c140 = 0;
  int c180 = 0;
  int highestVisit = 0;
  int legsWon = 0;

  /// Wenigste Darts in einem gewonnenen Leg (0 = keins).
  int bestLeg = 0;

  /// Finish-Wert in diesem Leg (null = nicht gecheckt).
  int? finish;

  /// Trefferbild (Schlüssel wie [Dart.key]).
  final Map<String, int> hits = {};

  double get average => darts == 0 ? 0 : points / darts * 3;
  double get first9 => f9Darts == 0 ? 0 : f9Points / f9Darts * 3;
  double get coRate => coAttempts == 0 ? 0 : coHits / coAttempts * 100;

  void add(PlayerLegStats o) {
    darts += o.darts;
    points += o.points;
    visits += o.visits;
    f9Darts += o.f9Darts;
    f9Points += o.f9Points;
    coAttempts += o.coAttempts;
    coHits += o.coHits;
    if (o.highestFinish > highestFinish) highestFinish = o.highestFinish;
    c100 += o.c100;
    c140 += o.c140;
    c180 += o.c180;
    if (o.highestVisit > highestVisit) highestVisit = o.highestVisit;
    o.hits.forEach((k, v) => hits[k] = (hits[k] ?? 0) + v);
  }
}

/// Ein Leg: Gewinner und Werte aller Spieler.
class LegReport {
  LegReport(this.number, int n) : players = List.generate(n, (_) => PlayerLegStats());
  final int number;
  final List<PlayerLegStats> players;
  int? winner;
  bool singleOut = false;
  bool get finished => winner != null;
}

/// Statistik eines X01-Matches, aus der Wurfliste nachgerechnet
/// (stimmt dadurch auch nach Rückgängig, Single Out und Weiterspielen).
class MatchReport {
  MatchReport(this.players, this.legs, this.total);
  final List<GamePlayer> players;
  final List<LegReport> legs;
  final List<PlayerLegStats> total;

  int get n => players.length;

  /// Zuletzt beendetes Leg.
  LegReport? get lastFinishedLeg => legs.where((l) => l.finished).lastOrNull;

  static MatchReport? build({
    required GameConfig config,
    required List<GamePlayer> players,
    required int startIndex,
    required int seed,
    required List<Dart> darts,
  }) {
    if (config.modeId != 'x01') return null;
    final e = buildEngine(config, players, startIndex, seed) as X01Game;
    final n = players.length;
    final legs = <LegReport>[LegReport(1, n)];
    final visitsInLeg = List.filled(n, 0);
    var visitStart = e.scores[e.cur];
    var visitDarts = 0;

    for (final d in darts) {
      if (d.isControl) {
        e.apply(d);
        continue;
      }
      if (e.finished) break;
      final p = e.cur;
      if (e.turn.isEmpty) {
        visitStart = e.scores[p];
        visitDarts = 0;
      }
      final before = e.scores[p];
      final attempt = e.doubleOutNow && (before == 50 || (before <= 40 && before >= 2 && before.isEven));
      final soLeg = e.singleOutLeg;
      final legsBefore = e.legsPlayed;
      final placedBefore = e.placed.length;
      final ev = e.apply(d);
      visitDarts++;
      final leg = legs.last;
      final s = leg.players[p];
      s.darts++;
      s.hits[d.key] = (s.hits[d.key] ?? 0) + 1;
      if (attempt) s.coAttempts++;

      final legEnded = e.legsPlayed > legsBefore || e.placed.length > placedBefore;
      if (!ev.turnEnded && !legEnded) continue;

      // Aufnahme abgeschlossen
      final score = legEnded ? visitStart : (ev.bust ? 0 : visitStart - e.scores[p]);
      s.points += score;
      s.visits++;
      if (visitsInLeg[p] < 3) {
        s.f9Points += score;
        s.f9Darts += visitDarts;
      }
      visitsInLeg[p]++;
      if (score > s.highestVisit) s.highestVisit = score;
      if (score >= 180) {
        s.c180++;
      } else if (score >= 140) {
        s.c140++;
      } else if (score >= 100) {
        s.c100++;
      }

      if (legEnded) {
        if (attempt) s.coHits++;
        s.finish = visitStart;
        final realFinish = !soLeg || d.isDouble;
        if (realFinish && visitStart > s.highestFinish) s.highestFinish = visitStart;
        if (e.legsPlayed > legsBefore) {
          leg.winner = p;
          leg.singleOut = soLeg && !d.isDouble;
          for (var i = 0; i < n; i++) {
            visitsInLeg[i] = 0;
          }
          if (!e.finished) legs.add(LegReport(legs.length + 1, n));
        }
      }
    }

    // Summen über alle Legs
    final total = List.generate(n, (_) => PlayerLegStats());
    for (final l in legs) {
      for (var i = 0; i < n; i++) {
        total[i].add(l.players[i]);
      }
      final w = l.winner;
      if (w != null) {
        total[w].legsWon++;
        final dd = l.players[w].darts;
        if (total[w].bestLeg == 0 || dd < total[w].bestLeg) total[w].bestLeg = dd;
      }
    }
    // Leeres, noch nicht begonnenes Leg am Ende weglassen
    if (legs.length > 1 && legs.last.players.every((p) => p.darts == 0)) legs.removeLast();
    return MatchReport(players, legs, total);
  }
}

/// Eine Zeile der Vergleichstabelle.
class StatRow {
  const StatRow(this.label, this.values, {this.higherIsBetter = true, this.compare});
  final String label;
  final List<String> values;
  final bool higherIsBetter;

  /// Zahlen zum Vergleichen (null = Zeile ohne Hervorhebung).
  final List<double>? compare;

  /// Index des besten Werts (null bei Gleichstand oder ohne Vergleich).
  int? get best {
    final c = compare;
    if (c == null || c.length < 2) return null;
    final relevant = [for (var i = 0; i < c.length; i++) if (!higherIsBetter && c[i] <= 0) null else c[i]];
    double? top;
    int? idx;
    var tie = false;
    for (var i = 0; i < relevant.length; i++) {
      final v = relevant[i];
      if (v == null) continue;
      if (top == null || (higherIsBetter ? v > top : v < top)) {
        top = v;
        idx = i;
        tie = false;
      } else if (v == top) {
        tie = true;
      }
    }
    return tie ? null : idx;
  }
}

String _f1(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

/// Zeilen der Leg-Statistik.
List<StatRow> legRows(LegReport l) {
  final p = l.players;
  return [
    StatRow('Average', [for (final s in p) _f1(s.average)], compare: [for (final s in p) s.average]),
    StatRow('First 9', [for (final s in p) _f1(s.first9)], compare: [for (final s in p) s.first9]),
    StatRow('Darts', [for (final s in p) '${s.darts}']),
    StatRow('Finish', [for (final s in p) s.finish == null ? '–' : '${s.finish}']),
    StatRow('Darts aufs Double', [for (final s in p) '${s.coAttempts}']),
    StatRow('Checkout-Quote', [for (final s in p) s.coAttempts == 0 ? '–' : '${s.coRate.round()} %'],
        compare: [for (final s in p) s.coRate]),
    StatRow('Höchste Aufnahme', [for (final s in p) '${s.highestVisit}'],
        compare: [for (final s in p) s.highestVisit.toDouble()]),
    StatRow('100+ / 140+ / 180', [for (final s in p) '${s.c100} / ${s.c140} / ${s.c180}']),
  ];
}

/// Zeilen der Match-Statistik.
List<StatRow> matchRows(MatchReport r) {
  final p = r.total;
  return [
    StatRow('Legs', [for (final s in p) '${s.legsWon}'], compare: [for (final s in p) s.legsWon.toDouble()]),
    StatRow('Average', [for (final s in p) _f1(s.average)], compare: [for (final s in p) s.average]),
    StatRow('First 9', [for (final s in p) _f1(s.first9)], compare: [for (final s in p) s.first9]),
    StatRow('Checkout-Quote',
        [for (final s in p) s.coAttempts == 0 ? '–' : '${s.coRate.round()} % (${s.coHits}/${s.coAttempts})'],
        compare: [for (final s in p) s.coRate]),
    StatRow('Höchstes Finish', [for (final s in p) s.highestFinish == 0 ? '–' : '${s.highestFinish}'],
        compare: [for (final s in p) s.highestFinish.toDouble()]),
    StatRow('Bestes Leg', [for (final s in p) s.bestLeg == 0 ? '–' : '${s.bestLeg} Darts'],
        higherIsBetter: false, compare: [for (final s in p) s.bestLeg.toDouble()]),
    StatRow('Höchste Aufnahme', [for (final s in p) '${s.highestVisit}'],
        compare: [for (final s in p) s.highestVisit.toDouble()]),
    StatRow('100+', [for (final s in p) '${s.c100}'], compare: [for (final s in p) s.c100.toDouble()]),
    StatRow('140+', [for (final s in p) '${s.c140}'], compare: [for (final s in p) s.c140.toDouble()]),
    StatRow('180', [for (final s in p) '${s.c180}'], compare: [for (final s in p) s.c180.toDouble()]),
    StatRow('Darts gesamt', [for (final s in p) '${s.darts}']),
  ];
}

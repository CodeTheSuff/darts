import '../games/bot.dart';
import '../games/catalog.dart';
import '../games/engine.dart';
import '../games/x01.dart';
import '../models/dart.dart';
import '../models/player.dart';
import 'match_controller.dart';
import 'storage.dart';

/// Zeitraum für die Statistik.
enum Period { all, d30, d7, today }

extension PeriodX on Period {
  String get label => switch (this) {
        Period.all => 'Gesamt',
        Period.d30 => '30 Tage',
        Period.d7 => '7 Tage',
        Period.today => 'Heute',
      };

  /// Beginn des Zeitraums (null = alles).
  DateTime? since([DateTime? now]) {
    final n = now ?? DateTime.now();
    return switch (this) {
      Period.all => null,
      Period.d30 => n.subtract(const Duration(days: 30)),
      Period.d7 => n.subtract(const Duration(days: 7)),
      Period.today => DateTime(n.year, n.month, n.day),
    };
  }
}

/// Ein Punkt im Verlauf (ein X01-Match).
class TimelinePoint {
  const TimelinePoint(this.t, this.average, this.checkout, this.first9);
  final DateTime t;
  final double average;
  final double checkout;
  final double first9;
}

/// Eine Aufnahme im Leg-Detail.
class Visit {
  Visit(this.player, this.darts, this.score, this.rest,
      {this.bust = false, this.checkout = false, this.singleOut = false});
  final int player;
  final List<Dart> darts;
  final int score;
  final int rest;
  final bool bust;
  final bool checkout;

  /// Leg mit Single Out beendet (ohne Double).
  final bool singleOut;
}

class LegDetail {
  LegDetail(this.number);
  final int number;
  final List<Visit> visits = [];
  int? winner;
  int dartsOfWinner = 0;
}

/// Kurzinfo eines Matches für die Historie.
class MatchSummary {
  MatchSummary(this.record, this.engine, this.me);
  final MatchRecord record;
  final GameEngine engine;

  /// Index des betrachteten Spielers im Match (oder -1).
  final int me;

  DateTime get date => DateTime.fromMillisecondsSinceEpoch(record.t);
  List<PlayerResult> get results => engine.results();
  bool get won => me >= 0 && results.firstWhere((r) => r.playerIndex == me).rank == 1 && engine.n > 1;
  double get myAverage {
    final e = engine;
    return e is X01Game && me >= 0 ? e.stats[me].average : 0;
  }
}

/// Direktvergleich zweier Spieler.
class HeadToHead {
  int matches = 0;
  final wins = [0, 0];
  final legs = [0, 0];
  final avg = [X01Stats(), X01Stats()];
  final List<MatchSummary> list = [];
}

/// Trefferquote auf ein Double.
class DoubleRate {
  DoubleRate(this.label);
  final String label;
  int attempts = 0;
  int hits = 0;
  double get rate => attempts == 0 ? 0 : hits / attempts * 100;
}

class Analytics {
  Analytics._();

  static final Map<String, GameEngine> _cache = {};

  static GameEngine engineOf(MatchRecord r) => _cache.putIfAbsent(r.rid, () => MatchController.replay(r));

  /// Index des lokalen Spielers [pid] in einem archivierten Match.
  static int indexOf(MatchRecord r, String pid) {
    for (var i = 0; i < r.players.length; i++) {
      if (Store.localIdOf(r.players[i].$1) == pid) return i;
    }
    return -1;
  }

  /// Statistik eines Spielers im Zeitraum (der alte Grundstand zählt nur zu „Gesamt“).
  static PlayerStats statsFor(String pid, Period p) {
    final since = p.since();
    if (since == null) return Store.statsFor(pid);
    final s = PlayerStats();
    final from = since.millisecondsSinceEpoch;
    for (final e in Store.log) {
      if (e.pid != pid || e.mode == 'base' || e.t < from) continue;
      s.merge(e.d);
    }
    return s;
  }

  /// Verlauf der X01-Werte pro Match.
  static List<TimelinePoint> timeline(String pid, Period p) {
    final from = p.since()?.millisecondsSinceEpoch ?? 0;
    final pts = <TimelinePoint>[];
    for (final e in Store.log) {
      if (e.pid != pid || e.mode != 'x01' || e.t < from || e.d.x01.darts == 0) continue;
      final x = e.d.x01;
      pts.add(TimelinePoint(DateTime.fromMillisecondsSinceEpoch(e.t), x.average, x.coRate, x.first9));
    }
    pts.sort((a, b) => a.t.compareTo(b.t));
    return pts;
  }

  /// Alle archivierten Matches eines Spielers, neueste zuerst.
  static List<MatchSummary> history(String pid, {Period p = Period.all, String? mode}) {
    final from = p.since()?.millisecondsSinceEpoch ?? 0;
    final out = <MatchSummary>[];
    for (final r in Store.archive.reversed) {
      if (r.t < from || (mode != null && r.mode != mode)) continue;
      final i = indexOf(r, pid);
      if (i < 0) continue;
      try {
        out.add(MatchSummary(r, engineOf(r), i));
      } catch (_) {}
    }
    return out;
  }

  /// Legs eines X01-Matches mit allen Aufnahmen.
  static final Map<String, List<LegDetail>> _legCache = {};

  static List<LegDetail> legs(MatchRecord r) => _legCache.putIfAbsent(r.rid, () => _legs(r));

  static List<LegDetail> _legs(MatchRecord r) {
    if (r.mode != 'x01') return [];
    final e = buildEngine(
      GameConfig(r.mode, r.options),
      [for (final (id, n, c) in r.players) GamePlayer(id, n, c)],
      r.start,
      r.seed,
    ) as X01Game;
    final out = <LegDetail>[LegDetail(1)];
    var turn = <Dart>[];
    var visitStart = e.scores[e.cur];
    for (final code in r.darts) {
      if (e.finished) break;
      final d = Dart.fromCode(code);
      if (d.isControl) {
        e.apply(d);
        continue;
      }
      final p = e.cur;
      if (e.turn.isEmpty) visitStart = e.scores[p];
      turn.add(d);
      final legsBefore = e.legsPlayed;
      final ev = e.apply(d);
      final leg = out.last;
      if (e.legsPlayed > legsBefore) {
        leg.visits.add(Visit(p, List.of(turn), visitStart, 0, checkout: true, singleOut: ev.singleOutFinish));
        leg.winner = p;
        leg.dartsOfWinner = leg.visits.where((v) => v.player == p).fold(0, (a, v) => a + v.darts.length);
        turn = [];
        if (!e.finished) out.add(LegDetail(out.length + 1));
      } else if (ev.turnEnded) {
        final rest = e.scores[p];
        leg.visits.add(Visit(p, List.of(turn), ev.bust ? 0 : visitStart - rest, rest, bust: ev.bust));
        turn = [];
      }
    }
    if (turn.isNotEmpty && !e.finished) {
      out.last.visits.add(Visit(e.cur, List.of(turn), sumOf(turn), e.scores[e.cur]));
    }
    return out.where((l) => l.visits.isNotEmpty).toList();
  }

  /// Direktvergleich: X01-Matches, in denen beide gespielt haben.
  static HeadToHead headToHead(String a, String b) {
    final h = HeadToHead();
    for (final r in Store.archive.reversed) {
      if (r.mode != 'x01') continue;
      final ia = indexOf(r, a);
      final ib = indexOf(r, b);
      if (ia < 0 || ib < 0) continue;
      final GameEngine e;
      try {
        e = engineOf(r);
      } catch (_) {
        continue;
      }
      if (!e.finished || e is! X01Game) continue;
      h.matches++;
      final res = e.results();
      final ra = res.firstWhere((x) => x.playerIndex == ia).rank;
      final rb = res.firstWhere((x) => x.playerIndex == ib).rank;
      if (ra < rb) h.wins[0]++;
      if (rb < ra) h.wins[1]++;
      h.legs[0] += e.legsTotal[ia];
      h.legs[1] += e.legsTotal[ib];
      h.avg[0].merge(e.stats[ia]);
      h.avg[1].merge(e.stats[ib]);
      h.list.add(MatchSummary(r, e, ia));
    }
    return h;
  }

  /// Trefferquote je Double: jeder Dart auf einen Rest, bei dem ein Double das Leg beendet.
  static List<DoubleRate> doubles(String pid, Period p) {
    final from = p.since()?.millisecondsSinceEpoch ?? 0;
    final rates = {for (var i = 1; i <= 20; i++) i: DoubleRate('D$i'), 25: DoubleRate('Bull')};
    for (final r in Store.archive) {
      if (r.mode != 'x01' || r.t < from || r.options['doubleOut'] != true) continue;
      final me = indexOf(r, pid);
      if (me < 0) continue;
      final GameEngine e0;
      try {
        e0 = buildEngine(GameConfig(r.mode, r.options), [for (final (id, n, c) in r.players) GamePlayer(id, n, c)],
            r.start, r.seed);
      } catch (_) {
        continue;
      }
      final e = e0 as X01Game;
      for (final code in r.darts) {
        final d = Dart.fromCode(code);
        if (e.cur == me && !d.isControl && e.doubleOutNow) {
          final rest = e.scores[me];
          final target = rest == 50 ? 25 : (rest <= 40 && rest >= 2 && rest.isEven ? rest ~/ 2 : null);
          if (target != null) {
            final rt = rates[target]!;
            rt.attempts++;
            if (d.isDouble && d.value == rest) rt.hits++;
          }
        }
        e.apply(d);
        if (e.finished) break;
      }
    }
    return rates.values.toList();
  }

  // ------------------------------------------------------------ Erfolge

  static List<Achievement> achievements(String pid) {
    final s = Store.statsFor(pid);
    final x = s.x01;
    var bullFinish = false;
    var bestMatchAvg = 0.0;
    var won = 0;
    for (final m in history(pid, mode: 'x01')) {
      final e = m.engine;
      if (e is! X01Game || m.me < 0) continue;
      if (e.stats[m.me].darts >= 9 && e.stats[m.me].average > bestMatchAvg) bestMatchAvg = e.stats[m.me].average;
      if (m.won) won++;
      if (!bullFinish) {
        for (final leg in legs(m.record)) {
          final last = leg.visits.isEmpty ? null : leg.visits.last;
          if (last != null && last.checkout && last.player == m.me && last.darts.last.isBull && last.darts.last.mult == 2) {
            bullFinish = true;
            break;
          }
        }
      }
    }
    final wins = x.matchesWon > won ? x.matchesWon : won;
    bool beat(BotLevel l) => (s.bots[l.name]?[0] ?? 0) > 0;
    return [
      Achievement('Erste 180', 'Wirf eine 180', x.c180 >= 1, x.c180.clamp(0, 1), 1),
      Achievement('180er-Sammler', '10 × 180', x.c180 >= 10, x.c180.clamp(0, 10), 10),
      Achievement('Maximum-Maschine', '50 × 180', x.c180 >= 50, x.c180.clamp(0, 50), 50),
      Achievement('Ton-Plus', '100 × 140+', x.c140 + x.c180 >= 100, (x.c140 + x.c180).clamp(0, 100), 100),
      Achievement('High Finish', 'Checke 100 oder mehr', x.highestFinish >= 100, null, null),
      Achievement('Big Fish', 'Checke 170', x.highestFinish >= 170, null, null),
      Achievement('Bullseye-Finish', 'Checke mit dem Bull', bullFinish, null, null),
      Achievement('9-Darter', 'Leg mit 9 Darts', x.bestLeg > 0 && x.bestLeg <= 9, null, null),
      Achievement('12-Darter', 'Leg mit höchstens 12 Darts', x.bestLeg > 0 && x.bestLeg <= 12, null, null),
      Achievement('15-Darter', 'Leg mit höchstens 15 Darts', x.bestLeg > 0 && x.bestLeg <= 15, null, null),
      Achievement('Average 60', 'Match-Average 60+', bestMatchAvg >= 60, null, null),
      Achievement('Average 80', 'Match-Average 80+', bestMatchAvg >= 80, null, null),
      Achievement('Average 100', 'Match-Average 100+', bestMatchAvg >= 100, null, null),
      Achievement('Erster Sieg', 'Gewinne ein X01-Match', wins >= 1, wins.clamp(0, 1), 1),
      Achievement('Siegertyp', '10 Matches gewonnen', wins >= 10, wins.clamp(0, 10), 10),
      Achievement('Seriensieger', '50 Matches gewonnen', wins >= 50, wins.clamp(0, 50), 50),
      Achievement('Stammspieler', '100 X01-Matches', x.matches >= 100, x.matches.clamp(0, 100), 100),
      Achievement('Bot-Bezwinger', 'Besiege den leichten Bot', beat(BotLevel.easy), null, null),
      Achievement('Mittelfeld', 'Besiege den mittleren Bot', beat(BotLevel.medium), null, null),
      Achievement('Schwergewicht', 'Besiege den schweren Bot', beat(BotLevel.hard), null, null),
      Achievement('Profi-Killer', 'Besiege den Profi-Bot', beat(BotLevel.pro), null, null),
      Achievement('Auf dem Podest', 'Platz 1–3 in einem Turnier', s.podiums >= 1, null, null),
      Achievement('Turniersieger', 'Gewinne ein Turnier', s.tournamentWins >= 1, null, null),
      Achievement('Champion', '10 Turniersiege', s.tournamentWins >= 10, s.tournamentWins.clamp(0, 10), 10),
      Achievement('Allrounder', '5 verschiedene Modi gespielt', s.modes.length >= 5, s.modes.length.clamp(0, 5), 5),
    ];
  }
}

class Achievement {
  const Achievement(this.title, this.text, this.done, this.progress, this.goal);
  final String title;
  final String text;
  final bool done;
  final int? progress;
  final int? goal;
}

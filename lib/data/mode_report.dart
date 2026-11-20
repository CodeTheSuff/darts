import '../games/catalog.dart';
import '../games/engine.dart';
import '../models/dart.dart';
import '../models/player.dart';
import 'match_report.dart' show StatRow;

/// Werte eines Spielers in einem Trainings- oder Minispiel.
class ModePlayerStats {
  int darts = 0;

  /// Darts, bei denen ein Ziel vorgegeben war, und davon Treffer aufs Ziel.
  int targetDarts = 0;
  int targetHits = 0;
  int visits = 0;
  int points = 0;
  int bestVisit = 0;
  int c100 = 0;
  int c140 = 0;
  int c180 = 0;

  /// Cricket: Marks auf 15–20 und Bull.
  int marks = 0;
  final Map<String, int> hits = {};

  double get average => darts == 0 ? 0 : points / darts * 3;
  double get targetRate => targetDarts == 0 ? 0 : targetHits / targetDarts * 100;
  double get mpr => darts == 0 ? 0 : marks / darts * 3;
}

/// Statistik eines Trainings- oder Minispiels, aus der Wurfliste nachgerechnet.
class ModeReport {
  ModeReport(this.modeId, this.players);
  final String modeId;
  final List<ModePlayerStats> players;

  static const _cricket = {15, 16, 17, 18, 19, 20, 25};

  static bool _isHit(Dart d, List<Target> tg) =>
      d.field != 0 && tg.any((t) => t.field == d.field && (t.mult == null || t.mult == d.mult));

  static ModeReport? build({
    required GameConfig config,
    required List<GamePlayer> players,
    required int startIndex,
    required int seed,
    required List<Dart> darts,
  }) {
    if (config.modeId == 'x01') return null;
    final e = buildEngine(config, players, startIndex, seed);
    final stats = List.generate(players.length, (_) => ModePlayerStats());
    var visit = 0;
    for (final d in darts) {
      if (d.isControl) {
        e.apply(d);
        continue;
      }
      if (e.finished) break;
      final p = e.cur;
      final s = stats[p];
      final tg = e.targets;
      if (tg.isNotEmpty) {
        s.targetDarts++;
        if (_isHit(d, tg)) s.targetHits++;
      }
      if (config.modeId == 'cricket' && _cricket.contains(d.field)) s.marks += d.mult;
      s.darts++;
      s.hits[d.key] = (s.hits[d.key] ?? 0) + 1;
      visit += d.value;
      final ev = e.apply(d);
      if (ev.turnEnded || ev.gameOver) {
        s.visits++;
        s.points += visit;
        if (visit > s.bestVisit) s.bestVisit = visit;
        if (visit >= 180) {
          s.c180++;
        } else if (visit >= 140) {
          s.c140++;
        } else if (visit >= 100) {
          s.c100++;
        }
        visit = 0;
      }
    }
    return ModeReport(config.modeId, stats);
  }
}

String _f1(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

/// Zeilen der Statistik passend zum Modus. [results] liefert das Ergebnis je Spieler.
List<StatRow> modeRows(ModeReport r, List<PlayerResult> results) {
  final p = r.players;
  final byIndex = {for (final x in results) x.playerIndex: x};
  final id = r.modeId;
  final hasTargets = p.any((s) => s.targetDarts > 0);
  final scoringLike = const {'scoring', 'highscore', 'catch40', 'checkout', '121'}.contains(id);
  return [
    StatRow('Ergebnis', [for (var i = 0; i < p.length; i++) byIndex[i]?.value ?? '–']),
    StatRow('Darts', [for (final s in p) '${s.darts}']),
    if (id == 'cricket')
      StatRow('Marks pro Runde', [for (final s in p) _f1(s.mpr)], compare: [for (final s in p) s.mpr]),
    if (id == 'bobs27')
      StatRow('Doubles getroffen', [for (final s in p) '${s.targetHits} / ${s.targetDarts}'],
          compare: [for (final s in p) s.targetRate])
    else if (id == 'atc')
      StatRow('Darts pro Ziel', [for (final s in p) s.targetHits == 0 ? '–' : _f1(s.darts / s.targetHits)],
          higherIsBetter: false,
          compare: [for (final s in p) s.targetHits == 0 ? 0 : s.darts / s.targetHits])
    else if (hasTargets && id != 'scoring')
      StatRow('Zieltreffer', [for (final s in p) s.targetDarts == 0 ? '–' : '${s.targetRate.round()} %'],
          compare: [for (final s in p) s.targetRate]),
    if (id == 'scoring')
      StatRow('Treffer aufs Triple', [for (final s in p) s.targetDarts == 0 ? '–' : '${s.targetRate.round()} %'],
          compare: [for (final s in p) s.targetRate]),
    if (scoringLike) StatRow('Average', [for (final s in p) _f1(s.average)], compare: [for (final s in p) s.average]),
    StatRow('Beste Aufnahme', [for (final s in p) '${s.bestVisit}'],
        compare: [for (final s in p) s.bestVisit.toDouble()]),
    if (id == 'scoring' || id == 'highscore')
      StatRow('100+ / 140+ / 180', [for (final s in p) '${s.c100} / ${s.c140} / ${s.c180}']),
  ];
}

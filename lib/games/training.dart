import 'dart:math';

import '../models/dart.dart';
import '../models/player.dart';
import 'checkout.dart';
import 'engine.dart';

// ======================================================================
// Around the Clock
// ======================================================================

/// Varianten: classic (Double/Triple springen), single (ohne Sprünge),
/// doubles (nur Doubles zählen), triples (nur Triples zählen).
class AroundTheClockGame extends GameEngine {
  AroundTheClockGame(super.players, super.config,
      {super.startIndex, super.seed})
      : variant = config.opt<String>('variant') {
    progress = List.filled(n, 0);
    darts = List.filled(n, 0);
    hitCount = List.filled(n, 0);
  }

  final String variant;
  late List<int> progress; // 0..19 = Zahl 1..20, 20 = Bull, 21 = fertig
  late List<int> darts;
  late List<int> hitCount;
  int? winner;

  static const bullStep = 20;

  int? _ringFor() => switch (variant) {
        'doubles' => 2,
        'triples' => 3,
        _ => null,
      };

  String _targetLabel(int step) {
    if (step >= 21) return 'Fertig';
    if (step == bullStep) return variant == 'doubles' ? 'Bull' : 'Bull';
    final num = step + 1;
    return switch (variant) {
      'doubles' => 'D$num',
      'triples' => 'T$num',
      _ => '$num',
    };
  }

  @override
  void onDart(Dart d, ThrowEvent ev) {
    final p = cur;
    darts[p]++;
    final step = progress[p];
    var advance = 0;
    if (step == bullStep) {
      final ok = d.isBull && (variant == 'doubles' ? d.mult == 2 : true);
      if (ok) advance = 1;
    } else {
      final num = step + 1;
      if (d.field == num) {
        advance = switch (variant) {
          'classic' => d.mult,
          'single' => 1,
          'doubles' => d.mult == 2 ? 1 : 0,
          'triples' => d.mult == 3 ? 1 : 0,
          _ => 1,
        };
      }
    }
    if (advance > 0) {
      hitCount[p]++;
      if (step == bullStep) {
        progress[p] = 21;
        winner = p;
        ev.message = '${players[p].name} ist rum!';
        ev.celebration = Celebration.legWon;
        ev.celebrationValue = darts[p];
        finishGame();
        return;
      }
      progress[p] = min(step + advance, bullStep);
    }
  }

  @override
  String get title => switch (variant) {
        'classic' => 'Around the Clock',
        'single' => 'Around the Clock · ohne Sprünge',
        'doubles' => 'Around the Clock · Doubles',
        'triples' => 'Around the Clock · Triples',
        _ => 'Around the Clock',
      };

  @override
  String get subtitle => 'Runde $round';

  @override
  String mainValue(int i) => _targetLabel(progress[i]);

  @override
  String? subLine(int i) {
    final rate = darts[i] == 0 ? 0 : hitCount[i] / darts[i] * 100;
    return '${min(progress[i], 21)}/21 · ${darts[i]} Darts · ${rate.round()} %';
  }

  @override
  String lastLine(int i) {
    final t = lastTurns[i];
    if (t.isEmpty) return '–';
    return t.map((d) => d.label).join(' ');
  }

  @override
  bool get showTurnSum => false;

  @override
  Hint? get hint => Hint('Ziel', _targetLabel(progress[cur]), strong: true);

  @override
  List<Target> get targets {
    final step = progress[cur];
    if (step >= 21) return const [];
    if (step == bullStep) return [Target(25, variant == 'doubles' ? 2 : null)];
    return [Target(step + 1, _ringFor())];
  }

  /// Nur das Zielfeld ist relevant → große Treffer-Tasten + Miss.
  @override
  InputSpec get input {
    final step = progress[cur];
    if (step == bullStep) {
      if (variant == 'doubles') {
        return const InputSpec.buttons([QuickButton(25, 2, 'Bull', 'Getroffen')]);
      }
      return const InputSpec.buttons([
        QuickButton(25, 1, '25', 'Single Bull'),
        QuickButton(25, 2, 'Bull', 'Bullseye'),
      ]);
    }
    final n = step + 1;
    return switch (variant) {
      'classic' => InputSpec.buttons([
          QuickButton(n, 1, '$n', 'Single · +1'),
          QuickButton(n, 2, 'D$n', 'Double · +2'),
          QuickButton(n, 3, 'T$n', 'Triple · +3'),
        ]),
      'doubles' => InputSpec.buttons([QuickButton(n, 2, 'D$n', 'Getroffen')]),
      'triples' => InputSpec.buttons([QuickButton(n, 3, 'T$n', 'Getroffen')]),
      _ => InputSpec.buttons([QuickButton(n, 1, '$n', 'Getroffen')]),
    };
  }

  @override
  List<PlayerResult> results() {
    final list = [
      for (var i = 0; i < n; i++)
        PlayerResult(
          playerIndex: i,
          value: progress[i] >= 21 ? '${darts[i]} Darts' : '${progress[i]}/21',
          detail:
              'Trefferquote ${darts[i] == 0 ? 0 : (hitCount[i] / darts[i] * 100).round()} %',
          metric: progress[i] >= 21 ? darts[i] : null,
        )
    ];
    return rankBy(list, (r) => progress[r.playerIndex] * 10000 - darts[r.playerIndex]);
  }
}

// ======================================================================
// Bob's 27
// ======================================================================

class Bobs27Game extends GameEngine {
  Bobs27Game(super.players, super.config, {super.startIndex, super.seed}){
    scores = List.filled(n, 27);
    outRound = List.filled(n, 0);
    doubleHits = List.filled(n, 0);
  }

  late List<int> scores;
  late List<int> outRound; // 0 = noch dabei
  late List<int> doubleHits;

  static const rounds = 21; // D1..D20 + Bull

  int _targetValue(int r) => r == 21 ? 50 : r * 2;
  String _label(int r) => r == 21 ? 'Bull' : 'D$r';

  bool _hit(Dart d, int r) => r == 21 ? (d.isBull && d.mult == 2) : (d.isDouble && d.field == r);

  @override
  bool isOut(int i) => outRound[i] > 0;

  @override
  void onDart(Dart d, ThrowEvent ev) {}

  @override
  void onTurnComplete(ThrowEvent ev) {
    final p = cur;
    final hits = turn.where((d) => _hit(d, round)).length;
    final v = _targetValue(round);
    doubleHits[p] += hits;
    if (hits > 0) {
      scores[p] += hits * v;
      ev.message = '${players[p].name}: +${hits * v}';
    } else {
      scores[p] -= v;
      ev.message = '${players[p].name}: −$v';
      if (scores[p] <= 0) {
        outRound[p] = round;
        ev.message = '${players[p].name} ist raus (Runde $round)';
        ev.bust = true;
      }
    }
    if (List.generate(n, isOut).every((o) => o)) {
      finishGame();
    }
  }

  @override
  void onNewRound() {
    if (round > rounds) finishGame();
  }

  @override
  String get title => "Bob's 27";

  @override
  String get subtitle => 'Runde ${min(round, rounds)} / $rounds · Ziel ${_label(min(round, rounds))}';

  @override
  String mainValue(int i) => isOut(i) ? 'Raus' : '${scores[i]}';

  @override
  String? subLine(int i) => 'Doubles getroffen: ${doubleHits[i]}';

  @override
  String lastLine(int i) {
    final t = lastTurns[i];
    if (t.isEmpty) return '–';
    return t.map((d) => d.label).join(' ');
  }

  @override
  bool get showTurnSum => false;

  @override
  Hint? get hint => Hint('Ziel', '${_label(round)} · Treffer +${_targetValue(round)}', strong: true);

  @override
  List<Target> get targets => [round == 21 ? const Target(25, 2) : Target(round, 2)];

  @override
  InputSpec get input => round == 21
      ? const InputSpec.buttons([QuickButton(25, 2, 'Bull', 'Treffer · +50')])
      : InputSpec.buttons([QuickButton(round, 2, 'D$round', 'Treffer · +${round * 2}')]);

  @override
  List<PlayerResult> results() {
    final list = [
      for (var i = 0; i < n; i++)
        PlayerResult(
          playerIndex: i,
          value: isOut(i) ? 'Raus in Runde ${outRound[i]}' : '${scores[i]} Punkte',
          detail: 'Doubles getroffen: ${doubleHits[i]}',
          metric: isOut(i) ? null : scores[i],
        )
    ];
    return rankBy(list, (r) {
      final i = r.playerIndex;
      return isOut(i) ? outRound[i] - 100000 : scores[i];
    });
  }
}

// ======================================================================
// Checkout-Training, 121 und Catch 40
// ======================================================================

/// kind: 'training' (Zufallszahl für alle, 9 Darts),
///       '121'      (eigenes Ziel ab 121, 9 Darts, Erfolg = +1, sonst 121),
///       'catch40'  (61, 62, …, 6 Darts, Punkte 3/2/1).
class CheckoutChallengeGame extends GameEngine {
  CheckoutChallengeGame(List<GamePlayer> players, GameConfig config,
      {super.startIndex, super.seed, required this.kind})
      : rounds = config.opt<int>('rounds'),
        super(players, config) {
    score = List.filled(n, 0);
    successes = List.filled(n, 0);
    best = List.filled(n, 0);
    ownTarget = List.filled(n, 121);
    if (kind == 'training') {
      final range = config.opt<String>('range').split('-').map(int.parse).toList();
      final lo = range[0], hi = range[1];
      roundTargets = [];
      while (roundTargets.length < rounds) {
        final t = lo + rng.nextInt(hi - lo + 1);
        if (!bogeyNumbers.contains(t)) roundTargets.add(t);
      }
    } else if (kind == 'catch40') {
      roundTargets = List.generate(rounds, (i) => 61 + i);
    } else {
      roundTargets = const [];
    }
  }

  final String kind;
  final int rounds;
  late List<int> score;
  late List<int> successes;
  late List<int> best;
  late List<int> ownTarget;
  late List<int> roundTargets;

  int target = 0;
  int rest = 0;
  int visitStart = 0;
  int used = 0;
  int visitIndex = 0; // Index in [turn], an dem die aktuelle Aufnahme beginnt

  int get allowed => kind == 'catch40' ? 6 : 9;

  @override
  int get dartsPerTurn => 999; // Ende wird selbst gesteuert

  @override
  void onTurnStart() {
    target = kind == '121' ? ownTarget[cur] : roundTargets[min(round, rounds) - 1];
    rest = target;
    visitStart = target;
    used = 0;
    visitIndex = 0;
  }

  @override
  void onNewRound() {
    if (round > rounds) finishGame();
  }

  @override
  void onDart(Dart d, ThrowEvent ev) {
    used++;
    final r = rest - d.value;
    final bust = r < 0 || r == 1 || (r == 0 && !d.isDouble);
    if (bust) {
      rest = visitStart;
      used = ((used + 2) ~/ 3) * 3;
      visitIndex = turn.length;
      ev.bust = true;
      ev.message = 'Bust! Zurück auf $visitStart';
      if (used >= allowed) _finishAttempt(ev, false);
      return;
    }
    if (r == 0) {
      _finishAttempt(ev, true);
      return;
    }
    rest = r;
    if (used % 3 == 0) {
      visitStart = rest;
      visitIndex = turn.length;
    }
    if (used >= allowed) _finishAttempt(ev, false);
  }

  void _finishAttempt(ThrowEvent ev, bool success) {
    final p = cur;
    final name = players[p].name;
    if (success) {
      successes[p]++;
      switch (kind) {
        case 'training':
          score[p]++;
          ev.message = '$name checkt $target in $used Darts!';
        case '121':
          if (target > best[p]) best[p] = target;
          score[p] = max(score[p], target);
          ownTarget[p] = target + 1;
          ev.message = '$name checkt $target! Weiter mit ${target + 1}';
        case 'catch40':
          final pts = used <= 2 ? 3 : used == 3 ? 2 : 1;
          score[p] += pts;
          ev.message = '$name checkt $target: +$pts';
      }
      ev.celebration = target >= 100 ? Celebration.highFinish : Celebration.legWon;
      ev.celebrationValue = target;
    } else {
      switch (kind) {
        case '121':
          ownTarget[p] = 121;
          ev.message = '$name schafft $target nicht – zurück auf 121';
        default:
          ev.message = '$name schafft $target nicht';
      }
    }
    endTurn(ev);
  }

  @override
  List<Dart> get visibleTurn => turn.sublist(min(visitIndex, turn.length));

  @override
  bool get showTurnSum => true;

  @override
  String get title => switch (kind) {
        'training' => 'Checkout-Training',
        '121' => '121',
        _ => 'Catch 40',
      };

  @override
  String get subtitle {
    final r = min(round, rounds);
    return 'Runde $r / $rounds · Ziel $target · Dart ${min(used + 1, allowed)}/$allowed';
  }

  @override
  String mainValue(int i) {
    switch (kind) {
      case '121':
        return '${ownTarget[i]}';
      case 'catch40':
        return '${score[i]} P';
      default:
        return '${score[i]}/${min(round, rounds)}';
    }
  }

  @override
  String activeValue() => '$rest';

  @override
  String? subLine(int i) => switch (kind) {
        '121' => 'Bestes: ${best[i] == 0 ? '–' : best[i]} · Checks ${successes[i]}',
        'catch40' => 'Checks ${successes[i]}',
        _ => 'Checks ${successes[i]}',
      };

  @override
  String lastLine(int i) {
    final t = lastTurns[i];
    if (t.isEmpty) return '–';
    return '${t.length} Darts';
  }

  @override
  Hint? get hint {
    final left = 3 - (used % 3);
    final co = findCheckout(rest, left);
    if (co != null) return Hint('Checkout', co.join(' · '), strong: true);
    return Hint(null, 'Kein Finish mit $left ${left == 1 ? 'Dart' : 'Darts'}');
  }

  @override
  List<PlayerResult> results() {
    final list = [
      for (var i = 0; i < n; i++)
        PlayerResult(
          playerIndex: i,
          value: switch (kind) {
            '121' => best[i] == 0 ? 'Kein Check' : 'Bestes: ${best[i]}',
            'catch40' => '${score[i]} Punkte',
            _ => '${score[i]} / $rounds',
          },
          detail: 'Checks: ${successes[i]}',
          metric: kind == '121' ? best[i] : score[i],
        )
    ];
    return rankBy(list, (r) => r.metric!);
  }
}

// ======================================================================
// Scoring (frei wählbare Anzahl Darts)
// ======================================================================

class ScoringGame extends GameEngine {
  ScoringGame(super.players, super.config, {super.startIndex, super.seed})
      : total = config.opt<int>('darts'),
        aim = config.opt<int>('target') {
    thrown = List.filled(n, 0);
    points = List.filled(n, 0);
    onTarget = List.filled(n, 0);
    triples = List.filled(n, 0);
    highest = List.filled(n, 0);
  }

  final int total;
  final int aim; // 20, 19 oder 0 = frei
  late List<int> thrown;
  late List<int> points;
  late List<int> onTarget;
  late List<int> triples;
  late List<int> highest;

  @override
  bool isOut(int i) => thrown[i] >= total;

  @override
  void onDart(Dart d, ThrowEvent ev) {
    final p = cur;
    thrown[p]++;
    points[p] += d.value;
    if (aim == 0 || d.field == aim) {
      if (!d.isMiss) onTarget[p]++;
      if (d.isTriple) triples[p]++;
    }
    if (thrown[p] >= total && turn.length < 3) {
      onTurnComplete(ev);
      if (List.generate(n, isOut).every((o) => o)) {
        finishGame();
        return;
      }
      endTurn(ev);
    }
  }

  @override
  void onTurnComplete(ThrowEvent ev) {
    final sum = sumOf(turn);
    if (sum > highest[cur]) highest[cur] = sum;
    final c = celebrationForScore(sum);
    if (c != null) {
      ev.celebration = c;
      ev.celebrationValue = sum;
    }
    if (List.generate(n, isOut).every((o) => o)) finishGame();
  }

  double avg(int i) => thrown[i] == 0 ? 0 : points[i] / thrown[i] * 3;

  @override
  String get title => aim == 0 ? 'Scoring · frei' : 'Scoring · T$aim';

  @override
  String get subtitle => '$total Darts pro Spieler';

  @override
  String mainValue(int i) => '${points[i]}';

  @override
  String? subLine(int i) => 'Ø ${fmt1(avg(i))} · ${thrown[i]}/$total Darts';

  @override
  Hint? get hint {
    final left = total - thrown[cur];
    final rate = thrown[cur] == 0 ? 0 : (triples[cur] / thrown[cur] * 100).round();
    return Hint(aim == 0 ? 'Frei' : 'Ziel T$aim',
        'Noch $left Darts${aim == 0 ? '' : ' · Triple-Quote $rate %'}');
  }

  @override
  List<Target> get targets => aim == 0 ? const [] : [Target(aim, 3)];

  @override
  List<PlayerResult> results() {
    final list = [
      for (var i = 0; i < n; i++)
        PlayerResult(
          playerIndex: i,
          value: '${points[i]} Punkte',
          detail:
              'Ø ${fmt1(avg(i))} · Höchste ${highest[i]}${aim == 0 ? '' : ' · T$aim: ${triples[i]}×'}',
          metric: avg(i),
        )
    ];
    return rankBy(list, (r) => points[r.playerIndex]);
  }
}

// ======================================================================
// Halve It: 15, 16, D, 17, 18, T, 19, 20, Bull
// ======================================================================

class HalveItGame extends GameEngine {
  HalveItGame(super.players, super.config, {super.startIndex, super.seed}){
    scores = List.filled(n, 0);
    halved = List.filled(n, 0);
  }

  static const steps = ['15', '16', 'D', '17', '18', 'T', '19', '20', 'B'];
  late List<int> scores;
  late List<int> halved;

  String get step => steps[min(round, steps.length) - 1];

  String stepLabel(String s) => switch (s) {
        'D' => 'Irgendein Double',
        'T' => 'Irgendein Triple',
        'B' => 'Bull',
        _ => s,
      };

  bool _hit(Dart d, String s) => switch (s) {
        'D' => d.isDouble,
        'T' => d.isTriple,
        'B' => d.isBull,
        _ => d.field == int.parse(s),
      };

  @override
  void onDart(Dart d, ThrowEvent ev) {}

  @override
  void onTurnComplete(ThrowEvent ev) {
    final p = cur;
    final pts = turn.where((d) => _hit(d, step)).fold(0, (a, d) => a + d.value);
    if (pts == 0) {
      scores[p] = scores[p] ~/ 2;
      halved[p]++;
      ev.bust = true;
      ev.message = '${players[p].name}: halbiert auf ${scores[p]}';
    } else {
      scores[p] += pts;
      ev.message = '${players[p].name}: +$pts';
    }
  }

  @override
  void onNewRound() {
    if (round > steps.length) finishGame();
  }

  @override
  String get title => 'Halve It';

  @override
  String get subtitle => 'Runde ${min(round, steps.length)} / ${steps.length} · ${stepLabel(step)}';

  @override
  String mainValue(int i) => '${scores[i]}';

  @override
  String? subLine(int i) => 'Halbiert: ${halved[i]}×';

  @override
  Hint? get hint => Hint('Ziel', stepLabel(step), strong: true);

  @override
  List<Target> get targets => switch (step) {
        'D' => const [Target(-1, 2)],
        'T' => const [Target(-1, 3)],
        'B' => const [Target(25)],
        _ => [Target(int.parse(step))],
      };

  @override
  InputSpec get input {
    switch (step) {
      case 'D':
        return const InputSpec.full(lockedMult: 2, title: 'Irgendein Double – Zahl antippen');
      case 'T':
        return const InputSpec.full(lockedMult: 3, title: 'Irgendein Triple – Zahl antippen');
      case 'B':
        return const InputSpec.buttons([
          QuickButton(25, 1, '25', '+25'),
          QuickButton(25, 2, 'Bull', '+50'),
        ]);
      default:
        final n = int.parse(step);
        return InputSpec.buttons([
          QuickButton(n, 1, '$n', '+$n'),
          QuickButton(n, 2, 'D$n', '+${n * 2}'),
          QuickButton(n, 3, 'T$n', '+${n * 3}'),
        ]);
    }
  }

  @override
  List<PlayerResult> results() {
    final list = [
      for (var i = 0; i < n; i++)
        PlayerResult(
          playerIndex: i,
          value: '${scores[i]} Punkte',
          detail: 'Halbiert: ${halved[i]}×',
          metric: scores[i],
        )
    ];
    return rankBy(list, (r) => r.metric!);
  }
}

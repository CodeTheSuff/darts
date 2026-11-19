import 'dart:math';

import '../models/dart.dart';
import 'engine.dart';

// ======================================================================
// Cricket
// ======================================================================

class CricketGame extends GameEngine {
  CricketGame(super.players, super.config, {super.startIndex, super.seed})
      : maxRounds = config.opt<int>('rounds') {
    marks = List.generate(n, (_) => List.filled(numbers.length, 0));
    points = List.filled(n, 0);
  }

  static const numbers = [20, 19, 18, 17, 16, 15, 25];
  final int maxRounds;
  late List<List<int>> marks;
  late List<int> points;
  int? winner;

  int closedCount(int i) => marks[i].where((m) => m >= 3).length;
  bool allClosed(int i) => closedCount(i) == numbers.length;

  @override
  void onDart(Dart d, ThrowEvent ev) {
    final k = numbers.indexOf(d.field);
    if (k < 0) return;
    final p = cur;
    for (var h = 0; h < d.mult; h++) {
      if (marks[p][k] < 3) {
        marks[p][k]++;
      } else {
        final someoneOpen = n > 1 && List.generate(n, (j) => j != p && marks[j][k] < 3).any((x) => x);
        if (someoneOpen) points[p] += d.field;
      }
    }
    if (allClosed(p)) {
      final bestOther = n == 1
          ? 0
          : List.generate(n, (j) => j == p ? -1 : points[j]).reduce(max);
      if (points[p] >= bestOther) {
        winner = p;
        ev.message = '${players[p].name} gewinnt Cricket!';
        finishGame();
      }
    }
  }

  @override
  void onNewRound() {
    if (round > maxRounds) finishGame();
  }

  @override
  String get title => 'Cricket';

  @override
  String get subtitle => 'Runde ${min(round, maxRounds)} / $maxRounds';

  @override
  String mainValue(int i) => '${points[i]}';

  @override
  String? subLine(int i) => '${closedCount(i)}/7 geschlossen';

  @override
  String lastLine(int i) {
    final t = lastTurns[i];
    if (t.isEmpty) return '–';
    return t.map((d) => d.label).join(' ');
  }

  @override
  bool get showTurnSum => false;

  @override
  Hint? get hint {
    final open = [
      for (var k = 0; k < numbers.length; k++)
        if (marks[cur][k] < 3) numbers[k] == 25 ? 'Bull' : '${numbers[k]}'
    ];
    if (open.isEmpty) return const Hint('Offen', 'Alles zu – Punkte sammeln!');
    return Hint('Offen', open.join(' · '), strong: true);
  }

  @override
  List<Target> get targets => [
        for (var k = 0; k < numbers.length; k++)
          if (marks[cur][k] < 3) Target(numbers[k])
      ];

  /// Nur 15–20 und Bull zählen.
  @override
  InputSpec get input => const InputSpec.numbers(numbers);

  @override
  List<PlayerResult> results() {
    final list = [
      for (var i = 0; i < n; i++)
        PlayerResult(
          playerIndex: i,
          value: '${points[i]} Punkte',
          detail: '${closedCount(i)}/7 geschlossen',
          metric: points[i],
        )
    ];
    return rankBy(list, (r) {
      final i = r.playerIndex;
      return (i == winner ? 1000000 : 0) + points[i] * 10 + closedCount(i);
    });
  }
}

// ======================================================================
// Killer
// ======================================================================

class KillerGame extends GameEngine {
  KillerGame(super.players, super.config, {super.startIndex, super.seed})
      : startLives = config.opt<int>('lives') {
    final pool = List.generate(20, (i) => i + 1)..shuffle(rng);
    numbers = pool.take(n).toList();
    lives = List.filled(n, startLives);
    killer = List.filled(n, false);
    kills = List.filled(n, 0);
    outOrder = [];
  }

  final int startLives;
  late List<int> numbers;
  late List<int> lives;
  late List<bool> killer;
  late List<int> kills;
  late List<int> outOrder;

  @override
  bool isOut(int i) => lives[i] <= 0;

  int get aliveCount => List.generate(n, (i) => !isOut(i)).where((x) => x).length;

  @override
  void onDart(Dart d, ThrowEvent ev) {
    final p = cur;
    if (!d.isDouble || d.isBull) return;
    if (d.field == numbers[p]) {
      if (!killer[p]) {
        killer[p] = true;
        ev.message = '${players[p].name} ist jetzt Killer!';
      } else {
        lives[p]--;
        ev.message = 'Autsch! ${players[p].name} trifft das eigene Double';
        ev.bust = true;
        if (isOut(p)) {
          outOrder.add(p);
          _checkEnd(ev);
          if (!finished) endTurn(ev);
        }
      }
      return;
    }
    if (!killer[p]) return;
    for (var j = 0; j < n; j++) {
      if (j != p && !isOut(j) && numbers[j] == d.field) {
        lives[j]--;
        kills[p]++;
        ev.message = isOut(j)
            ? '${players[j].name} ist raus!'
            : '${players[j].name} verliert ein Leben';
        if (isOut(j)) outOrder.add(j);
        _checkEnd(ev);
      }
    }
  }

  void _checkEnd(ThrowEvent ev) {
    if (aliveCount <= 1) {
      final w = List.generate(n, (i) => i).firstWhere((i) => !isOut(i), orElse: () => cur);
      ev.message = '${players[w].name} gewinnt Killer!';
      finishGame();
    }
  }

  @override
  String get title => 'Killer';

  @override
  String get subtitle => 'Runde $round · $startLives Leben';

  @override
  String mainValue(int i) => '${numbers[i]}';

  @override
  String? subLine(int i) {
    if (isOut(i)) return 'Raus';
    return '${'♥' * lives[i]}${'♡' * max(0, startLives - lives[i])}${killer[i] ? ' · Killer' : ''}';
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
  Hint? get hint {
    if (!killer[cur]) return Hint('Ziel', 'D${numbers[cur]} – werde Killer', strong: true);
    final victims = [
      for (var j = 0; j < n; j++)
        if (j != cur && !isOut(j)) 'D${numbers[j]}'
    ];
    return Hint('Angriff', victims.join(' · '), strong: true);
  }

  /// Nur die Doubles der Spielerzahlen zählen → eine Taste pro Spieler.
  @override
  InputSpec get input {
    final order = [cur, for (var k = 1; k < n; k++) (cur + k) % n];
    return InputSpec.buttons([
      for (final j in order)
        if (!isOut(j))
          QuickButton(numbers[j], 2, 'D${numbers[j]}', j == cur ? 'Eigene Zahl' : players[j].name, players[j].color),
    ], title: killer[cur] ? 'Killer: Doubles der Gegner treffen' : 'Eigenes Double treffen');
  }

  @override
  List<Target> get targets {
    if (!killer[cur]) return [Target(numbers[cur], 2)];
    return [
      for (var j = 0; j < n; j++)
        if (j != cur && !isOut(j)) Target(numbers[j], 2)
    ];
  }

  @override
  List<PlayerResult> results() {
    final list = [
      for (var i = 0; i < n; i++)
        PlayerResult(
          playerIndex: i,
          value: isOut(i) ? 'Raus' : '${lives[i]} Leben',
          detail: 'Zahl ${numbers[i]} · ${kills[i]} Treffer auf Gegner',
          metric: kills[i],
        )
    ];
    return rankBy(list, (r) {
      final i = r.playerIndex;
      if (!isOut(i)) return 1000 + lives[i];
      return outOrder.indexOf(i);
    });
  }
}

// ======================================================================
// Shanghai
// ======================================================================

class ShanghaiGame extends GameEngine {
  ShanghaiGame(super.players, super.config, {super.startIndex, super.seed})
      : maxRounds = config.opt<int>('rounds') {
    scores = List.filled(n, 0);
  }

  final int maxRounds;
  late List<int> scores;
  int? shanghaiWinner;

  int get target => min(round, maxRounds);

  @override
  void onDart(Dart d, ThrowEvent ev) {
    final p = cur;
    if (d.field == target) scores[p] += d.value;
    if (turn.length == 3) {
      final ms = turn.where((x) => x.field == target).map((x) => x.mult).toSet();
      if (ms.containsAll([1, 2, 3])) {
        shanghaiWinner = p;
        ev.message = 'SHANGHAI! ${players[p].name} gewinnt sofort';
        ev.celebration = Celebration.highFinish;
        ev.celebrationValue = target * 6;
        finishGame();
      }
    }
  }

  @override
  void onTurnComplete(ThrowEvent ev) {
    final pts = turn.where((d) => d.field == target).fold(0, (a, d) => a + d.value);
    ev.message = '${players[cur].name}: +$pts';
  }

  @override
  void onNewRound() {
    if (round > maxRounds) finishGame();
  }

  @override
  String get title => 'Shanghai';

  @override
  String get subtitle => 'Runde $target / $maxRounds';

  @override
  String mainValue(int i) => '${scores[i]}';

  @override
  Hint? get hint => Hint('Ziel', '$target · Single + Double + Triple = Shanghai', strong: true);

  @override
  List<Target> get targets => [Target(target)];

  @override
  InputSpec get input => InputSpec.buttons([
        QuickButton(target, 1, '$target', 'Single · +$target'),
        QuickButton(target, 2, 'D$target', 'Double · +${target * 2}'),
        QuickButton(target, 3, 'T$target', 'Triple · +${target * 3}'),
      ], title: 'Ziel: $target');

  @override
  List<PlayerResult> results() {
    final list = [
      for (var i = 0; i < n; i++)
        PlayerResult(
          playerIndex: i,
          value: i == shanghaiWinner ? 'Shanghai!' : '${scores[i]} Punkte',
          detail: '${scores[i]} Punkte',
          metric: scores[i],
        )
    ];
    return rankBy(list, (r) {
      final i = r.playerIndex;
      return (i == shanghaiWinner ? 100000 : 0) + scores[i];
    });
  }
}

// ======================================================================
// High Score
// ======================================================================

class HighScoreGame extends GameEngine {
  HighScoreGame(super.players, super.config, {super.startIndex, super.seed})
      : maxRounds = config.opt<int>('rounds') {
    scores = List.filled(n, 0);
    darts = List.filled(n, 0);
  }

  final int maxRounds;
  late List<int> scores;
  late List<int> darts;

  @override
  void onDart(Dart d, ThrowEvent ev) {
    scores[cur] += d.value;
    darts[cur]++;
  }

  @override
  void onTurnComplete(ThrowEvent ev) {
    final sum = sumOf(turn);
    final c = celebrationForScore(sum);
    if (c != null) {
      ev.celebration = c;
      ev.celebrationValue = sum;
    }
  }

  @override
  void onNewRound() {
    if (round > maxRounds) finishGame();
  }

  @override
  String get title => 'High Score';

  @override
  String get subtitle => 'Runde ${min(round, maxRounds)} / $maxRounds';

  @override
  String mainValue(int i) => '${scores[i]}';

  @override
  String? subLine(int i) =>
      'Ø ${fmt1(darts[i] == 0 ? 0 : scores[i] / darts[i] * 3)}';

  @override
  List<PlayerResult> results() {
    final list = [
      for (var i = 0; i < n; i++)
        PlayerResult(
          playerIndex: i,
          value: '${scores[i]} Punkte',
          detail: 'Ø ${fmt1(darts[i] == 0 ? 0 : scores[i] / darts[i] * 3)}',
          metric: scores[i],
        )
    ];
    return rankBy(list, (r) => r.metric!);
  }
}

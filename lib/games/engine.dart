import 'dart:math';

import '../models/dart.dart';
import '../models/player.dart';

/// Stufen der großen Animationen.
enum Celebration { ton, ton40, max180, highFinish, legWon }

Celebration? celebrationForScore(int score) {
  if (score >= 180) return Celebration.max180;
  if (score >= 140) return Celebration.ton40;
  if (score >= 100) return Celebration.ton;
  return null;
}

/// Was nach einem Pfeil passiert ist – die Oberfläche reagiert darauf.
class ThrowEvent {
  ThrowEvent(this.playerIndex);

  final int playerIndex;
  bool turnEnded = false;
  List<Dart> turnDarts = const [];
  bool bust = false;
  bool gameOver = false;
  Celebration? celebration;
  int? celebrationValue;
  String? celebrationLabel;
  String? message;

  /// Steuer-Markierung statt eines Pfeils (z. B. Single Out umgeschaltet).
  bool control = false;

  /// Dieser Spieler hängt im Finish fest: Single Out anbieten.
  int? offerSingleOut;

  /// Leg wurde mit Single Out ohne Double beendet.
  bool singleOutFinish = false;

  /// Nach diesem Wurf steht ein Platz fest und es spielen noch mindestens zwei weiter:
  /// Weiterspielen um den nächsten Platz anbieten (Wert = dieser Platz, z. B. 1 = Sieger).
  int? offerPlayOn;
}

/// Ein Feld, das auf der Scheibe als Ziel hervorgehoben wird.
/// [field] -1 = alle Zahlen (z. B. „irgendein Double“), [mult] null = alle Ringe.
class Target {
  const Target(this.field, [this.mult]);
  final int field;
  final int? mult;
}

/// Eine große Schnelltaste (z. B. „T7“ bei Shanghai).
class QuickButton {
  const QuickButton(this.field, this.mult, this.label, [this.sub, this.color]);
  final int field;
  final int mult;
  final String label;
  final String? sub;

  /// Eigene Farbe (ARGB), z. B. Killer: Farbe des Spielers, dem die Zahl gehört.
  /// Ohne Angabe: Farbe des Spielers am Wurf.
  final int? color;
}

enum InputKind { full, numbers, buttons }

/// Welche Eingabe der Modus gerade braucht.
class InputSpec {
  const InputSpec.full({this.lockedMult, this.title})
      : kind = InputKind.full,
        numbers = const [],
        buttons = const [];
  const InputSpec.numbers(this.numbers, {this.title})
      : kind = InputKind.numbers,
        lockedMult = null,
        buttons = const [];
  const InputSpec.buttons(this.buttons, {this.title})
      : kind = InputKind.buttons,
        lockedMult = null,
        numbers = const [];

  final InputKind kind;
  final int? lockedMult;
  final List<int> numbers;
  final List<QuickButton> buttons;
  final String? title;
}

class Hint {
  const Hint(this.label, this.text, {this.strong = false});
  final String? label;
  final String text;
  final bool strong;
}

class PlayerResult {
  PlayerResult({
    required this.playerIndex,
    required this.value,
    this.detail = '',
    this.rank = 0,
    this.metric,
    this.won = false,
  });

  final int playerIndex;
  final String value;
  final String detail;
  int rank;
  final num? metric;
  bool won;
}

/// Konfiguration eines Spiels: Modus + Optionen.
class GameConfig {
  const GameConfig(this.modeId, this.options);
  final String modeId;
  final Map<String, dynamic> options;

  T opt<T>(String key) => options[key] as T;

  Map<String, dynamic> toJson() => {'mode': modeId, 'options': options};
  factory GameConfig.fromJson(Map<String, dynamic> j) => GameConfig(
      j['mode'] as String, Map<String, dynamic>.from(j['options'] as Map));
}

/// Basisklasse aller Spielmodi.
///
/// Die Engines sind deterministisch (Zufall nur über [rng] mit festem Seed).
/// Undo funktioniert, indem eine neue Engine gebaut und alle Pfeile bis auf
/// den letzten erneut angewendet werden.
abstract class GameEngine {
  GameEngine(this.players, this.config, {this.startIndex = 0, int seed = 0})
      : rng = Random(seed),
        cur = startIndex % players.length,
        roundStarter = startIndex % players.length,
        lastTurns = List.generate(players.length, (_) => <Dart>[]),
        hits = List.generate(players.length, (_) => <String, int>{}),
        dartCount = List.filled(players.length, 0);

  final List<GamePlayer> players;
  final GameConfig config;
  final int startIndex;
  final Random rng;

  int cur;
  int roundStarter;
  int round = 1;
  bool finished = false;
  List<Dart> turn = [];
  final List<List<Dart>> lastTurns;

  /// Trefferbild pro Spieler in diesem Match (Schlüssel wie [Dart.key]).
  final List<Map<String, int>> hits;
  final List<int> dartCount;

  int get n => players.length;
  int get dartsPerTurn => 3;

  /// Steuer-Markierung aus der Wurf-Liste (Standard: ignorieren).
  void onControl(Dart d) {}

  /// Wird nach dem Erzeugen einmal aufgerufen.
  void begin() => onTurnStart();

  ThrowEvent apply(Dart d) {
    final ev = ThrowEvent(cur);
    if (finished && !d.isControl) return ev;
    if (d.isControl) {
      ev.control = true;
      onControl(d);
      return ev;
    }
    turn.add(d);
    hits[cur][d.key] = (hits[cur][d.key] ?? 0) + 1;
    dartCount[cur]++;
    onDart(d, ev);
    if (!finished && !ev.turnEnded && turn.length >= dartsPerTurn) {
      onTurnComplete(ev);
      if (!finished && !ev.turnEnded) endTurn(ev);
    }
    if (finished) {
      ev.gameOver = true;
      if (!ev.turnEnded) {
        ev.turnEnded = true;
        ev.turnDarts = List.of(turn);
        lastTurns[cur] = List.of(turn);
      }
    }
    return ev;
  }

  /// Beendet die Aufnahme des aktuellen Spielers.
  void endTurn(ThrowEvent ev, {int? next}) {
    ev.turnEnded = true;
    ev.turnDarts = List.of(turn);
    lastTurns[cur] = List.of(turn);
    turn = [];
    if (finished) return;
    if (next != null) {
      cur = next;
    } else {
      _advance();
    }
    if (!finished) onTurnStart();
  }

  void _advance() {
    if (List.generate(n, isOut).every((o) => o)) {
      finishGame();
      return;
    }
    var c = cur;
    for (var i = 0; i < n * 2; i++) {
      c = (c + 1) % n;
      if (c == roundStarter) {
        round++;
        onNewRound();
        if (finished) return;
      }
      if (!isOut(c)) break;
    }
    cur = c;
  }

  void finishGame() => finished = true;

  /// Spieler ist ausgeschieden bzw. fertig und wird übersprungen.
  bool isOut(int i) => false;

  void onTurnStart() {}
  void onNewRound() {}
  void onDart(Dart d, ThrowEvent ev);
  void onTurnComplete(ThrowEvent ev) {}

  // ---------- Anzeige ----------
  String get title;
  String get subtitle;
  String mainValue(int i);
  String activeValue() => mainValue(cur);
  String? subLine(int i) => null;

  /// Große Kennzahl rechts in der Karte am Wurf (z. B. „Ø 45,3“), sonst null.
  String? cardStat(int i) => null;
  String lastLine(int i) {
    final t = lastTurns[i];
    if (t.isEmpty) return '–';
    return '${sumOf(t)}';
  }

  int? get legsToWin => null;
  int legsOf(int i) => 0;
  int? get setsToWin => null;
  int setsOf(int i) => 0;
  Hint? get hint => null;
  List<Target> get targets => const [];
  InputSpec get input => const InputSpec.full();
  List<Dart> get visibleTurn => turn;
  bool get showTurnSum => true;

  /// Ergebnisliste, Platz 1 zuerst.
  List<PlayerResult> results();
}

/// Hilfsfunktion: Ränge vergeben (gleicher Wert = gleicher Rang).
List<PlayerResult> rankBy(List<PlayerResult> list, num Function(PlayerResult) key,
    {bool lowerIsBetter = false}) {
  list.sort((a, b) {
    final c = key(a).compareTo(key(b));
    return lowerIsBetter ? c : -c;
  });
  for (var i = 0; i < list.length; i++) {
    if (i > 0 && key(list[i]) == key(list[i - 1])) {
      list[i].rank = list[i - 1].rank;
    } else {
      list[i].rank = i + 1;
    }
  }
  if (list.length > 1) {
    for (final r in list) {
      r.won = r.rank == 1;
    }
  } else if (list.isNotEmpty) {
    list.first.won = true;
  }
  return list;
}

String fmt1(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

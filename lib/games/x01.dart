import '../models/dart.dart';
import 'checkout.dart';
import 'engine.dart';

/// Langzeit-Statistikwerte eines Spielers in einem X01-Match.
class X01Stats {
  int matches = 0;
  int matchesWon = 0;
  int legsWon = 0;
  int legsPlayed = 0;
  int points = 0;
  int darts = 0;
  int f9Points = 0;
  int f9Darts = 0;
  int coAttempts = 0;
  int coHits = 0;
  int highestFinish = 0;
  int c100 = 0;
  int c140 = 0;
  int c180 = 0;
  int highestTurn = 0;
  int bestLeg = 0; // 0 = noch keins
  Map<String, int> hits = {};

  double get average => darts == 0 ? 0 : points / darts * 3;
  double get first9 => f9Darts == 0 ? 0 : f9Points / f9Darts * 3;
  double get coRate => coAttempts == 0 ? 0 : coHits / coAttempts * 100;

  void merge(X01Stats o) {
    matches += o.matches;
    matchesWon += o.matchesWon;
    legsWon += o.legsWon;
    legsPlayed += o.legsPlayed;
    points += o.points;
    darts += o.darts;
    f9Points += o.f9Points;
    f9Darts += o.f9Darts;
    coAttempts += o.coAttempts;
    coHits += o.coHits;
    if (o.highestFinish > highestFinish) highestFinish = o.highestFinish;
    c100 += o.c100;
    c140 += o.c140;
    c180 += o.c180;
    if (o.highestTurn > highestTurn) highestTurn = o.highestTurn;
    if (o.bestLeg > 0 && (bestLeg == 0 || o.bestLeg < bestLeg)) bestLeg = o.bestLeg;
    o.hits.forEach((k, v) => hits[k] = (hits[k] ?? 0) + v);
  }

  Map<String, dynamic> toJson() => {
        'matches': matches,
        'matchesWon': matchesWon,
        'legsWon': legsWon,
        'legsPlayed': legsPlayed,
        'points': points,
        'darts': darts,
        'f9Points': f9Points,
        'f9Darts': f9Darts,
        'coAttempts': coAttempts,
        'coHits': coHits,
        'highestFinish': highestFinish,
        'c100': c100,
        'c140': c140,
        'c180': c180,
        'highestTurn': highestTurn,
        'bestLeg': bestLeg,
        'hits': hits,
      };

  static X01Stats fromJson(Map<String, dynamic> j) {
    final s = X01Stats();
    int g(String k) => (j[k] as num?)?.toInt() ?? 0;
    s.matches = g('matches');
    s.matchesWon = g('matchesWon');
    s.legsWon = g('legsWon');
    s.legsPlayed = g('legsPlayed');
    s.points = g('points');
    s.darts = g('darts');
    s.f9Points = g('f9Points');
    s.f9Darts = g('f9Darts');
    s.coAttempts = g('coAttempts');
    s.coHits = g('coHits');
    s.highestFinish = g('highestFinish');
    s.c100 = g('c100');
    s.c140 = g('c140');
    s.c180 = g('c180');
    s.highestTurn = g('highestTurn');
    s.bestLeg = g('bestLeg');
    s.hits = Map<String, int>.from(
        (j['hits'] as Map? ?? {}).map((k, v) => MapEntry(k as String, (v as num).toInt())));
    return s;
  }
}

class X01Game extends GameEngine {
  X01Game(super.players, super.config, {super.startIndex, super.seed})
      : start = config.opt<int>('start'),
        doubleOut = config.opt<bool>('doubleOut'),
        legsTarget = config.opt<int>('legs'),
        useSets = config.options['format'] == 'sets',
        setsTarget = (config.options['sets'] as int?) ?? 3 {
    scores = List.filled(n, start);
    legs = List.filled(n, 0);
    sets = List.filled(n, 0);
    legsTotal = List.filled(n, 0);
    legDarts = List.filled(n, 0);
    turnsInLeg = List.filled(n, 0);
    stats = List.generate(n, (_) => X01Stats());
    stuck = List.filled(n, 0);
    legStarter = cur;
    setStarter = cur;
  }

  final int start;
  final bool doubleOut;

  /// Legs zum Matchgewinn bzw. bei Sets: Legs pro Set.
  final int legsTarget;
  final bool useSets;
  final int setsTarget;

  late List<int> scores;
  /// Legs im aktuellen Set (ohne Sets: im Match).
  late List<int> legs;
  late List<int> sets;

  /// Insgesamt gewonnene Legs im Match.
  late List<int> legsTotal;
  int legsPlayed = 0;
  late int setStarter;
  late List<int> legDarts;
  late List<int> turnsInLeg;
  late List<X01Stats> stats;
  late int legStarter;
  int turnStart = 0;
  int? winner;

  /// Nach so vielen Aufnahmen ohne Änderung im Finish wird Single Out angeboten.
  static const stuckLimit = 5;

  /// Single Out ist im laufenden Leg erlaubt (für alle Spieler).
  bool singleOutLeg = false;

  /// Single Out wurde in diesem Leg schon angeboten (dann bleibt der Schalter sichtbar).
  bool singleOutOffered = false;

  /// Aufnahmen hintereinander ohne Änderung des Rests (pro Spieler, im Leg).
  late List<int> stuck;

  /// Gilt gerade Double Out?
  bool get doubleOutNow => doubleOut && !singleOutLeg;

  /// Feste Plätze in Reihenfolge (Sieger zuerst, dann wer beim Weiterspielen auscheckt).
  final List<int> placed = [];

  /// Nach dem Sieg wird um die weiteren Plätze weitergespielt.
  bool playingOn = false;

  /// Spieler, die noch um einen Platz spielen.
  int get remaining => n - placed.length;

  @override
  bool isOut(int i) => playingOn && placed.contains(i);

  /// Platz eines Spielers (1 = Sieger) oder null, wenn noch offen.
  int? placeOf(int i) {
    final k = placed.indexOf(i);
    return k < 0 ? null : k + 1;
  }

  @override
  void onControl(Dart d) {
    if (d.field == -2) {
      _playOn();
      return;
    }
    if (!doubleOut || finished) return;
    singleOutLeg = d.mult == 1;
    if (singleOutLeg) singleOutOffered = true;
  }

  /// Nach jeder Aufnahme: festhängen im Finish zählen.
  void _afterVisit(int p, ThrowEvent ev) {
    final rest = scores[p];
    if (rest == turnStart && findCheckout(rest, 3, doubleOut: true) != null) {
      stuck[p]++;
    } else {
      stuck[p] = 0;
    }
    if (doubleOut && !singleOutLeg && !singleOutOffered && stuck[p] >= stuckLimit) {
      singleOutOffered = true;
      ev.offerSingleOut = p;
    }
  }

  @override
  void onTurnStart() => turnStart = scores[cur];

  bool _isFinishable(int rest) =>
      doubleOutNow ? (rest == 50 || (rest <= 40 && rest >= 2 && rest.isEven)) : false;

  @override
  void onDart(Dart d, ThrowEvent ev) {
    final p = cur;
    final s = stats[p];
    final before = scores[p];
    final rest = before - d.value;
    final first9 = turnsInLeg[p] < 3;

    s.darts++;
    legDarts[p]++;
    s.hits[d.key] = (s.hits[d.key] ?? 0) + 1;
    if (first9) s.f9Darts++;
    final attempt = _isFinishable(before);
    if (attempt) s.coAttempts++;

    final bust = doubleOutNow
        ? (rest < 0 || rest == 1 || (rest == 0 && !d.isDouble))
        : rest < 0;

    if (bust) {
      final lost = turnStart - before;
      s.points -= lost;
      if (first9) s.f9Points -= lost;
      scores[p] = turnStart;
      turnsInLeg[p]++;
      ev.bust = true;
      ev.message = 'Bust! ${players[p].name} bleibt auf $turnStart';
      _afterVisit(p, ev);
      endTurn(ev);
      return;
    }

    s.points += d.value;
    if (first9) s.f9Points += d.value;

    if (rest == 0 && playingOn) {
      if (attempt) s.coHits++;
      _recordTurn(p, turnStart);
      scores[p] = 0;
      placed.add(p);
      ev.celebration = Celebration.legWon;
      ev.celebrationValue = turnStart;
      ev.celebrationLabel = 'PLATZ ${placed.length}';
      ev.message = '${players[p].name} wird ${placed.length}.';
      if (remaining == 1) {
        // Der Letzte bekommt den letzten Platz.
        placed.add([for (var i = 0; i < n; i++) i].firstWhere((i) => !placed.contains(i)));
        finishGame();
      } else {
        finishGame();
        ev.offerPlayOn = placed.length;
      }
      return;
    }
    if (rest == 0) {
      if (attempt) s.coHits++;
      final finish = turnStart;
      // Single-Finish (ohne Double) zählt nicht als High-Finish.
      final realFinish = !singleOutLeg || !doubleOut || d.isDouble;
      ev.singleOutFinish = !realFinish;
      _recordTurn(p, finish);
      if (realFinish && finish > s.highestFinish) s.highestFinish = finish;
      legs[p]++;
      legsTotal[p]++;
      legsPlayed++;
      s.legsWon++;
      if (s.bestLeg == 0 || legDarts[p] < s.bestLeg) s.bestLeg = legDarts[p];
      scores[p] = 0;
      ev.celebration = finish >= 100 && realFinish ? Celebration.highFinish : Celebration.legWon;
      ev.celebrationValue = finish;
      var setWon = false;
      if (useSets && legs[p] >= legsTarget) {
        sets[p]++;
        setWon = true;
      }
      if (useSets ? sets[p] >= setsTarget : legs[p] >= legsTarget) {
        winner = p;
        placed.add(p);
        _closeMatch();
        finishGame();
        if (remaining >= 2) ev.offerPlayOn = 1;
        return;
      }
      if (setWon) {
        ev.celebrationLabel = 'SET GEWONNEN';
        ev.message = '${players[p].name} checkt $finish – Set gewonnen';
      } else {
        ev.message = '${players[p].name} checkt $finish – Leg gewonnen';
      }
      for (var i = 0; i < n; i++) {
        scores[i] = start;
        legDarts[i] = 0;
        turnsInLeg[i] = 0;
        stuck[i] = 0;
        if (setWon) legs[i] = 0;
      }
      // Neues Leg: wieder Double Out
      singleOutLeg = false;
      singleOutOffered = false;
      if (setWon) {
        setStarter = (setStarter + 1) % n;
        legStarter = setStarter;
      } else {
        legStarter = (legStarter + 1) % n;
      }
      roundStarter = legStarter;
      endTurn(ev, next: legStarter);
      return;
    }
    scores[p] = rest;
  }

  void _recordTurn(int p, int sum) {
    final s = stats[p];
    if (sum >= 180) {
      s.c180++;
    } else if (sum >= 140) {
      s.c140++;
    } else if (sum >= 100) {
      s.c100++;
    }
    if (sum > s.highestTurn) s.highestTurn = sum;
  }

  @override
  void onTurnComplete(ThrowEvent ev) {
    final p = cur;
    final sum = turnStart - scores[p];
    _recordTurn(p, sum);
    turnsInLeg[p]++;
    _afterVisit(p, ev);
    final c = celebrationForScore(sum);
    if (c != null) {
      ev.celebration = c;
      ev.celebrationValue = sum;
    }
  }

  /// Nach einem Sieg mit den übrigen Spielern weiterspielen (Leg läuft mit ihren Restpunkten weiter).
  void _playOn() {
    if (!finished || remaining < 2) return;
    finished = false;
    playingOn = true;
    turn = [];
    // Der nächste noch spielende Spieler nach dem zuletzt Platzierten ist dran.
    var c = placed.last;
    for (var i = 0; i < n; i++) {
      c = (c + 1) % n;
      if (!placed.contains(c)) break;
    }
    cur = c;
    onTurnStart();
  }

  void _closeMatch() {
    for (var i = 0; i < n; i++) {
      stats[i].matches = 1;
      stats[i].legsPlayed = legsPlayed;
      stats[i].matchesWon = i == winner ? 1 : 0;
    }
  }

  @override
  String get title => '$start · ${!doubleOut ? 'Single Out' : singleOutLeg ? 'Single Out (dieses Leg)' : 'Double Out'}';

  @override
  String get subtitle {
    // Weiterspielen um Plätze: das letzte Leg läuft weiter, kein neues Leg.
    if (playingOn && !finished) return '${players[placed.first].name} hat gewonnen · um Platz ${placed.length + 1}';
    if (useSets) {
      final setNo = sets.fold(0, (a, b) => a + b) + (finished ? 0 : 1);
      final legNo = legs.fold(0, (a, b) => a + b) + (finished ? 0 : 1);
      return 'First to $setsTarget ${setsTarget == 1 ? 'Set' : 'Sets'} · Set $setNo · Leg $legNo';
    }
    return 'First to $legsTarget ${legsTarget == 1 ? 'Leg' : 'Legs'} · Leg ${finished ? legsPlayed : legsPlayed + 1}';
  }

  /// Kurzform des Match-Formats, z. B. „FT 3 Sets (à 3 Legs)“.
  String get formatLabel => useSets
      ? 'First to $setsTarget ${setsTarget == 1 ? 'Set' : 'Sets'} · je $legsTarget ${legsTarget == 1 ? 'Leg' : 'Legs'}'
      : 'First to $legsTarget ${legsTarget == 1 ? 'Leg' : 'Legs'}';

  @override
  String mainValue(int i) => '${scores[i]}';

  @override
  String? subLine(int i) => 'Ø ${fmt1(stats[i].average)} · ${stats[i].darts} Darts';

  @override
  String lastLine(int i) {
    final t = lastTurns[i];
    if (t.isEmpty) return '–';
    return '${sumOf(t)}';
  }

  @override
  int? get legsToWin => legsTarget;

  @override
  int legsOf(int i) => legs[i];

  @override
  int? get setsToWin => useSets ? setsTarget : null;

  @override
  int setsOf(int i) => sets[i];

  @override
  Hint? get hint {
    final rest = scores[cur];
    final left = 3 - turn.length;
    final co = findCheckout(rest, left, doubleOut: doubleOutNow, avoidDoubles: singleOutLeg);
    if (co != null) return Hint('Checkout', co.join(' · '), strong: true);
    if (rest > (doubleOutNow ? 170 : 180)) return const Hint(null, 'Noch kein Finish möglich');
    // Kein Finish mehr mit den restlichen Darts: den besten Stellwurf vorschlagen.
    if (doubleOutNow) {
      final st = setupShot(rest);
      if (st != null) return Hint('Stellen', st.text);
    }
    return Hint(null, 'Kein Finish mit $left ${left == 1 ? 'Dart' : 'Darts'}');
  }

  @override
  List<PlayerResult> results() {
    final list = [
      for (var i = 0; i < n; i++)
        PlayerResult(
          playerIndex: i,
          value: useSets
              ? '${sets[i]} ${sets[i] == 1 ? 'Set' : 'Sets'}'
              : '${legs[i]} ${legs[i] == 1 ? 'Leg' : 'Legs'}',
          detail: '${useSets ? '${legsTotal[i]} Legs · ' : ''}'
              'Ø ${fmt1(stats[i].average)} · Höchste ${stats[i].highestTurn} · 180er ${stats[i].c180}',
          metric: placed.contains(i)
              ? 1000000000 - placed.indexOf(i)
              : sets[i] * 1000000 + legs[i] * 1000 - scores[i],
        )
    ];
    return rankBy(list, (r) => r.metric!);
  }
}

import 'dart:math';

/// Turniersysteme.
enum TSystem { ko, doubleKo, groups, league }

extension TSystemX on TSystem {
  String get label => switch (this) {
        TSystem.ko => 'K.o.-System',
        TSystem.doubleKo => 'Doppel-K.o.',
        TSystem.groups => 'Gruppen + K.o.',
        TSystem.league => 'Liga',
      };

  String get description => switch (this) {
        TSystem.ko => 'Wer verliert, ist raus. Die Halbfinal-Verlierer spielen um Platz 3.',
        TSystem.doubleKo => 'Gewinner- und Verliererrunde – erst die zweite Niederlage scheidet aus.',
        TSystem.groups => 'Jeder gegen jeden in Gruppen, die Besten spielen den K.o.-Baum.',
        TSystem.league => 'Alle gegen alle. Die Tabelle entscheidet.',
      };
}

/// Phasen, für die ein eigenes Match-Format eingestellt werden kann.
enum TStage { group, early, qf, sf, finale }

extension TStageX on TStage {
  String get label => switch (this) {
        TStage.group => 'Gruppe / Liga',
        TStage.early => 'Frühe Runden',
        TStage.qf => 'Viertelfinale',
        TStage.sf => 'Halbfinale',
        TStage.finale => 'Finale',
      };
}

/// Match-Format: First to X Legs oder First to X Sets à Y Legs.
class TFormat {
  const TFormat({this.sets = false, this.legs = 3, this.setCount = 3});
  final bool sets;
  final int legs;
  final int setCount;

  TFormat copyWith({bool? sets, int? legs, int? setCount}) =>
      TFormat(sets: sets ?? this.sets, legs: legs ?? this.legs, setCount: setCount ?? this.setCount);

  String get label => sets
      ? 'FT $setCount ${setCount == 1 ? 'Set' : 'Sets'} · je $legs ${legs == 1 ? 'Leg' : 'Legs'}'
      : 'First to $legs ${legs == 1 ? 'Leg' : 'Legs'}';

  Map<String, dynamic> toJson() => {'s': sets, 'l': legs, 'c': setCount};
  factory TFormat.fromJson(Map<String, dynamic> j) =>
      TFormat(sets: j['s'] as bool, legs: j['l'] as int, setCount: j['c'] as int);
}

class TPlayer {
  const TPlayer(this.profileId, this.name);
  final String profileId;
  final String name;

  Map<String, dynamic> toJson() => {'p': profileId, 'n': name};
  factory TPlayer.fromJson(Map<String, dynamic> j) => TPlayer(j['p'] as String, j['n'] as String);
}

/// Woher ein Teilnehmer eines Matches kommt.
class TSlot {
  const TSlot._(this.kind, {this.index = -1, this.match, this.group = 0, this.place = 0});

  /// Spieler mit Index [i] (oder Freilos bei -1).
  const TSlot.seed(int i) : this._('seed', index: i);
  const TSlot.bye() : this._('seed', index: -1);
  const TSlot.winnerOf(String m) : this._('win', match: m);
  const TSlot.loserOf(String m) : this._('lose', match: m);

  /// Seite A bzw. B eines anderen Matches (für das Entscheidungsspiel).
  const TSlot.sideOf(String m, int side) : this._('side', match: m, index: side);

  /// Platz [place] (0-basiert) der Gruppe [group].
  const TSlot.qualifier(int group, int place) : this._('q', group: group, place: place);

  final String kind;
  final int index;
  final String? match;
  final int group;
  final int place;

  Map<String, dynamic> toJson() => {'k': kind, 'i': index, 'm': match, 'g': group, 'p': place};
  factory TSlot.fromJson(Map<String, dynamic> j) => TSlot._(j['k'] as String,
      index: j['i'] as int, match: j['m'] as String?, group: j['g'] as int, place: j['p'] as int);
}

/// Ergebnis der Auflösung eines Slots.
class _R {
  const _R.pending()
      : pending = true,
        player = null;
  const _R.empty()
      : pending = false,
        player = null;
  const _R.player(int this.player) : pending = false;
  final bool pending;
  final int? player;
  bool get isEmpty => !pending && player == null;
}

class TMatch {
  TMatch({
    required this.id,
    required this.bracket,
    required this.round,
    required this.order,
    required this.stage,
    required this.a,
    required this.b,
    this.group,
    this.conditional = false,
  });

  final String id;

  /// W = Hauptrunde/K.o., L = Verliererrunde, F = Finale (Doppel-K.o.),
  /// P3 = Spiel um Platz 3, G = Gruppe, LG = Liga.
  final String bracket;
  final int round;
  final int order;
  final TStage stage;
  final TSlot a;
  final TSlot b;
  final int? group;

  /// Entscheidungsspiel im Doppel-K.o.: nur nötig, wenn Seite B das erste Finale gewinnt.
  final bool conditional;

  // Ergebnis
  int? winnerSide; // 0 = a, 1 = b
  List<int> legs = [0, 0];
  List<int> sets = [0, 0];
  List<int> points = [0, 0];
  List<int> darts = [0, 0];

  bool get played => winnerSide != null;

  double avg(int side) => darts[side] == 0 ? 0 : points[side] / darts[side] * 3;

  Map<String, dynamic> toJson() => {
        'id': id,
        'br': bracket,
        'r': round,
        'o': order,
        'st': stage.name,
        'a': a.toJson(),
        'b': b.toJson(),
        'g': group,
        'c': conditional,
        'w': winnerSide,
        'l': legs,
        's': sets,
        'pt': points,
        'd': darts,
      };

  factory TMatch.fromJson(Map<String, dynamic> j) {
    List<int> li(Object? v) => [for (final x in (v as List? ?? [0, 0])) (x as num).toInt()];
    return TMatch(
      id: j['id'] as String,
      bracket: j['br'] as String,
      round: j['r'] as int,
      order: j['o'] as int,
      stage: TStage.values.byName(j['st'] as String),
      a: TSlot.fromJson(Map<String, dynamic>.from(j['a'] as Map)),
      b: TSlot.fromJson(Map<String, dynamic>.from(j['b'] as Map)),
      group: j['g'] as int?,
      conditional: j['c'] as bool? ?? false,
    )
      ..winnerSide = j['w'] as int?
      ..legs = li(j['l'])
      ..sets = li(j['s'])
      ..points = li(j['pt'])
      ..darts = li(j['d']);
  }
}

/// Tabellenzeile (Gruppe / Liga).
class TStanding {
  TStanding(this.player);
  final int player;
  int played = 0;
  int wins = 0;
  int losses = 0;
  int legsFor = 0;
  int legsAgainst = 0;
  int points = 0;
  int darts = 0;
  int get legDiff => legsFor - legsAgainst;
  double get average => darts == 0 ? 0 : points / darts * 3;
}

/// Platzierung am Ende.
class TPlacement {
  const TPlacement(this.player, this.rank);
  final int player;
  final int rank;
}

int nextPow2(int n) {
  var p = 1;
  while (p < n) {
    p *= 2;
  }
  return p;
}

/// Setzpositionen im Baum: für 8 → [1, 8, 4, 5, 2, 7, 3, 6].
List<int> seedPositions(int size) {
  var s = [1];
  while (s.length < size) {
    final m = s.length * 2 + 1;
    s = [for (final x in s) ...[x, m - x]];
  }
  return s;
}

/// Vorschlag für Gruppen: (Anzahl Gruppen, Aufsteiger pro Gruppe).
(int, int) suggestGroups(int n) {
  final g = (n / 4).round().clamp(2, max(2, n ~/ 2)).toInt();
  final minSize = n ~/ g;
  final a = minSize >= 3 ? 2 : 1;
  return (g, a);
}

class Tournament {
  Tournament({
    required this.id,
    required this.name,
    required this.created,
    required this.system,
    required this.players,
    required this.start,
    required this.doubleOut,
    required this.formats,
    this.homeAway = false,
    this.groupCount = 2,
    this.advance = 2,
    List<TMatch>? matches,
    this.finished = false,
  }) : matches = matches ?? [];

  final String id;
  String name;
  final DateTime created;
  final TSystem system;

  /// Teilnehmer in Setz-Reihenfolge (Index 0 = Nummer 1 der Setzliste).
  final List<TPlayer> players;
  final int start;
  final bool doubleOut;
  final Map<TStage, TFormat> formats;
  final bool homeAway;
  final int groupCount;
  final int advance;
  final List<TMatch> matches;
  bool finished;

  int get n => players.length;

  /// Welche Phasen in diesem Turnier vorkommen.
  static List<TStage> stagesFor(TSystem system, int n, {int groupCount = 2, int advance = 2}) {
    if (system == TSystem.league) return [TStage.group];
    final size = system == TSystem.groups ? nextPow2(groupCount * advance) : nextPow2(n);
    final out = <TStage>[if (system == TSystem.groups) TStage.group];
    if (size > 8) out.add(TStage.early);
    if (size >= 8) out.add(TStage.qf);
    if (size >= 4 || system == TSystem.doubleKo) out.add(TStage.sf);
    out.add(TStage.finale);
    return out;
  }

  TFormat formatOf(TStage s) => formats[s] ?? const TFormat();

  TMatch matchById(String id) => matches.firstWhere((m) => m.id == id);

  // ------------------------------------------------------------ Aufbau

  /// Erzeugt alle Matches für das gewählte System.
  void build() {
    matches.clear();
    switch (system) {
      case TSystem.ko:
        _buildKo([for (var i = 0; i < n; i++) TSlot.seed(i)], 'W', thirdPlace: true);
      case TSystem.doubleKo:
        _buildDoubleKo();
      case TSystem.league:
        _buildRoundRobin(List.generate(n, (i) => i), 'LG', null, homeAway);
      case TSystem.groups:
        final groups = groupMembers();
        for (var g = 0; g < groups.length; g++) {
          _buildRoundRobin(groups[g], 'G', g, false);
        }
        final q = <TSlot>[
          for (var place = 0; place < advance; place++)
            for (var g = 0; g < groupCount; g++) TSlot.qualifier(g, place),
        ];
        _buildKo(q, 'W', thirdPlace: true);
    }
  }

  /// Spieler je Gruppe (Schlangen-Verteilung nach Setzliste).
  List<List<int>> groupMembers() {
    final groups = List.generate(groupCount, (_) => <int>[]);
    for (var i = 0; i < n; i++) {
      final row = i ~/ groupCount;
      final col = i % groupCount;
      groups[row.isEven ? col : groupCount - 1 - col].add(i);
    }
    return groups;
  }

  static TStage _koStage(int matchesInRound) => switch (matchesInRound) {
        1 => TStage.finale,
        2 => TStage.sf,
        4 => TStage.qf,
        _ => TStage.early,
      };

  /// K.o.-Baum aus [entrants] (in Setz-Reihenfolge). Liefert die Runden.
  List<List<TMatch>> _buildKo(List<TSlot> entrants, String br, {bool thirdPlace = false, bool finalStage = true}) {
    final size = max(2, nextPow2(entrants.length));
    final pos = seedPositions(size);
    final rounds = <List<TMatch>>[];
    var cur = <TMatch>[];
    for (var i = 0; i < size / 2; i++) {
      TSlot slot(int seed) => seed <= entrants.length ? entrants[seed - 1] : const TSlot.bye();
      cur.add(TMatch(
        id: '$br-1-$i',
        bracket: br,
        round: 1,
        order: i,
        stage: _koStage(size ~/ 2),
        a: slot(pos[2 * i]),
        b: slot(pos[2 * i + 1]),
      ));
    }
    rounds.add(cur);
    var r = 1;
    while (cur.length > 1) {
      r++;
      final next = <TMatch>[];
      for (var i = 0; i < cur.length ~/ 2; i++) {
        next.add(TMatch(
          id: '$br-$r-$i',
          bracket: br,
          round: r,
          order: i,
          stage: _koStage(cur.length ~/ 2),
          a: TSlot.winnerOf(cur[2 * i].id),
          b: TSlot.winnerOf(cur[2 * i + 1].id),
        ));
      }
      rounds.add(next);
      cur = next;
    }
    if (!finalStage) {
      // Im Doppel-K.o. ist das Finale der Hauptrunde nur ein Halbfinale.
      for (final rd in rounds) {
        for (final m in rd) {
          final st = switch (rd.length) { 1 => TStage.sf, 2 => TStage.qf, _ => TStage.early };
          matches.add(TMatch(id: m.id, bracket: m.bracket, round: m.round, order: m.order, stage: st, a: m.a, b: m.b));
        }
      }
    } else {
      for (final rd in rounds) {
        matches.addAll(rd);
      }
    }
    if (thirdPlace && rounds.length >= 2) {
      final sf = rounds[rounds.length - 2];
      matches.add(TMatch(
        id: 'P3',
        bracket: 'P3',
        round: rounds.length,
        order: 1,
        stage: TStage.sf,
        a: TSlot.loserOf(sf[0].id),
        b: TSlot.loserOf(sf[1].id),
      ));
    }
    return rounds;
  }

  void _buildDoubleKo() {
    final wb = _buildKo([for (var i = 0; i < n; i++) TSlot.seed(i)], 'W', finalStage: false);
    final k = wb.length; // Runden der Hauptrunde
    final lbRounds = <List<TMatch>>[];
    var r = 0;
    // LB-Runde 1: Verlierer der ersten Hauptrunde gegeneinander.
    var prev = <TMatch>[];
    {
      r++;
      final w1 = wb[0];
      for (var i = 0; i < w1.length ~/ 2; i++) {
        prev.add(TMatch(
          id: 'L-$r-$i',
          bracket: 'L',
          round: r,
          order: i,
          stage: TStage.early,
          a: TSlot.loserOf(w1[2 * i].id),
          b: TSlot.loserOf(w1[2 * i + 1].id),
        ));
      }
      lbRounds.add(prev);
    }
    for (var j = 1; j < k; j++) {
      // Einstiegsrunde: Sieger der LB gegen Verlierer der Hauptrunde j+1.
      r++;
      final drop = wb[j];
      final reversed = j.isOdd;
      final cur = <TMatch>[];
      for (var i = 0; i < prev.length; i++) {
        final w = drop[reversed ? drop.length - 1 - i : i];
        cur.add(TMatch(
          id: 'L-$r-$i',
          bracket: 'L',
          round: r,
          order: i,
          stage: TStage.early,
          a: TSlot.winnerOf(prev[i].id),
          b: TSlot.loserOf(w.id),
        ));
      }
      lbRounds.add(cur);
      prev = cur;
      if (prev.length > 1) {
        r++;
        final cons = <TMatch>[];
        for (var i = 0; i < prev.length ~/ 2; i++) {
          cons.add(TMatch(
            id: 'L-$r-$i',
            bracket: 'L',
            round: r,
            order: i,
            stage: TStage.early,
            a: TSlot.winnerOf(prev[2 * i].id),
            b: TSlot.winnerOf(prev[2 * i + 1].id),
          ));
        }
        lbRounds.add(cons);
        prev = cons;
      }
    }
    for (var x = 0; x < lbRounds.length; x++) {
      final st = x == lbRounds.length - 1
          ? TStage.sf
          : x == lbRounds.length - 2
              ? TStage.qf
              : TStage.early;
      for (final m in lbRounds[x]) {
        matches.add(TMatch(id: m.id, bracket: 'L', round: m.round, order: m.order, stage: st, a: m.a, b: m.b));
      }
    }
    final wFinal = wb.last.single.id;
    final lFinal = lbRounds.last.single.id;
    matches.add(TMatch(
        id: 'F-1',
        bracket: 'F',
        round: 1,
        order: 0,
        stage: TStage.finale,
        a: TSlot.winnerOf(wFinal),
        b: TSlot.winnerOf(lFinal)));
    matches.add(TMatch(
        id: 'F-2',
        bracket: 'F',
        round: 2,
        order: 0,
        stage: TStage.finale,
        a: const TSlot.sideOf('F-1', 0),
        b: const TSlot.sideOf('F-1', 1),
        conditional: true));
  }

  /// Jeder gegen jeden (Kreis-Verfahren), optional mit Rückrunde.
  void _buildRoundRobin(List<int> ids, String br, int? group, bool twice) {
    final list = <int?>[...ids];
    if (list.length.isOdd) list.add(null);
    final m = list.length;
    final roundsOne = m - 1;
    var counter = 0;
    for (var leg = 0; leg < (twice ? 2 : 1); leg++) {
      final arr = List<int?>.of(list);
      for (var r = 0; r < roundsOne; r++) {
        for (var i = 0; i < m ~/ 2; i++) {
          final x = arr[i];
          final y = arr[m - 1 - i];
          if (x == null || y == null) continue;
          final swap = (r.isOdd && i == 0) != (leg == 1);
          matches.add(TMatch(
            id: '$br${group ?? ''}-${leg * roundsOne + r + 1}-$i',
            bracket: br,
            round: leg * roundsOne + r + 1,
            order: counter++,
            stage: TStage.group,
            a: TSlot.seed(swap ? y : x),
            b: TSlot.seed(swap ? x : y),
            group: group,
          ));
        }
        // rotieren (erstes Element bleibt fest)
        final last = arr.removeLast();
        arr.insert(1, last);
      }
    }
  }

  // ------------------------------------------------------------ Auflösung

  _R _resolve(TSlot s, [int depth = 0]) {
    if (depth > 200) return const _R.pending();
    switch (s.kind) {
      case 'seed':
        return s.index < 0 ? const _R.empty() : _R.player(s.index);
      case 'win':
      case 'lose':
        final m = matchById(s.match!);
        if (!isDecided(m, depth + 1)) return const _R.pending();
        final w = winnerOf(m, depth + 1);
        final l = loserOf(m, depth + 1);
        final v = s.kind == 'win' ? w : l;
        return v == null ? const _R.empty() : _R.player(v);
      case 'side':
        // Entscheidungsspiel: erst nach dem ersten Finale bekannt.
        final m = matchById(s.match!);
        if (!m.played) return const _R.pending();
        if (m.winnerSide == 0) return const _R.empty();
        return _resolve(s.index == 0 ? m.a : m.b, depth + 1);
      case 'q':
        final gm = matches.where((m) => m.bracket == 'G' && m.group == s.group).toList();
        if (gm.any((m) => !m.played)) return const _R.pending();
        final table = standings(group: s.group);
        if (s.place >= table.length) return const _R.empty();
        return _R.player(table[s.place].player);
    }
    return const _R.pending();
  }

  /// Teilnehmer eines Matches: Spielerindex, -1 = Freilos/leer, null = offen.
  (int?, int?) participants(TMatch m) {
    int? conv(_R r) => r.pending ? null : (r.player ?? -1);
    return (conv(_resolve(m.a)), conv(_resolve(m.b)));
  }

  /// Bedingtes Entscheidungsspiel überflüssig?
  bool isSkipped(TMatch m, [int depth = 0]) {
    if (!m.conditional) return false;
    final f = matchById((m.a).match!);
    if (!f.played) return false;
    return f.winnerSide == 0;
  }

  /// Ist das Ergebnis eines Matches bekannt (gespielt, Freilos oder überflüssig)?
  bool isDecided(TMatch m, [int depth = 0]) {
    if (m.played) return true;
    if (m.conditional) return isSkipped(m, depth);
    final a = _resolve(m.a, depth);
    final b = _resolve(m.b, depth);
    if (a.pending || b.pending) return false;
    return a.isEmpty || b.isEmpty;
  }

  int? winnerOf(TMatch m, [int depth = 0]) {
    if (m.conditional && isSkipped(m, depth)) return null;
    final a = _resolve(m.a, depth);
    final b = _resolve(m.b, depth);
    if (m.played) return m.winnerSide == 0 ? a.player : b.player;
    if (a.pending || b.pending) return null;
    return a.player ?? b.player;
  }

  int? loserOf(TMatch m, [int depth = 0]) {
    if (!m.played) return null;
    final a = _resolve(m.a, depth);
    final b = _resolve(m.b, depth);
    return m.winnerSide == 0 ? b.player : a.player;
  }

  /// Kann gespielt werden (beide Spieler stehen fest, noch kein Ergebnis).
  bool isPlayable(TMatch m) {
    if (m.played || isDecided(m)) return false;
    final (a, b) = participants(m);
    return a != null && b != null && a >= 0 && b >= 0;
  }

  /// Ein echtes Spiel (kein Freilos, nicht übersprungen)?
  bool isRealMatch(TMatch m) {
    if (m.played) return true;
    if (isSkipped(m)) return false;
    final (a, b) = participants(m);
    return !(a == -1 || b == -1);
  }

  List<TMatch> get playable => [for (final m in matches) if (isPlayable(m)) m];

  bool get allDone => matches.every(isDecided);

  int get playedCount => matches.where((m) => m.played).length;
  int get realCount => matches.where(isRealMatch).length;

  /// Trägt ein Ergebnis ein.
  void record(String matchId,
      {required int winnerSide, required List<int> legs, List<int>? sets, List<int>? points, List<int>? darts}) {
    final m = matchById(matchId);
    m.winnerSide = winnerSide;
    m.legs = List.of(legs);
    m.sets = List.of(sets ?? [0, 0]);
    m.points = List.of(points ?? [0, 0]);
    m.darts = List.of(darts ?? [0, 0]);
    finished = allDone;
  }

  /// Darf das Ergebnis zurückgenommen werden? (kein Folge-Match gespielt)
  bool canReset(TMatch m) {
    if (!m.played) return false;
    final dependents = matches.where((x) =>
        x.played && x != m && (x.a.match == m.id || x.b.match == m.id || _dependsOnGroup(x, m)));
    return dependents.isEmpty;
  }

  bool _dependsOnGroup(TMatch x, TMatch m) =>
      m.bracket == 'G' && ((x.a.kind == 'q' && x.a.group == m.group) || (x.b.kind == 'q' && x.b.group == m.group));

  void reset(TMatch m) {
    m.winnerSide = null;
    m.legs = [0, 0];
    m.sets = [0, 0];
    m.points = [0, 0];
    m.darts = [0, 0];
    finished = false;
  }

  // ------------------------------------------------------------ Tabelle

  /// Tabelle der Gruppe [group] bzw. der Liga (group = null).
  List<TStanding> standings({int? group}) {
    final ms = matches
        .where((m) => group == null ? m.bracket == 'LG' : (m.bracket == 'G' && m.group == group))
        .toList();
    final ids = <int>{};
    for (final m in ms) {
      ids.add(m.a.index);
      ids.add(m.b.index);
    }
    if (system == TSystem.groups && group != null) ids.addAll(groupMembers()[group]);
    if (system == TSystem.league) ids.addAll(List.generate(n, (i) => i));
    final table = {for (final i in ids) i: TStanding(i)};
    final h2h = <String, int>{};
    for (final m in ms.where((m) => m.played)) {
      final pa = m.a.index;
      final pb = m.b.index;
      final sa = table[pa]!;
      final sb = table[pb]!;
      sa.played++;
      sb.played++;
      sa.legsFor += m.legs[0];
      sa.legsAgainst += m.legs[1];
      sb.legsFor += m.legs[1];
      sb.legsAgainst += m.legs[0];
      sa.points += m.points[0];
      sa.darts += m.darts[0];
      sb.points += m.points[1];
      sb.darts += m.darts[1];
      final w = m.winnerSide == 0 ? pa : pb;
      final l = m.winnerSide == 0 ? pb : pa;
      table[w]!.wins++;
      table[l]!.losses++;
      h2h['$w>$l'] = (h2h['$w>$l'] ?? 0) + 1;
    }
    final list = table.values.toList();
    list.sort((x, y) {
      var c = y.wins.compareTo(x.wins);
      if (c != 0) return c;
      c = y.legDiff.compareTo(x.legDiff);
      if (c != 0) return c;
      c = (h2h['${y.player}>${x.player}'] ?? 0).compareTo(h2h['${x.player}>${y.player}'] ?? 0);
      if (c != 0) return c;
      c = y.average.compareTo(x.average);
      if (c != 0) return c;
      return x.player.compareTo(y.player);
    });
    return list;
  }

  // ------------------------------------------------------------ Ergebnis

  int? get champion {
    if (!finished) return null;
    return placements().where((p) => p.rank == 1).firstOrNull?.player;
  }

  /// Endplatzierungen (gleicher Rang bei gleichem Ausscheiden).
  List<TPlacement> placements() {
    final out = <TPlacement>[];
    switch (system) {
      case TSystem.league:
        final t = standings();
        for (var i = 0; i < t.length; i++) {
          out.add(TPlacement(t[i].player, i + 1));
        }
        return out;
      case TSystem.ko:
      case TSystem.groups:
        return _koPlacements();
      case TSystem.doubleKo:
        return _doubleKoPlacements();
    }
  }

  List<TPlacement> _rank(List<List<int>> tiers) {
    final out = <TPlacement>[];
    var rank = 1;
    for (final tier in tiers) {
      if (tier.isEmpty) continue;
      for (final p in tier) {
        out.add(TPlacement(p, rank));
      }
      rank += tier.length;
    }
    return out;
  }

  List<TPlacement> _koPlacements() {
    final ko = matches.where((m) => m.bracket == 'W').toList();
    if (ko.isEmpty) return [];
    final maxRound = ko.map((m) => m.round).reduce(max);
    final fin = ko.firstWhere((m) => m.round == maxRound);
    final tiers = <List<int>>[];
    final w = winnerOf(fin);
    final l = loserOf(fin);
    tiers.add([?w]);
    tiers.add([?l]);
    final p3 = matches.where((m) => m.bracket == 'P3').firstOrNull;
    final placed = <int>{?w, ?l};
    if (p3 != null) {
      final w3 = winnerOf(p3);
      final l3 = loserOf(p3);
      tiers.add([?w3]);
      tiers.add([?l3]);
      placed.addAll([?w3, ?l3]);
    }
    for (var r = maxRound - 1; r >= 1; r--) {
      final tier = <int>[];
      for (final m in ko.where((m) => m.round == r)) {
        final lo = loserOf(m);
        if (lo != null && !placed.contains(lo)) tier.add(lo);
      }
      placed.addAll(tier);
      tiers.add(tier);
    }
    if (system == TSystem.groups) {
      // Ausgeschiedene der Gruppenphase: nach Gruppenplatz, dann Siege/Legs/Average.
      final rest = <(int, TStanding)>[];
      for (var g = 0; g < groupCount; g++) {
        final t = standings(group: g);
        for (var i = 0; i < t.length; i++) {
          if (!placed.contains(t[i].player)) rest.add((i, t[i]));
        }
      }
      final places = rest.map((e) => e.$1).toSet().toList()..sort();
      for (final pl in places) {
        final tier = rest.where((e) => e.$1 == pl).map((e) => e.$2).toList()
          ..sort((x, y) {
            var c = y.wins.compareTo(x.wins);
            if (c != 0) return c;
            c = y.legDiff.compareTo(x.legDiff);
            if (c != 0) return c;
            return y.average.compareTo(x.average);
          });
        for (final s in tier) {
          tiers.add([s.player]);
        }
      }
    }
    return _rank(tiers);
  }

  List<TPlacement> _doubleKoPlacements() {
    final f1 = matchById('F-1');
    final f2 = matchById('F-2');
    final last = isSkipped(f2) || !f2.played ? f1 : f2;
    final tiers = <List<int>>[];
    final w = winnerOf(last);
    final l = last.played ? loserOf(last) : null;
    tiers.add([?w]);
    tiers.add([?l]);
    final placed = <int>{?w, ?l};
    final lb = matches.where((m) => m.bracket == 'L').toList();
    if (lb.isNotEmpty) {
      final maxR = lb.map((m) => m.round).reduce(max);
      for (var r = maxR; r >= 1; r--) {
        final tier = <int>[];
        for (final m in lb.where((m) => m.round == r)) {
          final lo = loserOf(m);
          if (lo != null && !placed.contains(lo)) tier.add(lo);
        }
        placed.addAll(tier);
        tiers.add(tier);
      }
    }
    return _rank(tiers);
  }

  // ------------------------------------------------------------ Anzeige

  String roundLabel(TMatch m) {
    switch (m.bracket) {
      case 'P3':
        return 'Spiel um Platz 3';
      case 'F':
        return m.round == 1 ? 'Finale' : 'Entscheidungsspiel';
      case 'G':
        return 'Gruppe ${String.fromCharCode(65 + (m.group ?? 0))} · Spieltag ${m.round}';
      case 'LG':
        return 'Spieltag ${m.round}';
      case 'L':
        final maxR = matches.where((x) => x.bracket == 'L').map((x) => x.round).reduce(max);
        return m.round == maxR ? 'Finale Verliererrunde' : 'Verliererrunde ${m.round}';
      default:
        final inRound = matches.where((x) => x.bracket == 'W' && x.round == m.round).length;
        final name = switch (inRound) {
          1 => 'Finale',
          2 => 'Halbfinale',
          4 => 'Viertelfinale',
          8 => 'Achtelfinale',
          _ => 'Runde ${m.round}',
        };
        return system == TSystem.doubleKo ? 'Hauptrunde · $name' : name;
    }
  }

  // ------------------------------------------------------------ JSON

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created': created.toIso8601String(),
        'system': system.name,
        'players': players.map((p) => p.toJson()).toList(),
        'start': start,
        'doubleOut': doubleOut,
        'formats': formats.map((k, v) => MapEntry(k.name, v.toJson())),
        'homeAway': homeAway,
        'groupCount': groupCount,
        'advance': advance,
        'matches': matches.map((m) => m.toJson()).toList(),
        'finished': finished,
      };

  factory Tournament.fromJson(Map<String, dynamic> j) => Tournament(
        id: j['id'] as String,
        name: j['name'] as String,
        created: DateTime.parse(j['created'] as String),
        system: TSystem.values.byName(j['system'] as String),
        players: [for (final p in j['players'] as List) TPlayer.fromJson(Map<String, dynamic>.from(p as Map))],
        start: j['start'] as int,
        doubleOut: j['doubleOut'] as bool,
        formats: {
          for (final e in (j['formats'] as Map).entries)
            TStage.values.byName(e.key as String): TFormat.fromJson(Map<String, dynamic>.from(e.value as Map)),
        },
        homeAway: j['homeAway'] as bool? ?? false,
        groupCount: j['groupCount'] as int? ?? 2,
        advance: j['advance'] as int? ?? 2,
        matches: [for (final m in j['matches'] as List) TMatch.fromJson(Map<String, dynamic>.from(m as Map))],
        finished: j['finished'] as bool? ?? false,
      );
}

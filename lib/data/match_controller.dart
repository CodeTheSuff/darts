import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'error_log.dart';
import '../games/bot.dart';
import '../games/catalog.dart';
import '../games/engine.dart';
import '../games/x01.dart';
import '../models/dart.dart';
import '../models/player.dart';
import '../net/link.dart';
import 'storage.dart';

/// Hält ein laufendes Match: Konfiguration + alle geworfenen Pfeile.
/// Der Spielstand wird bei Bedarf aus den Pfeilen neu berechnet (Undo, Fortsetzen).
class MatchController extends ChangeNotifier {
  MatchController({
    required this.config,
    required this.players,
    this.startIndex = 0,
    int? seed,
    List<Dart>? darts,
    this.tournamentId,
    this.tournamentMatchId,
    String? matchId,
  })  : seed = seed ?? Random().nextInt(1 << 31),
        matchId = matchId ?? Store.newId('m'),
        darts = darts ?? [] {
    _rebuild();
  }

  final GameConfig config;
  final List<GamePlayer> players;
  final int startIndex;
  final int seed;
  final List<Dart> darts;

  /// Eindeutige Kennung des Matches – auf allen gekoppelten Geräten gleich.
  final String matchId;

  /// Gast in einem gekoppelten Spiel: Würfe gehen an den Host, der Stand kommt vom Host.
  bool remote = false;

  final _ext = StreamController<ThrowEvent>.broadcast();

  /// Zählt komplette Neuaufbauten durch den Host (z. B. nach Undo auf einem anderen Gerät).
  int resynced = 0;

  /// Würfe, die nicht über dieses Gerät eingegeben wurden (andere Handys, Host).
  Stream<ThrowEvent> get externalEvents => _ext.stream;
  late GameEngine engine;
  bool committed = false;

  /// Gehört das Match zu einem Turnier?
  final String? tournamentId;
  final String? tournamentMatchId;
  bool get isTournament => tournamentId != null && tournamentMatchId != null;

  /// Wird nach dem Eintragen der Statistik eines Turnier-Matches aufgerufen.
  static void Function(MatchController m)? onTournamentMatchDone;

  final Map<int, Bot> _bots = {};

  bool isBot(int i) => isBotId(players[i].profileId);
  bool get hasBot => List.generate(players.length, isBot).any((b) => b);

  /// Ist gerade ein Bot am Wurf?
  bool get botTurn => !engine.finished && isBot(engine.cur);

  /// Erzeugt den nächsten Pfeil des Bots, der am Wurf ist.
  Dart nextBotDart() {
    final i = engine.cur;
    final bot = _bots.putIfAbsent(i, () => Bot.forId(players[i].profileId));
    final e = engine;
    if (e.turn.isEmpty) bot.startVisit();
    if (e is X01Game) {
      return bot.next(e.scores[i], 3 - e.turn.length, doubleOut: e.doubleOutNow);
    }
    return bot.throwAt(const Aim(20, 3));
  }

  ModeDef get mode => modeById(config.modeId);

  void _rebuild() {
    engine = buildEngine(config, players, startIndex, seed);
    for (final d in darts) {
      engine.apply(d);
    }
  }

  ThrowEvent throwDart(Dart d) {
    if (engine.finished) return ThrowEvent(engine.cur);
    ErrorLog.crumb('Dart ${d.label} von ${players[engine.cur].name} (Dart ${darts.length + 1})');
    darts.add(d);
    final ev = engine.apply(d);
    if (remote) Link.I.sendToHost({'t': 'dart', 'mid': matchId, 'd': d.toJson()});
    _persist();
    notifyListeners();
    return ev;
  }

  /// Host: Wurf eines gekoppelten Geräts.
  void throwDartExternal(Dart d) {
    if (engine.finished || inputLocked || !isValidDart(d)) return;
    // Ist gerade ein Bot dran, gehört der Wurf nicht zu ihm (veralteter Stand beim Gast).
    if (botTurn && !d.isControl) return;
    final ev = throwDart(d);
    _ext.add(ev);
  }

  /// Host: Eingaben von außen gerade gesperrt (z. B. während einer Jubel-Animation).
  bool inputLocked = false;

  /// Nur echte Felder bzw. bekannte Markierungen zulassen.
  static bool isValidDart(Dart d) {
    if (d.isControl) return d.field == -1 && (d.mult == 0 || d.mult == 1);
    if (d.field == 0) return d.mult == 1;
    if (d.field == 25) return d.mult == 1 || d.mult == 2;
    return d.field >= 1 && d.field <= 20 && d.mult >= 1 && d.mult <= 3;
  }

  /// Gast: Stand vom Host übernehmen. Neue Würfe am Ende werden als Ereignisse
  /// gemeldet (für Sound und Animation), sonst wird neu aufgebaut.
  void applyRemote(List<Dart> remoteDarts) {
    String enc(Dart d) => jsonEncode(d.toJson());
    final local = darts.map(enc).toList();
    final other = remoteDarts.map(enc).toList();
    if (local.length == other.length && _same(local, other, local.length)) return;
    if (other.length > local.length && _same(local, other, local.length)) {
      for (final d in remoteDarts.sublist(local.length)) {
        darts.add(d);
        final ev = engine.apply(d);
        _ext.add(ev);
      }
    } else {
      darts
        ..clear()
        ..addAll(remoteDarts);
      _rebuild();
      resynced++;
    }
    notifyListeners();
  }

  static bool _same(List<String> a, List<String> b, int n) {
    for (var i = 0; i < n; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool get canUndo => darts.isNotEmpty && !committed && (!hasBot || _humanDartExistsCached);

  // Zwischenspeicher: die Prüfung spielt das Match nach – nur neu, wenn sich die Würfe ändern.
  int _undoLen = -1;
  Dart? _undoLast;
  bool _undoVal = false;

  bool get _humanDartExistsCached {
    final last = darts.isEmpty ? null : darts.last;
    if (_undoLen != darts.length || !identical(_undoLast, last)) {
      _undoLen = darts.length;
      _undoLast = last;
      _undoVal = _humanDartExists;
    }
    return _undoVal;
  }

  bool get _humanDartExists {
    // Gibt es noch einen Pfeil eines Menschen, der zurückgenommen werden kann?
    final probe = buildEngine(config, players, startIndex, seed);
    for (final d in darts) {
      if (!isBotId(players[probe.cur].profileId)) return true;
      probe.apply(d);
    }
    return false;
  }

  void undo() {
    ErrorLog.crumb('Rückgängig (Dart ${darts.length})');
    if (!canUndo) return;
    if (remote) Link.I.sendToHost({'t': 'undo', 'mid': matchId});
    _removeLastDart();
    _rebuild();
    // Gegen Bots: dessen Aufnahme mit zurücknehmen, bis wieder ein Mensch dran ist.
    if (hasBot) {
      while (darts.isNotEmpty && botTurn) {
        _removeLastDart();
        _rebuild();
      }
    }
    _persist();
    notifyListeners();
  }

  /// Letzten echten Pfeil entfernen – samt Umschaltungen, die danach kamen.
  void _removeLastDart() {
    while (darts.isNotEmpty && darts.last.isControl) {
      darts.removeLast();
    }
    if (darts.isNotEmpty) darts.removeLast();
  }

  /// Single Out für das laufende Leg an- oder ausschalten (nur X01 mit Double Out).
  void setSingleOut(bool on) {
    final e = engine;
    if (e is! X01Game || e.finished || !e.doubleOut || e.singleOutLeg == on) return;
    throwDart(on ? Dart.singleOutOn : Dart.singleOutOff);
  }

  /// Neues Match mit denselben Spielern; der Anwurf rückt einen Platz weiter.
  MatchController rematch() => MatchController(
        config: config,
        players: players,
        startIndex: (startIndex + 1) % players.length,
      );

  /// Gesamt gewonnene Legs bzw. Sets je Spieler (für Turnier-Ergebnisse).
  List<int> get legsWon {
    final e = engine;
    return e is X01Game ? List.of(e.legsTotal) : List.filled(players.length, 0);
  }

  List<int> get setsWon {
    final e = engine;
    return e is X01Game ? List.of(e.sets) : List.filled(players.length, 0);
  }

  List<double> get averages {
    final e = engine;
    return e is X01Game ? [for (final s in e.stats) s.average] : List.filled(players.length, 0);
  }

  int? get winnerIndex {
    if (!engine.finished) return null;
    return engine.results().first.playerIndex;
  }

  void _persist() {
    if (remote) return;
    if (engine.finished) {
      Store.activeMatch = null;
      return;
    }
    Store.activeMatch = toJson();
  }

  /// Schreibt die Statistik eines beendeten Matches (einmalig).
  void commitStats() {
    if (committed || !engine.finished) return;
    committed = true;
    if (!remote) Store.activeMatch = null;
    final results = engine.results();
    final botIdx = [for (var i = 0; i < players.length; i++) if (isBot(i)) i];
    final now = DateTime.now().millisecondsSinceEpoch;
    final entries = <LogEntry>[];
    for (var i = 0; i < players.length; i++) {
      final id = players[i].profileId;
      if (isBotId(id)) continue;
      final s = PlayerStats();
      final r = results.firstWhere((x) => x.playerIndex == i);
      for (final b in botIdx) {
        final key = botLevelOf(players[b].profileId)?.name ?? (customBotOf(players[b].profileId) != null ? 'custom' : null);
        if (key == null) continue;
        final botRank = results.firstWhere((x) => x.playerIndex == b).rank;
        if (r.rank == botRank) continue; // Gleichstand zählt weder als Sieg noch als Niederlage
        s.bots[key] = r.rank < botRank ? [1, 0] : [0, 1];
      }
      final e = engine;
      if (e is X01Game) s.x01.merge(e.stats[i]);
      final ms = s.modes.putIfAbsent(config.modeId, ModeStats.new);
      ms.played = 1;
      if (r.won && players.length > 1) ms.wins = 1;
      if (r.metric != null && mode.metricLabel != null) ms.best = r.metric;
      // Spieler eines anderen Geräts (gekoppeltes Spiel) auf lokale Spieler abbilden.
      final local = Store.resolveForeign(id, players[i].name);
      entries.add(LogEntry(rid: matchId, oid: id, pid: local, t: now, mode: config.modeId, d: s));
    }
    Store.addEntries(entries);
    Store.addRecords([toRecord(now)]);
    if (isTournament) onTournamentMatchDone?.call(this);
    onMatchCommitted?.call(this);
  }

  /// Wird nach jedem gespeicherten Match aufgerufen (z. B. Abgleich mit gekoppelten Handys).
  static void Function(MatchController m)? onMatchCommitted;

  MatchRecord toRecord(int t) => MatchRecord(
        rid: matchId,
        t: t,
        mode: config.modeId,
        options: Map.of(config.options),
        players: [for (final p in players) (p.profileId, p.name, p.color)],
        start: startIndex,
        seed: seed,
        darts: [for (final d in darts) d.code],
        tid: tournamentId,
      );

  /// Engine aus einem archivierten Match neu aufbauen.
  static GameEngine replay(MatchRecord r) {
    final e = buildEngine(
      GameConfig(r.mode, r.options),
      [for (final (id, n, c) in r.players) GamePlayer(id, n, c)],
      r.start,
      r.seed,
    );
    for (final code in r.darts) {
      e.apply(Dart.fromCode(code));
    }
    return e;
  }

  Map<String, dynamic> toJson() => {
        'config': config.toJson(),
        'players': players.map((p) => p.toJson()).toList(),
        'start': startIndex,
        'seed': seed,
        'darts': darts.map((d) => d.toJson()).toList(),
        'mid': matchId,
        if (tournamentId != null) 'tid': tournamentId,
        if (tournamentMatchId != null) 'tmid': tournamentMatchId,
      };

  static MatchController? fromJson(Map<String, dynamic> j) {
    try {
      return MatchController(
        config: GameConfig.fromJson(Map<String, dynamic>.from(j['config'] as Map)),
        players: (j['players'] as List)
            .map((e) => GamePlayer.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        startIndex: j['start'] as int,
        seed: j['seed'] as int,
        darts: (j['darts'] as List)
            .map((e) => Dart.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        tournamentId: j['tid'] as String?,
        tournamentMatchId: j['tmid'] as String?,
        matchId: j['mid'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

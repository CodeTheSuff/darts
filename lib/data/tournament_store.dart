import 'error_log.dart';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../games/engine.dart';
import '../games/tournament.dart';
import '../games/x01.dart';
import '../models/player.dart';
import '../ui/theme.dart';
import 'match_controller.dart';
import 'storage.dart';

/// Laden/Speichern der Turniere und Verknüpfung mit laufenden Matches.
class TournamentStore {
  TournamentStore._();

  static List<Tournament> all() {
    final out = <Tournament>[];
    for (final j in Store.tournaments) {
      try {
        out.add(Tournament.fromJson(j));
      } catch (_) {
        // defekte Einträge überspringen
      }
    }
    out.sort((a, b) => b.created.compareTo(a.created));
    return out;
  }

  static List<Tournament> get running => all().where((t) => !t.finished).toList();
  static List<Tournament> get history => all().where((t) => t.finished).toList();

  static Tournament? byId(String id) => all().where((t) => t.id == id).firstOrNull;

  /// Meldet jede Änderung (z. B. Ergebnis eines Matches, das ein anderes Gerät gestartet hat).
  static final changes = ValueNotifier<int>(0);

  static void save(Tournament t) {
    ErrorLog.crumb('Turnier gespeichert: ${t.name}');
    final list = Store.tournaments;
    final i = list.indexWhere((j) => j['id'] == t.id);
    if (i >= 0) {
      list[i] = t.toJson();
    } else {
      list.add(t.toJson());
    }
    Store.tournaments = list;
    changes.value++;
  }

  static void delete(String id) {
    Store.tournaments = Store.tournaments.where((j) => j['id'] != id).toList();
    final active = Store.activeMatch;
    if (active != null && active['tid'] == id) Store.activeMatch = null;
  }

  static String newId() => '${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(999)}';

  /// Spielstärke für die Setzliste (X01-Average, 0 = unbekannt).
  static double averageOf(String profileId) => Store.statsFor(profileId).x01.average;

  /// Setzliste: nach Average, Spieler ohne Statistik zufällig ans Ende.
  static List<TPlayer> seedByAverage(List<TPlayer> players, {Random? rng}) {
    final known = players.where((p) => averageOf(p.profileId) > 0).toList()
      ..sort((a, b) => averageOf(b.profileId).compareTo(averageOf(a.profileId)));
    final unknown = players.where((p) => averageOf(p.profileId) <= 0).toList()..shuffle(rng ?? Random());
    return [...known, ...unknown];
  }

  /// Baut das Match für eine Turnierpartie.
  static MatchController controllerFor(Tournament t, TMatch m, int startSide) {
    final (a, b) = t.participants(m);
    final pa = t.players[a!];
    final pb = t.players[b!];
    final f = t.formatOf(m.stage);
    final config = GameConfig('x01', {
      'start': t.start,
      'doubleOut': t.doubleOut,
      'format': f.sets ? 'sets' : 'legs',
      'legs': f.legs,
      'sets': f.setCount,
    });
    return MatchController(
      config: config,
      players: [
        GamePlayer(pa.profileId, pa.name, C.players[0].toARGB32()),
        GamePlayer(pb.profileId, pb.name, C.players[1].toARGB32()),
      ],
      startIndex: startSide,
      tournamentId: t.id,
      tournamentMatchId: m.id,
    );
  }

  /// Läuft gerade ein (pausiertes) Match dieses Turniers?
  static MatchController? activeFor(Tournament t, [String? matchId]) {
    final j = Store.activeMatch;
    if (j == null || j['tid'] != t.id) return null;
    if (matchId != null && j['tmid'] != matchId) return null;
    return MatchController.fromJson(j);
  }

  /// Wird vom MatchController nach einem beendeten Turnier-Match aufgerufen.
  static void onMatchDone(MatchController c) {
    final t = byId(c.tournamentId!);
    if (t == null) return;
    final m = t.matches.where((x) => x.id == c.tournamentMatchId).firstOrNull;
    if (m == null || m.played) return;
    final w = c.winnerIndex;
    if (w == null) return;
    final (pa, _) = t.participants(m);
    // Spieler 0 im Match ist immer Seite A.
    final aIsFirst = t.players[pa!].profileId == c.players[0].profileId;
    int side(int playerIdx) => aIsFirst ? playerIdx : 1 - playerIdx;
    List<int> bySide(List<num> v) => aIsFirst ? [v[0].toInt(), v[1].toInt()] : [v[1].toInt(), v[0].toInt()];
    final e = c.engine;
    final pts = <num>[0, 0];
    final darts = <num>[0, 0];
    if (e is X01Game) {
      for (var i = 0; i < 2; i++) {
        pts[i] = e.stats[i].points;
        darts[i] = e.stats[i].darts;
      }
    }
    t.record(
      m.id,
      winnerSide: side(w),
      legs: bySide(c.legsWon),
      sets: bySide(c.setsWon),
      points: bySide(pts),
      darts: bySide(darts),
    );
    if (t.finished) _finish(t);
    save(t);
  }

  static void _finish(Tournament t) {
    final now = DateTime.now().millisecondsSinceEpoch;
    Store.addEntries([
      for (final pl in t.placements())
        LogEntry(
          rid: 'tour-${t.id}',
          oid: t.players[pl.player].profileId,
          pid: t.players[pl.player].profileId,
          t: now,
          mode: 'tournament',
          d: PlayerStats()
            ..tournaments = 1
            ..tournamentWins = pl.rank == 1 ? 1 : 0
            ..podiums = pl.rank <= 3 ? 1 : 0,
        ),
    ]);
  }
}

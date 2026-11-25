import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/callouts.dart';
import '../data/match_controller.dart';
import '../data/match_report.dart';
import '../data/storage.dart';

import '../games/engine.dart';
import '../games/x01.dart';
import '../games/tournament.dart';
import '../models/dart.dart';
import '../net/link.dart';
import '../platform/fullscreen_button.dart';
import 'board_grid.dart';
import 'display_waiting.dart';
import 'celebration.dart';
import 'link_coordinator.dart';
import 'stats_table.dart';
import 'theme.dart';
import 'tournament_display.dart';

/// Reine Anzeige für ein gekoppeltes Gerät (z. B. Tablet an der Wand neben dem Board):
/// riesige Restpunkte, die drei Pfeile der Aufnahme, Jubel-Animationen und
/// ein hervorgehobener Sieger. Im Turnier Baum bzw. Tabelle.
class ScoreboardScreen extends StatefulWidget {
  const ScoreboardScreen({super.key});

  @override
  State<ScoreboardScreen> createState() => _ScoreboardScreenState();
}

/// Eine anstehende Jubel-Animation (mit Spiel, damit Namen/Farben passen).
class _Show {
  _Show(this.board, this.engine, this.kind, this.player, this.darts, this.value, this.label);
  final _Board board;
  final GameEngine engine;
  final CelebrationKind kind;
  final int player;
  final List<Dart> darts;
  final int? value;
  final String? label;
}

/// Ein laufendes Spiel auf der Anzeige („Scheibe“). Ohne `boards` vom Host gibt es
/// genau eines mit n = 0 (das Match des Host-Geräts).
class _Board {
  _Board(this.n, this.name, this.ctl);
  int n;
  String name;
  final MatchController ctl;
  StreamSubscription<ThrowEvent>? sub;

  /// Leg-Statistik bis zum ersten Dart des nächsten Legs, Match-Statistik bis zum nächsten Match.
  LegReport? leg;
  bool matchStats = false;
}

class _ScoreboardScreenState extends State<ScoreboardScreen> {

  MatchReport? _report(MatchController c) =>
      MatchReport.build(config: c.config, players: c.players, startIndex: c.startIndex, seed: c.seed, darts: c.darts);

  /// Laufende Spiele nach Scheiben-Nummer (aufsteigend).
  var _boards = <int, _Board>{};

  /// Zuletzt beendetes Spiel (für die Turnier-Ansicht zwischen den Spielen).
  MatchController? _lastDone;

  /// Statistik des letzten Spiels, wenn es zum gezeigten Turnier gehört.
  Widget? _lastMatchView(Tournament t) {
    final c = _lastDone;
    if (c == null || c.tournamentId != t.id) return null;
    final r = _report(c);
    return r != null ? _BoardStats(engine: c.engine, report: r) : _MatchBoard(engine: c.engine);
  }
  final _queue = <_Show>[];
  _Show? _show;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    // Im Browser gibt es keinen System-UI-Modus (Vollbild dort per Taste oben rechts).
    if (!kIsWeb) SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable().catchError((_) {});
    LinkCoordinator.viewerState.addListener(_onState);
    Callouts.isDisplay = true;
    _onState(rebuild: false);
  }

  @override
  void dispose() {
    LinkCoordinator.viewerState.removeListener(_onState);
    Callouts.isDisplay = false;
    for (final b in _boards.values) {
      b.sub?.cancel();
    }
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    if (!kIsWeb) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  /// Neuer Stand vom Host: laufende Spiele fortschreiben (dabei entstehen
  /// Wurf-Ereignisse für Ansagen und Animationen) oder neu aufbauen.
  /// Liefert der Host `boards`, gelten nur diese, sonst das eine `match`.
  void _onState({bool rebuild = true}) {
    final st = LinkCoordinator.viewerState.value;
    final incoming = <(int, String, Map<String, dynamic>)>[];
    final raw = st?['boards'];
    if (raw is List && raw.isNotEmpty) {
      for (final b in raw) {
        if (b is! Map) continue;
        final n = b['n'];
        final mj = b['match'];
        if (n is! num || mj is! Map) continue;
        final name = b['name'];
        incoming.add((
          n.toInt(),
          name is String && name.isNotEmpty ? name : 'Scheibe ${n.toInt()}',
          Map<String, dynamic>.from(mj),
        ));
      }
      incoming.sort((a, b) => a.$1.compareTo(b.$1));
    } else {
      final mj = st?['match'];
      if (mj is Map) incoming.add((0, '', Map<String, dynamic>.from(mj)));
    }
    // Vorhandene Controller per matchId wiederverwenden (auch wenn sich die Nummer ändert).
    final old = {for (final b in _boards.values) b.ctl.matchId: b};
    final next = <int, _Board>{};
    for (final (n, name, j) in incoming) {
      if (next.containsKey(n)) continue;
      final cur = old.remove(j['mid']);
      if (cur != null) {
        cur
          ..n = n
          ..name = name;
        next[n] = cur;
        try {
          cur.ctl.applyRemote([for (final d in j['darts'] as List) Dart.fromJson(Map<String, dynamic>.from(d as Map))]);
        } catch (_) {}
      } else {
        MatchController? c;
        try {
          c = MatchController.fromJson(j);
        } catch (_) {}
        if (c != null) next[n] = _newBoard(n, name, c);
      }
    }
    // Verschwundene bzw. ersetzte Spiele aufräumen (samt ihrer ausstehenden Jubel).
    for (final b in old.values) {
      // Beendetes Spiel bleibt zwischen den Spielen als Ansicht „Letztes Spiel“ abrufbar.
      if (b.ctl.engine.finished) _lastDone = b.ctl;
      b.sub?.cancel();
      _queue.removeWhere((s) => s.board == b);
      if (_show?.board == b) _show = null;
    }
    _boards = next;
    if (rebuild && mounted) setState(() {});
    if (rebuild) _next();
  }

  _Board _newBoard(int n, String name, MatchController c) {
    final b = _Board(n, name, c);
    // Schon beendetes Match (z. B. Anzeige später verbunden): gleich die Statistik
    b.matchStats = c.engine.finished && c.engine is X01Game;
    b.sub = c.externalEvents.listen((ev) => _onEvent(b, ev));
    return b;
  }

  /// Allein gezeigte Scheibe; null = alle (geteilter Bildschirm) bzw. keine.
  /// Eine gewählte Scheibe, die es nicht (mehr) gibt, zählt als „Alle“.
  _Board? get _single {
    if (_boards.length == 1) return _boards.values.first;
    final sel = Store.viewerBoard;
    return sel == 0 ? null : _boards[sel];
  }

  /// Ansagen und Jubel nur für sichtbare Spiele.
  bool _visible(_Board b) {
    final s = _single;
    return s == null || identical(s, b);
  }

  void _select(int n) {
    Store.viewerBoard = n;
    _queue.removeWhere((s) => !_visible(s.board));
    setState(() {});
  }

  void _onEvent(_Board b, ThrowEvent ev) {
    if (!identical(_boards[b.n], b) || ev.control) return;
    final e = b.ctl.engine;
    final visible = _visible(b);
    if (visible) Callouts.onThrow(ev, e);
    // Der erste Dart des nächsten Legs (bzw. beim Weiterspielen) schließt die Statistik.
    if (b.leg != null || b.matchStats) {
      b.leg = null;
      b.matchStats = false;
      if (mounted) setState(() {});
    }
    if (!ev.turnEnded) return;
    if (e is X01Game) {
      final kind = ev.celebration == null ? null : kindOf(ev.celebration!);
      final legOver = kind == CelebrationKind.legWon || kind == CelebrationKind.highFinish;
      if (ev.gameOver) {
        b.matchStats = true;
      } else if (legOver) {
        b.leg = _report(b.ctl)?.lastFinishedLeg;
      }
      if (mounted) setState(() {});
    }
    // Caller-Ansage auch auf der Anzeige (wenn dort eingeschaltet)
    if (!visible || !Store.celebrations) return;
    if (ev.celebration != null) {
      final kind = kindOf(ev.celebration!);
      if (!(kind == CelebrationKind.legWon && ev.gameOver)) {
        var label = ev.celebrationLabel;
        if (kind == CelebrationKind.legWon && e.legsToWin == null) label = 'GESCHAFFT!';
        _queue.add(_Show(b, e, kind, ev.playerIndex, ev.turnDarts, ev.celebrationValue, label));
      }
    }
    if (ev.gameOver) {
      final w = e.results().first.playerIndex;
      _queue.add(
        _Show(
          b,
          e,
          CelebrationKind.match,
          w,
          w == ev.playerIndex ? ev.turnDarts : const [],
          null,
          e.n == 1 ? 'GESCHAFFT' : (e.legsToWin != null ? 'MATCH GEWONNEN' : 'SIEG'),
        ),
      );
    }
    _next();
  }

  void _next() {
    if (_show != null || _queue.isEmpty || !mounted) return;
    setState(() => _show = _queue.removeAt(0));
  }

  void _done() {
    setState(() => _show = null);
    _next();
  }

  Future<void> _leave() async {
    LinkCoordinator.viewer = false;
    await Link.I.leave();
    if (mounted) Navigator.of(context).pop();
  }

  // Turnier nur neu einlesen, wenn es sich geändert hat (unverändert = gleiches Objekt).
  Object? _tourSrc;
  Tournament? _tour;

  Tournament? _tournament(Object? tj) {
    if (!identical(tj, _tourSrc)) {
      _tourSrc = tj;
      _tour = null;
      if (tj is Map) {
        try {
          _tour = Tournament.fromJson(Map<String, dynamic>.from(tj));
        } catch (_) {}
      }
    }
    return _tour;
  }

  @override
  Widget build(BuildContext context) {
    final tj = LinkCoordinator.viewerState.value?['tournament'];
    final t = _tournament(tj);
    final multi = _boards.length >= 2;
    final single = _single;
    final next = t == null
        ? null
        : nextMatchLabel(t, except: [for (final b in _boards.values) b.ctl.tournamentMatchId]);
    Widget body;
    if (single != null) {
      final c = single.ctl;
      final label = multi ? single.name : null;
      final r = (single.leg != null || single.matchStats) ? _report(c) : null;
      body = r != null
          ? _BoardStats(engine: c.engine, report: r, leg: single.matchStats ? null : single.leg, board: label)
          : _MatchBoard(engine: c.engine, next: next, board: label);
    } else if (multi) {
      body = Column(
        children: [
          if (next != null) nextUpBar(next, 0.9),
          Expanded(
            child: BoardGrid(boards: [for (final b in _boards.values) BoardEntry(b.name, b.ctl.engine)]),
          ),
        ],
      );
    } else if (t != null) {
      body = TournamentDisplay(t: t, lastMatch: _lastMatchView(t));
    } else {
      body = _waiting();
    }
    if (multi) {
      body = Column(
        children: [
          _boardBar(single),
          Expanded(child: body),
        ],
      );
    }
    final show = _show;
    return Scaffold(
      backgroundColor: C.bg,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -1.2),
            radius: 1.5,
            colors: [C.accent.withValues(alpha: 0.12), C.bg],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: body),
              // Verbindung zum Host weg: deutlich zeigen, dass der Stand gerade nicht aktuell ist.
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: ListenableBuilder(
                    listenable: Link.I,
                    builder: (_, _) {
                      final l = Link.I;
                      if (!l.isClient || l.isConnected) return const SizedBox.shrink();
                      final text = l.isOnline && l.relayStatus == RelayStatus.hostOffline
                          ? 'Host offline – Stand wird nachgeholt, sobald er wieder da ist'
                          : (l.status.isEmpty ? 'Verbindung verloren – verbinde neu …' : l.status);
                      return Center(
                        child: Container(
                          key: const ValueKey('viewer-offline'),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: C.danger.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(text,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 4,
                child: Row(
                  children: [
                    if (Link.I.isClient)
                      TextButton.icon(
                        onPressed: () => LinkCoordinator.setViewer(false),
                        icon: Icon(Icons.sports_esports_rounded, color: C.muted, size: 18),
                        label: Text('Mitspielen', style: TextStyle(color: C.muted)),
                      ),
                    FullscreenButton(color: C.muted),
                    IconButton(
                      tooltip: 'Anzeige beenden',
                      icon: Icon(Icons.close_rounded, color: C.muted),
                      onPressed: _leave,
                    ),
                  ],
                ),
              ),
              if (show != null) ...[
                Positioned.fill(
                  child: CelebrationOverlay(
                    key: ObjectKey(show),
                    kind: show.kind,
                    name: show.engine.players[show.player].name,
                    color: Color(show.engine.players[show.player].color),
                    darts: show.darts,
                    value: show.value,
                    label: show.label,
                    onDone: _done,
                  ),
                ),
                // Bei mehreren Spielen: zu welcher Scheibe der Jubel gehört
                if (multi)
                  Positioned(
                    top: 74,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                          decoration: BoxDecoration(
                            color: C.bg.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: C.accent.withValues(alpha: 0.7)),
                          ),
                          child: Text(
                            show.board.name.toUpperCase(),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                              color: C.accent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Leiste zur Auswahl: „Alle“ oder eine Scheibe (groß genug zum Antippen am Tablet).
  Widget _boardBar(_Board? single) {
    // Handy: kompakter, damit „Alle“ und zwei Scheiben ohne Scrollen passen.
    final narrow = MediaQuery.sizeOf(context).width < 600;
    Widget chip(String text, int n, bool sel) => Padding(
      padding: EdgeInsets.only(right: narrow ? 8 : 10),
      child: Material(
        key: ValueKey('board-chip-$n'),
        color: sel ? C.accent : C.surface.withValues(alpha: 0.7),
        shape: StadiumBorder(side: BorderSide(color: sel ? C.accent : C.border, width: 1.5)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _select(n),
          child: Container(
            constraints: BoxConstraints(minWidth: narrow ? 64 : 88, minHeight: 48),
            padding: EdgeInsets.symmetric(horizontal: narrow ? 14 : 22),
            alignment: Alignment.center,
            child: Text(
              text,
              style: TextStyle(fontSize: narrow ? 17 : 20, fontWeight: FontWeight.w800, color: sel ? C.bg : C.text),
            ),
          ),
        ),
      ),
    );
    return Container(
      height: 60,
      // rechts Platz für „Mitspielen“ und „Anzeige beenden“
      margin: EdgeInsets.only(right: Link.I.isClient ? 190 : 56),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            chip('Alle', 0, single == null),
            for (final b in _boards.values) chip(b.name, b.n, identical(single, b)),
          ],
        ),
      ),
    );
  }

  /// Wartebildschirm: großes, pulsierendes Logo, Status der Verbindung.
  Widget _waiting() => const DisplayWaiting();
}

/// „Als Nächstes“ im Turnier: das nächste spielbare Match (ohne die gerade laufenden).
String? nextMatchLabel(Tournament t, {String? exceptMatch, Iterable<String?> except = const []}) {
  final skip = {exceptMatch, ...except}..remove(null);
  for (final m in t.playable) {
    if (skip.contains(m.id)) continue;
    final (a, b) = t.participants(m);
    if (a == null || b == null) continue;
    return '${t.players[a].name} – ${t.players[b].name}';
  }
  return null;
}

/// Leiste „Als Nächstes“ oben auf der Anzeige.
Widget nextUpBar(String text, double k) => Container(
  margin: EdgeInsets.only(top: 6 * k),
  padding: EdgeInsets.symmetric(horizontal: 16 * k, vertical: 6 * k),
  decoration: BoxDecoration(
    color: C.accent.withValues(alpha: 0.14),
    borderRadius: BorderRadius.circular(99),
    border: Border.all(color: C.accent.withValues(alpha: 0.5)),
  ),
  child: FittedBox(
    fit: BoxFit.scaleDown,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.skip_next_rounded, color: C.accent, size: 26 * k),
        SizedBox(width: 8 * k),
        Text(
          'ALS NÄCHSTES',
          style: TextStyle(fontSize: 16 * k, fontWeight: FontWeight.w800, letterSpacing: 2, color: C.accent),
        ),
        SizedBox(width: 14 * k),
        Text(
          text,
          style: TextStyle(fontSize: 24 * k, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  ),
);

/// Leg- bzw. Match-Statistik groß auf der Anzeige.
class _BoardStats extends StatelessWidget {
  const _BoardStats({required this.engine, required this.report, this.leg, this.board});
  final GameEngine engine;
  final MatchReport report;

  /// Bei mehreren Spielen: Name der Scheibe.
  final String? board;

  /// null = Match-Statistik
  final LegReport? leg;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final k = (min(box.maxWidth, box.maxHeight) / 560).clamp(0.8, 1.8);
      final l = leg;
      final String eyebrow;
      final String title;
      final Color color;
      if (l != null) {
        final w = l.winner!;
        eyebrow = 'LEG ${l.number} BEENDET';
        title = '${engine.players[w].name} checkt ${l.players[w].finish} mit ${l.players[w].darts} Darts';
        color = Color(engine.players[w].color);
      } else {
        final w = engine.results().first.playerIndex;
        eyebrow = 'MATCHSTATISTIK';
        final score = engine.n == 2 && engine.legsToWin != null
            ? '   ${engine.legsOf(w)} : ${engine.legsOf(1 - w)}'
            : '';
        title = '${engine.players[w].name} gewinnt$score';
        color = C.gold;
      }
      return Padding(
        padding: EdgeInsets.fromLTRB(24 * k, 16 * k, 24 * k, 16 * k),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              board == null ? eyebrow : '${board!.toUpperCase()} · $eyebrow',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18 * k, fontWeight: FontWeight.w800, letterSpacing: 3, color: color),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                title,
                style: TextStyle(fontSize: 38 * k, fontWeight: FontWeight.w800),
              ),
            ),
            SizedBox(height: 14 * k),
            Expanded(
              // Immer komplett sichtbar: bei vielen Zeilen/Spielern wird verkleinert statt gescrollt
              // (an der Anzeige tippt niemand).
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: box.maxWidth - 48 * k,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      StatsTable(
                        players: engine.players,
                        rows: l != null ? legRows(l) : matchRows(report),
                        k: k * (engine.n > 4 ? 0.8 : 1.05),
                      ),
                      if (l == null && report.legs.length > 1) ...[
                        SizedBox(height: 16 * k),
                        LegList(report: report, k: k),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Text(
              l != null ? 'Weiter geht es mit dem nächsten Dart' : 'Neues Spiel am Handy starten',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16 * k, color: C.muted),
            ),
          ],
        ),
      );
    },
  );
}

class _MatchBoard extends StatelessWidget {
  const _MatchBoard({required this.engine, this.next, this.board});
  final GameEngine engine;

  /// Bei mehreren Spielen: kleiner Hinweis, welche Scheibe gezeigt wird.
  final String? board;

  /// Turnier: nächste Paarung.
  final String? next;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // Schriftgrößen wachsen mit dem Bildschirm (Tablet an der Wand: gut aus der Ferne lesbar).
      final k = (min(box.maxWidth, box.maxHeight) / 680).clamp(0.7, 1.7);
      return _build(context, k);
    },
  );

  Widget _build(BuildContext context, double k) {
    final e = engine;
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final so = e is X01Game && e.singleOutLeg;
    final hint = e.finished ? null : e.hint;
    final winner = e.finished && e.n > 1 ? e.results().first.playerIndex : null;
    // Ab 5 Spielern kompakte Kacheln in zwei Reihen, bei 3–4 etwas kleiner.
    final many = e.n > 4;
    final pk = many ? k * 0.58 : (e.n > 2 ? k * 0.8 : k);
    final panels = [for (var i = 0; i < e.n; i++) _panel(i, winner, pk)];
    final half = (e.n + 1) ~/ 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (board != null) ...[_pill(board!.toUpperCase(), C.muted, k: k), SizedBox(width: 12 * k)],
              Flexible(
                child: Text(
                  so ? '${e.start} · DOUBLE OUT' : e.title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 24 * k, fontWeight: FontWeight.w800, letterSpacing: 3, color: C.accent),
                ),
              ),
              if (so) ...[SizedBox(width: 12 * k), _pill('SINGLE OUT IN DIESEM LEG', C.gold, k: k * 1.2)],
            ],
          ),
          Text(
            e.subtitle,
            style: TextStyle(fontSize: 17 * k, color: C.muted),
          ),
          if (next != null) nextUpBar(next!, k),
          SizedBox(height: 10 * k),
          if (winner != null) ...[_winnerBanner(winner, k), const SizedBox(height: 8)],
          Expanded(
            child: many
                ? Column(
                    children: [
                      for (final row in [panels.sublist(0, half), panels.sublist(half)])
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final p in row) Expanded(child: p),
                              // gleich breite Kacheln, auch wenn die untere Reihe kürzer ist
                              for (var j = row.length; j < half; j++) const Expanded(child: SizedBox()),
                            ],
                          ),
                        ),
                    ],
                  )
                : landscape || e.n <= 1
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [for (final p in panels) Expanded(child: p)],
                  )
                : Column(children: [for (final p in panels) Expanded(child: p)]),
          ),
          if (hint != null && Store.checkoutHint) ...[
            SizedBox(height: 8 * k),
            _finishBar(hint, Color(e.players[e.cur].color), k),
          ],
        ],
      ),
    );
  }

  /// Große Finish-Leiste: pro Dart ein Kästchen, aus der Ferne lesbar.
  Widget _finishBar(Hint hint, Color col, double k) {
    final parts = hint.strong ? hint.text.split(' · ') : const <String>[];
    final e = engine;
    final rest = e is X01Game ? e.scores[e.cur] : null;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 10 * k, horizontal: 16 * k),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            col.withValues(alpha: hint.strong ? 0.28 : 0.10),
            col.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(22 * k),
        border: Border.all(
          color: col.withValues(alpha: hint.strong ? 0.8 : 0.3),
          width: hint.strong ? 2.5 : 1,
        ),
        boxShadow: hint.strong ? [BoxShadow(color: col.withValues(alpha: 0.25), blurRadius: 24)] : null,
      ),
      child: parts.isEmpty
          ? FittedBox(
              fit: BoxFit.scaleDown,
              child: Text.rich(
                TextSpan(
                  children: [
                    if (hint.label != null)
                      TextSpan(
                        text: '${hint.label!.toUpperCase()}   ',
                        style: TextStyle(color: col, letterSpacing: 3 * k, fontSize: 32 * k),
                      ),
                    TextSpan(text: hint.text),
                  ],
                ),
                style: TextStyle(fontSize: 44 * k, fontFamily: numFont, fontWeight: FontWeight.w800, color: C.text),
              ),
            )
          : Row(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FINISH',
                      style: TextStyle(fontSize: 20 * k, fontWeight: FontWeight.w800, letterSpacing: 3 * k, color: col),
                    ),
                    if (rest != null)
                      Text(
                        '$rest',
                        style: TextStyle(
                          fontFamily: numFont,
                          fontSize: 40 * k,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          color: C.text,
                        ),
                      ),
                  ],
                ),
                SizedBox(width: 18 * k),
                for (final p in parts) ...[
                  Expanded(
                    child: Container(
                      height: 92 * k,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: C.bg.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(18 * k),
                        border: Border.all(
                          color: p.startsWith('D') || p == 'Bull' ? C.dbl : col.withValues(alpha: 0.7),
                          width: 2.5,
                        ),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8 * k),
                          child: Text(
                            p,
                            style: TextStyle(
                              fontFamily: numFont,
                              fontSize: 62 * k,
                              fontWeight: FontWeight.w800,
                              color: p.startsWith('D') || p == 'Bull' ? C.dbl : C.text,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 10 * k),
                ],
                for (var i = parts.length; i < 3; i++) ...[const Expanded(child: SizedBox()), SizedBox(width: 10 * k)],
              ],
            ),
    );
  }

  Widget _winnerBanner(int w, double k) {
    final e = engine;
    final score = e.setsToWin != null
        ? [for (var i = 0; i < e.n; i++) e.setsOf(i)].join(' : ')
        : e.legsToWin != null
        ? [for (var i = 0; i < e.n; i++) e.legsOf(i)].join(' : ')
        : null;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.85, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.elasticOut,
      builder: (_, k, child) => Transform.scale(scale: k, child: child),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 14 * k, horizontal: 20 * k),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [C.gold.withValues(alpha: 0.30), C.gold.withValues(alpha: 0.08)]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: C.gold, width: 2),
          boxShadow: [BoxShadow(color: C.gold.withValues(alpha: 0.35), blurRadius: 28)],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emoji_events_rounded, color: C.gold, size: 52 * k),
              SizedBox(width: 16 * k),
              Text(
                '${e.players[w].name} gewinnt${score != null ? '   $score' : ''}',
                style: TextStyle(fontSize: 46 * k, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Die drei Pfeile der laufenden (aktiver Spieler) bzw. letzten Aufnahme.
  Widget _darts(int i, bool active, Color col, double k) {
    final e = engine;
    final list = active ? e.turn : e.lastTurns[i];
    final sum = list.fold<int>(0, (a, d) => a + d.value);
    return Row(
      children: [
        for (var j = 0; j < 3; j++) ...[
          Expanded(child: _dartChip(j < list.length ? list[j] : null, active, col, k)),
          SizedBox(width: 10 * k),
        ],
        SizedBox(
          width: 120 * k,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              list.isEmpty ? '' : '= $sum',
              style: TextStyle(
                fontFamily: numFont,
                fontSize: 48 * k,
                fontWeight: FontWeight.w800,
                color: active ? col : C.muted2,
                fontFeatures: tabular,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dartChip(Dart? d, bool active, Color col, double k) {
    final strong = d != null && (d.isTriple || d.isDouble || d.isBull);
    final c = d == null
        ? C.border
        : d.isMiss
        ? C.danger
        : d.isTriple
        ? C.gold
        : d.isDouble || d.isBull
        ? C.dbl
        : col;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      height: 84 * k,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: d == null ? C.surface.withValues(alpha: 0.5) : c.withValues(alpha: active ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(16 * k),
        border: Border.all(
          color: d == null ? C.border : c.withValues(alpha: strong ? 0.9 : 0.5),
          width: strong ? 2.5 : 1,
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 6 * k),
          child: Text(
            d?.label ?? '–',
            style: TextStyle(
              fontFamily: numFont,
              fontSize: 46 * k,
              fontWeight: FontWeight.w800,
              color: d == null ? C.muted : (active ? C.text : C.muted2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(int i, int? winner, double k) {
    final e = engine;
    final active = i == e.cur && !e.finished;
    final won = winner == i;
    // Weiterspielen um Plätze: wer schon einen Platz hat, wird abgedunkelt und markiert.
    final place = e is X01Game ? e.placeOf(i) : null;
    final lost = (winner != null && !won) || (place != null && !e.finished);
    final lit = active || won;
    final col = Color(e.players[i].color);
    final edge = won ? C.gold : col;
    final legs = e.legsToWin;
    final sets = e.setsToWin;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 400),
      opacity: lost ? 0.5 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: EdgeInsets.all(6 * k),
        padding: EdgeInsets.fromLTRB(20 * k, 12 * k, 20 * k, 14 * k),
        decoration: BoxDecoration(
          gradient: C.cardGradient(edge, lit ? 0.24 : 0.05),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: lit ? edge : C.border, width: lit ? 3 : 1),
          boxShadow: lit ? [BoxShadow(color: edge.withValues(alpha: 0.38), blurRadius: 34)] : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 20 * k,
                  height: 20 * k,
                  decoration: BoxDecoration(
                    color: col,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: col.withValues(alpha: 0.6), blurRadius: 10)],
                  ),
                ),
                SizedBox(width: 12 * k),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          e.players[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 42 * k,
                            fontWeight: FontWeight.w800,
                            color: lit ? C.text : C.muted2,
                          ),
                        ),
                      ),
                      SizedBox(width: 12 * k),
                      if (active) _pill('AM WURF', col, k: k),
                      if (won) _pill('SIEGER', C.gold, icon: Icons.emoji_events_rounded, k: k),
                      if (!won && place != null)
                        _pill(
                          place == 1 ? 'SIEGER' : 'PLATZ $place',
                          C.gold,
                          icon: place == 1 ? Icons.emoji_events_rounded : null,
                          k: k,
                        ),
                    ],
                  ),
                ),
                if (sets != null) _count('Sets', e.setsOf(i), col, k),
                if (legs != null) _count('Legs', e.legsOf(i), col, k),
              ],
            ),
            Expanded(
              child: FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                child: Text(
                  e.mainValue(i),
                  style: TextStyle(
                    fontFamily: numFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 200,
                    height: 1,
                    color: won ? C.gold : (active ? C.text : C.muted2),
                    fontFeatures: tabular,
                    shadows: lit ? [Shadow(color: edge.withValues(alpha: 0.45), blurRadius: 30)] : null,
                  ),
                ),
              ),
            ),
            _darts(i, active, col, k),
            SizedBox(height: 10 * k),
            Row(
              children: [
                Text(
                  active ? 'Aufnahme läuft' : 'Letzte Aufnahme',
                  style: TextStyle(fontSize: 22 * k, color: C.muted, fontWeight: FontWeight.w600),
                ),
                SizedBox(width: 12 * k),
                if (e.subLine(i) != null)
                  Expanded(
                    child: Text(
                      e.subLine(i)!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 26 * k,
                        color: C.text.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color c, {IconData? icon, double k = 1}) => Container(
    padding: EdgeInsets.symmetric(horizontal: 12 * k, vertical: 5 * k),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: c.withValues(alpha: 0.7)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 20 * k, color: c), SizedBox(width: 5 * k)],
        Text(
          text,
          style: TextStyle(fontSize: 17 * k, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: c),
        ),
      ],
    ),
  );

  Widget _count(String label, int v, Color col, double k) => Padding(
    padding: EdgeInsets.only(left: 18 * k),
    child: Column(
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(fontSize: 15 * k, color: C.muted, fontWeight: FontWeight.w800, letterSpacing: 1),
        ),
        Text(
          '$v',
          style: TextStyle(
            fontFamily: numFont,
            fontSize: 50 * k,
            fontWeight: FontWeight.w800,
            color: col,
            height: 1.05,
          ),
        ),
      ],
    ),
  );
}


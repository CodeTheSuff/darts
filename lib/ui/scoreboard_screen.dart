import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/match_controller.dart';
import '../data/storage.dart';
import '../games/engine.dart';
import '../games/x01.dart';
import '../games/tournament.dart';
import '../models/dart.dart';
import '../net/link.dart';
import 'celebration.dart';
import 'link_coordinator.dart';
import 'theme.dart';
import 'tournament_screens.dart';

/// Reine Anzeige für ein gekoppeltes Gerät (z. B. Tablet an der Wand neben dem Board):
/// riesige Restpunkte, die drei Pfeile der Aufnahme, Jubel-Animationen und
/// ein hervorgehobener Sieger. Im Turnier Baum bzw. Tabelle.
class ScoreboardScreen extends StatefulWidget {
  const ScoreboardScreen({super.key});

  @override
  State<ScoreboardScreen> createState() => _ScoreboardScreenState();
}

/// Eine anstehende Jubel-Animation.
class _Show {
  _Show(this.kind, this.player, this.darts, this.value, this.label);
  final CelebrationKind kind;
  final int player;
  final List<Dart> darts;
  final int? value;
  final String? label;
}

class _ScoreboardScreenState extends State<ScoreboardScreen> {
  MatchController? _ctl;
  StreamSubscription<ThrowEvent>? _sub;
  final _queue = <_Show>[];
  _Show? _show;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable().catchError((_) {});
    LinkCoordinator.viewerState.addListener(_onState);
    _onState(rebuild: false);
  }

  @override
  void dispose() {
    LinkCoordinator.viewerState.removeListener(_onState);
    _sub?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  /// Neuer Stand vom Host: laufendes Match fortschreiben (dabei entstehen
  /// Wurf-Ereignisse für die Animationen) oder neu aufbauen.
  void _onState({bool rebuild = true}) {
    final mj = LinkCoordinator.viewerState.value?['match'];
    if (mj is! Map) {
      if (_ctl != null) _setCtl(null);
    } else {
      final j = Map<String, dynamic>.from(mj);
      final cur = _ctl;
      if (cur != null && cur.matchId == j['mid']) {
        try {
          cur.applyRemote([
            for (final d in j['darts'] as List) Dart.fromJson(Map<String, dynamic>.from(d as Map)),
          ]);
        } catch (_) {}
      } else {
        _setCtl(MatchController.fromJson(j));
      }
    }
    if (rebuild && mounted) setState(() {});
  }

  void _setCtl(MatchController? c) {
    _sub?.cancel();
    _sub = null;
    _queue.clear();
    _show = null;
    _ctl = c;
    if (c != null) _sub = c.externalEvents.listen(_onEvent);
  }

  void _onEvent(ThrowEvent ev) {
    final e = _ctl?.engine;
    if (e == null || !ev.turnEnded || !Store.celebrations) return;
    if (ev.celebration != null) {
      final kind = kindOf(ev.celebration!);
      if (!(kind == CelebrationKind.legWon && ev.gameOver)) {
        var label = ev.celebrationLabel;
        if (kind == CelebrationKind.legWon && e.legsToWin == null) label = 'GESCHAFFT!';
        _queue.add(_Show(kind, ev.playerIndex, ev.turnDarts, ev.celebrationValue, label));
      }
    }
    if (ev.gameOver) {
      final w = e.results().first.playerIndex;
      _queue.add(_Show(CelebrationKind.match, w, w == ev.playerIndex ? ev.turnDarts : const [], null,
          e.n == 1 ? 'GESCHAFFT' : (e.legsToWin != null ? 'MATCH GEWONNEN' : 'SIEG')));
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
    await Link.I.stop();
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
    final c = _ctl;
    final t = _tournament(tj);
    final next = t == null ? null : nextMatchLabel(t, exceptMatch: c?.tournamentMatchId);
    Widget body;
    if (c != null) {
      body = _MatchBoard(engine: c.engine, next: next);
    } else if (t != null) {
      body = _TournamentBoard(t: t, next: next);
    } else {
      body = _waiting();
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
                    IconButton(
                      tooltip: 'Anzeige beenden',
                      icon: Icon(Icons.close_rounded, color: C.muted),
                      onPressed: _leave,
                    ),
                  ],
                ),
              ),
              if (show != null && c != null)
                Positioned.fill(
                  child: CelebrationOverlay(
                    key: ObjectKey(show),
                    kind: show.kind,
                    name: c.engine.players[show.player].name,
                    color: Color(c.engine.players[show.player].color),
                    darts: show.darts,
                    value: show.value,
                    label: show.label,
                    onDone: _done,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _waiting() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tv_rounded, size: 64, color: C.accent),
            const SizedBox(height: 14),
            const Text('Scoreboard', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            AnimatedBuilder(
              animation: Link.I,
              builder: (_, _) => Text(
                Link.I.isConnected
                    ? 'Verbunden mit ${Link.I.hostName ?? 'Host'} – warte auf ein Spiel …'
                    : Link.I.status,
                textAlign: TextAlign.center,
                style: TextStyle(color: C.muted, fontSize: 16),
              ),
            ),
          ],
        ),
      );
}

/// „Als Nächstes“ im Turnier: das nächste spielbare Match (ohne das gerade laufende).
String? nextMatchLabel(Tournament t, {String? exceptMatch}) {
  for (final m in t.playable) {
    if (m.id == exceptMatch) continue;
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
            Text('ALS NÄCHSTES',
                style: TextStyle(fontSize: 16 * k, fontWeight: FontWeight.w800, letterSpacing: 2, color: C.accent)),
            SizedBox(width: 14 * k),
            Text(text, style: TextStyle(fontSize: 24 * k, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );

class _MatchBoard extends StatelessWidget {
  const _MatchBoard({required this.engine, this.next});
  final GameEngine engine;

  /// Turnier: nächste Paarung.
  final String? next;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        // Schriftgrößen wachsen mit dem Bildschirm (Tablet an der Wand: gut aus der Ferne lesbar).
        final k = (min(box.maxWidth, box.maxHeight) / 680).clamp(0.7, 1.7);
        return _build(context, k);
      });

  Widget _build(BuildContext context, double k) {
    final e = engine;
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final so = e is X01Game && e.singleOutLeg;
    final hint = e.finished ? null : e.hint;
    final winner = e.finished && e.n > 1 ? e.results().first.playerIndex : null;
    final panels = [for (var i = 0; i < e.n; i++) _panel(i, winner, k)];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                    so ? '${e.start} · DOUBLE OUT' : e.title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 24 * k, fontWeight: FontWeight.w800, letterSpacing: 3, color: C.accent)),
              ),
              if (so) ...[SizedBox(width: 12 * k), _pill('SINGLE OUT IN DIESEM LEG', C.gold, k: k * 1.2)],
            ],
          ),
          Text(e.subtitle, style: TextStyle(fontSize: 17 * k, color: C.muted)),
          if (next != null) nextUpBar(next!, k),
          SizedBox(height: 10 * k),
          if (winner != null) ...[
            _winnerBanner(winner, k),
            const SizedBox(height: 8),
          ],
          Expanded(
            child: landscape || e.n <= 1
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
        gradient: LinearGradient(colors: [col.withValues(alpha: hint.strong ? 0.28 : 0.10), col.withValues(alpha: 0.06)]),
        borderRadius: BorderRadius.circular(22 * k),
        border: Border.all(color: col.withValues(alpha: hint.strong ? 0.8 : 0.3), width: hint.strong ? 2.5 : 1),
        boxShadow: hint.strong ? [BoxShadow(color: col.withValues(alpha: 0.25), blurRadius: 24)] : null,
      ),
      child: parts.isEmpty
          ? FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(hint.text,
                  style: TextStyle(fontSize: 40 * k, fontFamily: numFont, fontWeight: FontWeight.w800, color: C.muted2)),
            )
          : Row(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('FINISH',
                        style: TextStyle(
                            fontSize: 20 * k, fontWeight: FontWeight.w800, letterSpacing: 3 * k, color: col)),
                    if (rest != null)
                      Text('$rest',
                          style: TextStyle(
                              fontFamily: numFont, fontSize: 40 * k, fontWeight: FontWeight.w800, height: 1, color: C.text)),
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
                            color: p.startsWith('D') || p == 'Bull' ? C.dbl : col.withValues(alpha: 0.7), width: 2.5),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8 * k),
                          child: Text(p,
                              style: TextStyle(
                                fontFamily: numFont,
                                fontSize: 62 * k,
                                fontWeight: FontWeight.w800,
                                color: p.startsWith('D') || p == 'Bull' ? C.dbl : C.text,
                              )),
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
              Text('${e.players[w].name} gewinnt${score != null ? '   $score' : ''}',
                  style: TextStyle(fontSize: 46 * k, fontWeight: FontWeight.w800)),
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
            child: Text(list.isEmpty ? '' : '= $sum',
                style: TextStyle(
                  fontFamily: numFont,
                  fontSize: 48 * k,
                  fontWeight: FontWeight.w800,
                  color: active ? col : C.muted2,
                  fontFeatures: tabular,
                )),
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
        border: Border.all(color: d == null ? C.border : c.withValues(alpha: strong ? 0.9 : 0.5), width: strong ? 2.5 : 1),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 6 * k),
          child: Text(d?.label ?? '–',
              style: TextStyle(
                fontFamily: numFont,
                fontSize: 46 * k,
                fontWeight: FontWeight.w800,
                color: d == null ? C.muted : (active ? C.text : C.muted2),
              )),
        ),
      ),
    );
  }

  Widget _panel(int i, int? winner, double k) {
    final e = engine;
    final active = i == e.cur && !e.finished;
    final won = winner == i;
    final lost = winner != null && !won;
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
                        child: Text(e.players[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 42 * k, fontWeight: FontWeight.w800, color: lit ? C.text : C.muted2)),
                      ),
                      SizedBox(width: 12 * k),
                      if (active) _pill('AM WURF', col, k: k),
                      if (won) _pill('SIEGER', C.gold, icon: Icons.emoji_events_rounded, k: k),
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
                child: Text(e.mainValue(i),
                    style: TextStyle(
                      fontFamily: numFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 200,
                      height: 1,
                      color: won ? C.gold : (active ? C.text : C.muted2),
                      fontFeatures: tabular,
                      shadows: lit ? [Shadow(color: edge.withValues(alpha: 0.45), blurRadius: 30)] : null,
                    )),
              ),
            ),
            _darts(i, active, col, k),
            SizedBox(height: 10 * k),
            Row(
              children: [
                Text(active ? 'Aufnahme läuft' : 'Letzte Aufnahme',
                    style: TextStyle(fontSize: 22 * k, color: C.muted, fontWeight: FontWeight.w600)),
                SizedBox(width: 12 * k),
                if (e.subLine(i) != null)
                  Expanded(
                    child: Text(e.subLine(i)!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 26 * k, color: C.text.withValues(alpha: 0.8), fontWeight: FontWeight.w600)),
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
            Text(text, style: TextStyle(fontSize: 17 * k, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: c)),
          ],
        ),
      );

  Widget _count(String label, int v, Color col, double k) => Padding(
        padding: EdgeInsets.only(left: 18 * k),
        child: Column(
          children: [
            Text(label.toUpperCase(),
                style: TextStyle(fontSize: 15 * k, color: C.muted, fontWeight: FontWeight.w800, letterSpacing: 1)),
            Text('$v',
                style: TextStyle(
                    fontFamily: numFont, fontSize: 50 * k, fontWeight: FontWeight.w800, color: col, height: 1.05)),
          ],
        ),
      );
}

class _TournamentBoard extends StatelessWidget {
  const _TournamentBoard({required this.t, this.next});
  final Tournament t;
  final String? next;

  @override
  Widget build(BuildContext context) {
    final table = t.system == TSystem.league;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          Text('${t.system.label} · ${t.playedCount}/${t.realCount} Matches',
              textAlign: TextAlign.center, style: TextStyle(color: C.muted, fontSize: 15)),
          if (next != null) Center(child: nextUpBar(next!, 1.2)),
          const SizedBox(height: 8),
          Expanded(
            child: table
                ? ListView(
                    children: [
                      for (final (i, s) in t.standings().indexed)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(14)),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 40,
                                child: Text('${i + 1}.',
                                    style: TextStyle(
                                        fontSize: 22, fontWeight: FontWeight.w800, color: medalColor(i + 1))),
                              ),
                              Expanded(
                                child: Text(t.players[s.player].name,
                                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                              ),
                              Text('${s.wins} S · ${s.legsFor}:${s.legsAgainst}',
                                  style: TextStyle(fontSize: 18, color: C.muted2, fontFeatures: tabular)),
                            ],
                          ),
                        ),
                    ],
                  )
                : BracketView(t: t, onTap: (_) {}),
          ),
        ],
      ),
    );
  }
}

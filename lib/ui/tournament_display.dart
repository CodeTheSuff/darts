import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../games/tournament.dart';
import 'theme.dart';
import 'tournament_screens.dart' show BracketView, medalColor;

/// Turnier auf der Anzeige (Tablet an der Wand): große Schrift, drei Ansichten, die sich
/// alle 15 Sekunden abwechseln – Stand (Baum/Tabelle), Als Nächstes, Letzte Ergebnisse.
class TournamentDisplay extends StatefulWidget {
  const TournamentDisplay({super.key, required this.t, this.exceptMatch, this.interval = const Duration(seconds: 15)});
  final Tournament t;

  /// Gerade laufendes Match (nicht als „als Nächstes“ zeigen).
  final String? exceptMatch;
  final Duration interval;

  @override
  State<TournamentDisplay> createState() => _TournamentDisplayState();
}

enum _Page { standing, next, results }

class _TournamentDisplayState extends State<TournamentDisplay> {
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() => _index++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Tournament get t => widget.t;

  List<(int, int, TMatch)> get _upcoming => [
    for (final m in t.playable)
      if (m.id != widget.exceptMatch)
        if (t.participants(m) case (final int a, final int b) when a >= 0 && b >= 0) (a, b, m),
  ];

  List<TMatch> get _recent {
    final ms = [
      for (final m in t.matches)
        if (m.played)
          if (t.participants(m) case (final int a, final int b) when a >= 0 && b >= 0) m,
    ]..sort((x, y) => y.at.compareTo(x.at));
    return ms;
  }

  List<_Page> get _pages => [
    _Page.standing,
    if (_upcoming.isNotEmpty) _Page.next,
    if (_recent.isNotEmpty) _Page.results,
  ];

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    final page = pages[_index % pages.length];
    return LayoutBuilder(
      builder: (context, box) {
        // Skalierung nach Bildschirmhöhe: Handy ≈ 1, Tablet quer ≈ 1,4
        final k = (box.maxHeight / 560).clamp(0.9, 1.8);
        return Padding(
          padding: EdgeInsets.fromLTRB(20 * k, 10 * k, 20 * k, 12 * k),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(k, pages, page),
              SizedBox(height: 12 * k),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  child: SizedBox.expand(
                    key: ValueKey(page),
                    child: switch (page) {
                      _Page.standing => _standing(k),
                      _Page.next => _next(k),
                      _Page.results => _results(k),
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _header(double k, List<_Page> pages, _Page page) {
    final done = t.playedCount;
    final total = max(1, t.realCount);
    String title(_Page p) => switch (p) {
      _Page.standing =>
        t.champion != null
            ? 'Endstand'
            : t.system == TSystem.league ||
                  t.system == TSystem.groups && t.matches.any((m) => m.bracket == 'G' && !m.played)
            ? 'Tabelle'
            : 'Turnierbaum',
      _Page.next => 'Als Nächstes',
      _Page.results => 'Letzte Ergebnisse',
    };
    final chips = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final p in pages)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: EdgeInsets.only(left: 6 * k),
            padding: EdgeInsets.symmetric(horizontal: 12 * k, vertical: 6 * k),
            decoration: BoxDecoration(
              color: p == page ? C.accent.withValues(alpha: 0.18) : Colors.transparent,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: p == page ? C.accent : C.line),
            ),
            child: Text(
              title(p),
              style: TextStyle(fontSize: 13 * k, fontWeight: FontWeight.w800, color: p == page ? C.accent : C.muted),
            ),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 760;
        final head = Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Icon(Icons.emoji_events_rounded, color: C.gold, size: 40 * k),
            SizedBox(width: 12 * k),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 30 * k, fontWeight: FontWeight.w800, height: 1.1),
                  ),
                  SizedBox(height: 4 * k),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${t.system.label} · $done/$total Matches',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: C.muted, fontSize: 15 * k, fontWeight: FontWeight.w600),
                        ),
                      ),
                      SizedBox(width: 12 * k),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: done / total,
                            minHeight: 6 * k,
                            backgroundColor: C.surface2,
                            color: C.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!narrow) ...[SizedBox(width: 20 * k), chips],
          ],
        );
        if (!narrow) return head;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            head,
            SizedBox(height: 8 * k),
            FittedBox(fit: BoxFit.scaleDown, child: chips),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------- Stand

  Widget _standing(double k) {
    if (t.champion != null) return _podium(k);
    if (t.system == TSystem.league) return _table(k, t.standings(), title: null);
    if (t.system == TSystem.groups && t.matches.any((m) => m.bracket == 'G' && !m.played)) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var g = 0; g < t.groupCount; g++) ...[
            if (g > 0) SizedBox(width: 14 * k),
            Expanded(
              child: _table(k, t.standings(group: g), title: 'Gruppe ${String.fromCharCode(65 + g)}', compact: true),
            ),
          ],
        ],
      );
    }
    return Container(
      padding: EdgeInsets.all(8 * k),
      decoration: BoxDecoration(color: C.surface.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(20)),
      child: BracketView(t: t, onTap: (_) {}, fill: true),
    );
  }

  Widget _table(double k, List<TStanding> rows, {String? title, bool compact = false}) {
    final f = compact ? 0.85 : 1.0;
    final fs = 22 * k * f;
    TextStyle head = TextStyle(color: C.muted, fontSize: 13 * k * f, fontWeight: FontWeight.w800, letterSpacing: 1);
    TextStyle num = TextStyle(fontSize: fs * 0.85, fontWeight: FontWeight.w700, fontFeatures: tabular);
    Widget cell(String s, double w, TextStyle st) => SizedBox(
      width: w,
      child: Text(s, textAlign: TextAlign.center, style: st),
    );
    final w = 64 * k * f;
    return Container(
      padding: EdgeInsets.fromLTRB(14 * k, 10 * k, 14 * k, 10 * k),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(20)),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: compact ? 520 * k * f : 900 * k,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null)
                Padding(
                  padding: EdgeInsets.only(bottom: 6 * k),
                  child: Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      color: C.accent,
                      fontSize: 16 * k * f,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
              Row(
                children: [
                  SizedBox(width: 50 * k * f),
                  Expanded(child: Text('SPIELER', style: head)),
                  cell('SP', w, head),
                  cell('S', w, head),
                  cell('N', w, head),
                  cell('LEGS', w * 1.4, head),
                  cell('+/-', w, head),
                  if (!compact) cell('Ø', w * 1.3, head),
                ],
              ),
              SizedBox(height: 6 * k),
              for (final (i, s) in rows.indexed)
                Container(
                  margin: EdgeInsets.only(bottom: 5 * k),
                  padding: EdgeInsets.symmetric(vertical: 8 * k),
                  decoration: BoxDecoration(
                    color: i == 0 && s.played > 0 ? C.gold.withValues(alpha: 0.10) : C.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: i == 0 && s.played > 0 ? Border.all(color: C.gold.withValues(alpha: 0.5)) : null,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 50 * k * f,
                        child: Text(
                          '${i + 1}.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: fs, fontWeight: FontWeight.w800, color: medalColor(i + 1)),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          t.players[s.player].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: fs, fontWeight: FontWeight.w800),
                        ),
                      ),
                      cell('${s.played}', w, num),
                      cell('${s.wins}', w, num.copyWith(color: C.dbl)),
                      cell('${s.losses}', w, num.copyWith(color: C.muted)),
                      cell('${s.legsFor}:${s.legsAgainst}', w * 1.4, num),
                      cell('${s.legDiff > 0 ? '+' : ''}${s.legDiff}', w, num),
                      if (!compact)
                        cell(s.darts == 0 ? '–' : s.average.toStringAsFixed(1).replaceAll('.', ','), w * 1.3, num),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _podium(double k) {
    final pl = t.placements().where((p) => p.rank <= 3).toList()..sort((a, b) => a.rank.compareTo(b.rank));
    Widget step(TPlacement p, double h) => Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (p.rank == 1) Icon(Icons.emoji_events_rounded, color: C.gold, size: 70 * k),
        Text(
          t.players[p.player].name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: (p.rank == 1 ? 40 : 28) * k, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 8 * k),
        Container(
          height: h * k,
          width: 200 * k,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [medalColor(p.rank), medalColor(p.rank).withValues(alpha: 0.35)],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Text(
            '${p.rank}',
            style: TextStyle(fontSize: 54 * k, fontWeight: FontWeight.w900, color: C.ink, fontFamily: numFont),
          ),
        ),
      ],
    );
    final first = pl.where((p) => p.rank == 1).firstOrNull;
    final second = pl.where((p) => p.rank == 2).firstOrNull;
    final thirds = pl.where((p) => p.rank == 3).toList();
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (second != null) step(second, 140),
          SizedBox(width: 16 * k),
          if (first != null) step(first, 200),
          SizedBox(width: 16 * k),
          for (final p in thirds) ...[step(p, 100), SizedBox(width: 16 * k)],
        ],
      ),
    );
  }

  /// Runde/Phase – bei der Liga ohne Aussage, daher leer.
  String _stage(TMatch m) => t.system == TSystem.league ? '' : m.stage.label;

  // ---------------------------------------------------------------- Als Nächstes

  Widget _next(double k) {
    final up = _upcoming;
    final (a, b, m) = up.first;
    final f = t.formatOf(m.stage);
    final rest = up.skip(1).take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Container(
            padding: EdgeInsets.all(18 * k),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [C.accent.withValues(alpha: 0.22), C.surface]),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: C.accent.withValues(alpha: 0.6), width: 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  [if (_stage(m).isNotEmpty) _stage(m).toUpperCase(), f.label].join(' · '),
                  style: TextStyle(color: C.accent, fontSize: 16 * k, fontWeight: FontWeight.w800, letterSpacing: 1.6),
                ),
                SizedBox(height: 10 * k),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    children: [
                      Text(
                        t.players[a].name,
                        style: TextStyle(fontSize: 64 * k, fontWeight: FontWeight.w900),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 28 * k),
                        child: Text(
                          'vs',
                          style: TextStyle(fontSize: 34 * k, color: C.muted, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        t.players[b].name,
                        style: TextStyle(fontSize: 64 * k, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (rest.isNotEmpty) ...[
          SizedBox(height: 12 * k),
          Text(
            'DANACH',
            style: TextStyle(color: C.muted, fontSize: 14 * k, fontWeight: FontWeight.w800, letterSpacing: 1.4),
          ),
          SizedBox(height: 6 * k),
          Expanded(
            flex: 2,
            child: Column(
              children: [
                for (final (x, y, mm) in rest)
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.only(bottom: 6 * k),
                      padding: EdgeInsets.symmetric(horizontal: 18 * k),
                      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(14)),
                      child: Row(
                        children: [
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${t.players[x].name}  –  ${t.players[y].name}',
                                style: TextStyle(fontSize: 24 * k, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          Text(
                            _stage(mm),
                            style: TextStyle(color: C.muted, fontSize: 15 * k),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------- Ergebnisse

  Widget _results(double k) {
    final ms = _recent.take(6).toList();
    final wide = MediaQuery.sizeOf(context).width >= 760;
    String avg(TMatch m, int side) =>
        m.darts[side] == 0 ? '–' : (m.points[side] / m.darts[side] * 3).toStringAsFixed(1).replaceAll('.', ',');
    return Column(
      children: [
        for (final m in ms)
          Expanded(
            child: Builder(
              builder: (context) {
                final (a, b) = t.participants(m);
                final f = t.formatOf(m.stage);
                final sa = f.sets ? m.sets[0] : m.legs[0];
                final sb = f.sets ? m.sets[1] : m.legs[1];
                Widget name(int p, int side, TextAlign al) {
                  final won = m.winnerSide == side;
                  return Expanded(
                    child: Column(
                      crossAxisAlignment: al == TextAlign.right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          t.players[p].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 26 * k,
                            height: 1.1,
                            fontWeight: won ? FontWeight.w900 : FontWeight.w600,
                            color: won ? C.text : C.muted2,
                          ),
                        ),
                        Text(
                          'Ø ${avg(m, side)}',
                          style: TextStyle(color: C.muted, fontSize: 14 * k),
                        ),
                      ],
                    ),
                  );
                }

                return Container(
                  margin: EdgeInsets.only(bottom: 7 * k),
                  padding: EdgeInsets.symmetric(horizontal: 18 * k),
                  decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    children: [
                      if (wide)
                        SizedBox(
                          width: 150 * k,
                          child: Text(
                            _stage(m),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: C.muted, fontSize: 14 * k),
                          ),
                        ),
                      name(a!, 0, TextAlign.right),
                      Container(
                        margin: EdgeInsets.symmetric(horizontal: 16 * k),
                        padding: EdgeInsets.symmetric(horizontal: 14 * k, vertical: 4 * k),
                        decoration: BoxDecoration(color: C.surface3, borderRadius: BorderRadius.circular(10)),
                        child: Text(
                          '$sa : $sb',
                          style: TextStyle(
                            fontSize: 30 * k,
                            fontWeight: FontWeight.w900,
                            fontFamily: numFont,
                            fontFeatures: tabular,
                          ),
                        ),
                      ),
                      name(b!, 1, TextAlign.left),
                      if (wide) SizedBox(width: 150 * k),
                    ],
                  ),
                );
              },
            ),
          ),
        for (var i = ms.length; i < 6; i++) const Expanded(child: SizedBox()),
      ],
    );
  }
}

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../data/match_report.dart' show StatRow;
import '../games/engine.dart';
import 'dartboard.dart';
import 'hit_boards.dart';
import 'logo.dart';
import 'theme.dart';

const _muted = Color(0xFFA8B0C2);
const _bgTop = Color(0xFF10132A);
const _bgBottom = Color(0xFF070912);

String _date(DateTime d) => '${d.day}.${d.month}.${d.year}';

/// Bild teilen: Spieler auswählen (oder alle), Vorschau, „Als Bild teilen“.
class MatchShareScreen extends StatefulWidget {
  const MatchShareScreen({super.key, required this.engine, required this.rows, required this.date});
  final GameEngine engine;

  /// Statistik-Zeilen (Matchstatistik bzw. Modus-Statistik), eine Spalte je Spieler.
  final List<StatRow> rows;
  final DateTime date;

  @override
  State<MatchShareScreen> createState() => _MatchShareScreenState();
}

class _MatchShareScreenState extends State<MatchShareScreen> {
  final _key = GlobalKey();
  bool _busy = false;

  /// Gewählter Spieler (null = alle). Standard: der Sieger.
  int? _sel;

  @override
  void initState() {
    super.initState();
    _sel = widget.engine.n == 1 ? 0 : widget.engine.results().first.playerIndex;
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      const name = 'darts_ergebnis.png';
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(data!.buffer.asUint8List(), mimeType: 'image/png', name: name)],
        fileNameOverrides: [name],
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Teilen fehlgeschlagen: $e')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.engine;
    final order = [for (final r in e.results()) r.playerIndex];
    Widget chip(int? i) {
      final on = _sel == i;
      final col = i == null ? C.accent : Color(e.players[i].color);
      return ChoiceChip(
        selected: on,
        onSelected: (_) => setState(() => _sel = i),
        showCheckmark: false,
        avatar: i == null ? const Icon(Icons.groups_rounded, size: 18) : CircleAvatar(backgroundColor: col, radius: 6),
        label: Text(i == null ? 'Alle' : e.players[i].name),
        selectedColor: col.withValues(alpha: 0.22),
        side: BorderSide(color: on ? col : C.line),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ergebnis teilen')),
      body: SafeArea(
        child: Column(
          children: [
            if (e.n > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [chip(null), for (final i in order) chip(i)],
                ),
              ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FittedBox(
                    child: RepaintBoundary(
                      key: _key,
                      child: SizedBox(
                        width: 360,
                        height: 640,
                        child: MatchShareCard(engine: e, rows: widget.rows, date: widget.date, player: _sel),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: PrimaryButton(
                label: _busy ? 'Einen Moment …' : 'Als Bild teilen',
                icon: Icons.ios_share_rounded,
                onTap: _busy ? null : _share,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Teilen-Bild im Hochformat (360 × 640, geteilt mit Faktor 3 = 1080 × 1920):
/// Logo, Ergebnis, Statistik und Trefferbild – für einen Spieler oder alle.
class MatchShareCard extends StatelessWidget {
  const MatchShareCard({super.key, required this.engine, required this.rows, required this.date, this.player});
  final GameEngine engine;
  final List<StatRow> rows;
  final DateTime date;

  /// null = alle Spieler.
  final int? player;

  @override
  Widget build(BuildContext context) {
    final e = engine;
    final res = e.results();
    final winner = res.first.playerIndex;
    final focus = player ?? winner;
    final accent = Color(e.players[focus].color);
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.alphaBlend(accent.withValues(alpha: 0.30), _bgTop), _bgBottom],
            stops: const [0, 0.75],
          ),
        ),
        child: Stack(
          children: [
            // Großes, angeschnittenes Logo als Wasserzeichen
            Positioned(
              right: -90,
              top: -70,
              child: Opacity(
                opacity: 0.07,
                child: const DartsMark(size: 300),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: DefaultTextStyle(
                style: const TextStyle(color: Colors.white, fontFamily: 'Barlow'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(),
                    const SizedBox(height: 14),
                    Expanded(child: player == null ? _all(res) : _single(res, player!)),
                    const SizedBox(height: 8),
                    Text(
                      '${e.title}${e.subtitle.isEmpty ? '' : ' · ${e.subtitle}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10, color: _muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Row(
        children: [
          const DartsLogo(size: 38, radius: 10),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Darts', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, height: 1)),
              Text('Counter', style: TextStyle(fontSize: 11, color: _muted, letterSpacing: 1.5)),
            ],
          ),
          const Spacer(),
          Text(_date(date), style: const TextStyle(fontSize: 12, color: _muted, fontWeight: FontWeight.w600)),
        ],
      );

  Color _c(int i) => Color(engine.players[i].color);

  /// Ein Spieler: Name groß, Platz/Ergebnis, Werte-Kacheln, großes Trefferbild.
  Widget _single(List<PlayerResult> res, int i) {
    final e = engine;
    final r = res.firstWhere((x) => x.playerIndex == i);
    final col = _c(i);
    final label = e.n == 1
        ? 'ERGEBNIS'
        : r.rank == 1
            ? 'SIEG'
            : '${r.rank}. PLATZ';
    final stats = [
      for (final row in rows)
        if (i < row.values.length && row.values[i] != '–' && row.label != 'Ergebnis') (row.label, row.values[i], row.best == i),
    ];
    final h = e.hits[i];
    final top = HitBoards.topLine(h);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(e.title.toUpperCase(),
            style: const TextStyle(fontSize: 11, letterSpacing: 1.6, fontWeight: FontWeight.w800, color: _muted)),
        const SizedBox(height: 4),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(8)),
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w900, color: Color(0xFF0B0E1A))),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(r.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: col)),
            ),
          ],
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(e.players[i].name, style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w800, height: 1.1)),
        ),
        const SizedBox(height: 10),
        // Werte als Kacheln (max. 8)
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in stats.take(8))
              Container(
                width: 155,
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: s.$3 ? 0.13 : 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: s.$3 ? col.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: _muted)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(s.$2,
                          style: const TextStyle(fontFamily: numFont, fontSize: 19, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (_, c) => Center(
              child: Dartboard(size: min(c.maxWidth, c.maxHeight - 18), heat: h, color: col, showCounts: true),
            ),
          ),
        ),
        if (top.isNotEmpty)
          Text('Am häufigsten: $top', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: _muted)),
      ],
    );
  }

  /// Alle Spieler: Rangliste, Vergleichstabelle, Trefferbilder nebeneinander (max. 4 Spieler).
  Widget _all(List<PlayerResult> res) {
    final e = engine;
    final shown = [for (final r in res.take(4)) r.playerIndex];
    final tableRows = rows.where((r) => r.label != 'Ergebnis').take(e.n > 2 ? 6 : 8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(e.title.toUpperCase(),
            style: const TextStyle(fontSize: 11, letterSpacing: 1.6, fontWeight: FontWeight.w800, color: _muted)),
        const SizedBox(height: 6),
        for (final r in res.take(4))
          Container(
            margin: const EdgeInsets.only(bottom: 5),
            padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: r.rank == 1 ? 0.11 : 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _c(r.playerIndex).withValues(alpha: r.rank == 1 ? 0.85 : 0.25)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text('${r.rank}.',
                      style: TextStyle(fontWeight: FontWeight.w800, color: r.rank == 1 ? _c(r.playerIndex) : _muted)),
                ),
                CircleAvatar(backgroundColor: _c(r.playerIndex), radius: 4),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(e.players[r.playerIndex].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
                Text(r.value, style: const TextStyle(fontFamily: numFont, fontSize: 18, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        const SizedBox(height: 6),
        // Vergleichstabelle
        Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              for (final row in tableRows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.5),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Text(row.label,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: _muted)),
                      ),
                      for (final i in shown)
                        Expanded(
                          flex: 4,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(i < row.values.length ? row.values[i] : '–',
                                style: TextStyle(
                                    fontFamily: numFont,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: row.best == i ? _c(i) : Colors.white)),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(builder: (_, c) {
            const gap = 6.0;
            final cols = shown.length;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            final size = min(w, c.maxHeight - 16);
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var k = 0; k < cols; k++) ...[
                  if (k > 0) const SizedBox(width: gap),
                  SizedBox(
                    width: w,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Dartboard(
                            size: size,
                            heat: e.hits[shown[k]],
                            color: _c(shown[k]),
                            showCounts: true,
                            showNumbers: size > 120),
                        const SizedBox(height: 2),
                        Text(e.players[shown[k]].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _c(shown[k]))),
                      ],
                    ),
                  ),
                ],
              ],
            );
          }),
        ),
      ],
    );
  }
}

import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../games/engine.dart';
import '../games/x01.dart';
import '../models/dart.dart';
import 'theme.dart';

/// Ein Spiel im geteilten Bildschirm der Anzeige.
class BoardEntry {
  const BoardEntry(this.label, this.engine);

  /// z. B. „Scheibe 2“
  final String label;
  final GameEngine engine;
}

/// Geteilter Bildschirm („Alle“ Scheiben): 2 Spiele nebeneinander, 3–4 als 2×2-Raster,
/// mehr mit 3 Spalten. Hochkant (Handy) stehen bis zu 3 Spiele untereinander.
class BoardGrid extends StatelessWidget {
  const BoardGrid({super.key, required this.boards});
  final List<BoardEntry> boards;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final n = boards.length;
      final landscape = box.maxWidth >= box.maxHeight;
      final cols = landscape ? (n <= 4 ? min(n, 2) : 3) : (n <= 3 ? 1 : 2);
      final rows = (n + cols - 1) ~/ cols;
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
        child: Column(
          children: [
            for (var r = 0; r < rows; r++)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var c = 0; c < cols; c++)
                      Expanded(
                        child: r * cols + c < n
                            ? BoardTile(entry: boards[r * cols + c])
                            : const SizedBox(),
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// Kachel eines Spiels: Kopf „Scheibe n“ mit Modus/Leg, je Spieler eine Zeile mit
/// Name, Legs/Sets, Average, Aufnahme und großen Restpunkten.
class BoardTile extends StatelessWidget {
  const BoardTile({super.key, required this.entry});
  final BoardEntry entry;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final k = min(box.maxWidth / 620, box.maxHeight / 380).clamp(0.4, 1.6);
      final e = entry.engine;
      final winner = e.finished ? e.results().first.playerIndex : null;
      return Container(
        margin: EdgeInsets.all(5 * k),
        padding: EdgeInsets.fromLTRB(12 * k, 10 * k, 12 * k, 8 * k),
        decoration: BoxDecoration(
          color: C.surface.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(24 * k),
          border: Border.all(color: C.border, width: 1.5),
        ),
        child: Column(
          children: [
            _header(e, k),
            SizedBox(height: 6 * k),
            Expanded(
              child: Column(
                children: [for (var i = 0; i < e.n; i++) Expanded(child: _PlayerRow(e: e, i: i, winner: winner))],
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _header(GameEngine e, double k) {
    final so = e is X01Game && e.singleOutLeg;
    return Row(
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 14 * k, vertical: 6 * k),
          decoration: BoxDecoration(color: C.accent, borderRadius: BorderRadius.circular(99)),
          child: Text(
            entry.label.toUpperCase(),
            style: TextStyle(fontSize: 22 * k, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: C.bg),
          ),
        ),
        SizedBox(width: 12 * k),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                so ? '${e.start} · SINGLE OUT IN DIESEM LEG' : e.title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 19 * k,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: so ? C.gold : C.accent,
                ),
              ),
              Text(
                e.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17 * k, color: C.muted, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.e, required this.i, required this.winner});
  final GameEngine e;
  final int i;
  final int? winner;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // Höhe der Zeile bestimmt die Schrift; zu wenig Platz → verkleinern statt überlaufen.
      final k = min(box.maxWidth / 560, box.maxHeight / 150).clamp(0.3, 1.8);
      final active = i == e.cur && !e.finished;
      final won = winner == i && e.n > 1;
      final place = e is X01Game ? (e as X01Game).placeOf(i) : null;
      final lost = (winner != null && e.n > 1 && !won) || (place != null && !e.finished);
      final col = Color(e.players[i].color);
      final edge = won ? C.gold : col;
      final lit = active || won;
      final innerW = box.maxWidth - 2 * 3 * k - 30 * k;
      return AnimatedOpacity(
        duration: const Duration(milliseconds: 400),
        opacity: lost ? 0.5 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: EdgeInsets.symmetric(vertical: 3 * k),
          padding: EdgeInsets.fromLTRB(0, 6 * k, 14 * k, 6 * k),
          decoration: BoxDecoration(
            gradient: C.cardGradient(edge, lit ? 0.26 : 0.04),
            borderRadius: BorderRadius.circular(18 * k),
            border: Border.all(color: lit ? edge : C.border, width: lit ? 3 : 1),
            boxShadow: lit ? [BoxShadow(color: edge.withValues(alpha: 0.35), blurRadius: 22)] : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Farbbalken: am Wurf leuchtend
              Container(
                width: 10 * k,
                margin: EdgeInsets.only(left: 6 * k, right: 12 * k),
                decoration: BoxDecoration(
                  color: lit ? edge : col.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Expanded(
                flex: 11,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: max(innerW * 11 / 20, 10),
                    child: _left(active, won, place, col, k),
                  ),
                ),
              ),
              SizedBox(width: 8 * k),
              Expanded(
                flex: 9,
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.centerRight,
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
            ],
          ),
        ),
      );
    },
  );

  Widget _left(bool active, bool won, int? place, Color col, double k) {
    final legs = e.legsToWin;
    final sets = e.setsToWin;
    final g = e;
    final avg = g is X01Game ? 'Ø ${fmt1(g.stats[i].average)}' : e.subLine(i);
    final info = [
      if (sets != null) 'Sets ${e.setsOf(i)}',
      if (legs != null) 'Legs ${e.legsOf(i)}',
      ?avg,
    ];
    final list = active ? e.turn : e.lastTurns[i];
    final sum = list.fold<int>(0, (a, d) => a + d.value);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                e.players[i].name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 34 * k, fontWeight: FontWeight.w800, color: active || won ? C.text : C.muted2),
              ),
            ),
            if (active) ...[SizedBox(width: 10 * k), _pill('AM WURF', col, k)],
            if (won) ...[SizedBox(width: 10 * k), _pill('SIEGER', C.gold, k, icon: Icons.emoji_events_rounded)],
            if (!won && place != null) ...[
              SizedBox(width: 10 * k),
              _pill(place == 1 ? 'SIEGER' : 'PLATZ $place', C.gold, k),
            ],
          ],
        ),
        if (info.isNotEmpty)
          Text(
            info.join('  ·  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 23 * k,
              fontWeight: FontWeight.w700,
              color: C.text.withValues(alpha: 0.8),
              fontFeatures: tabular,
            ),
          ),
        SizedBox(height: 8 * k),
        SizedBox(
          height: 46 * k,
          child: Row(
            children: [
              for (var j = 0; j < 3; j++) ...[
                Expanded(child: _chip(j < list.length ? list[j] : null, active, col, k)),
                SizedBox(width: 6 * k),
              ],
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    list.isEmpty ? '' : '= $sum',
                    style: TextStyle(
                      fontFamily: numFont,
                      fontSize: 34 * k,
                      fontWeight: FontWeight.w800,
                      color: active ? col : C.muted2,
                      fontFeatures: tabular,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(Dart? d, bool active, Color col, double k) {
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
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: d == null ? C.surface.withValues(alpha: 0.5) : c.withValues(alpha: active ? 0.22 : 0.10),
        borderRadius: BorderRadius.circular(12 * k),
        border: Border.all(color: d == null ? C.border : c.withValues(alpha: strong ? 0.9 : 0.5), width: strong ? 2 : 1),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 4 * k),
          child: Text(
            d?.label ?? '–',
            style: TextStyle(
              fontFamily: numFont,
              fontSize: 30 * k,
              fontWeight: FontWeight.w800,
              color: d == null ? C.muted : (active ? C.text : C.muted2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(String text, Color c, double k, {IconData? icon}) => Container(
    padding: EdgeInsets.symmetric(horizontal: 10 * k, vertical: 4 * k),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: c.withValues(alpha: 0.8)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 18 * k, color: c), SizedBox(width: 4 * k)],
        Text(
          text,
          style: TextStyle(fontSize: 16 * k, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: c),
        ),
      ],
    ),
  );
}

import 'package:material_ui/material_ui.dart';

import '../data/match_report.dart';
import '../models/player.dart';
import 'theme.dart';

/// Vergleichstabelle Spieler gegen Spieler. Der beste Wert jeder Zeile wird in der
/// Spielerfarbe hervorgehoben. [k] skaliert alles (Anzeige auf dem Tablet: größer).
class StatsTable extends StatelessWidget {
  const StatsTable({super.key, required this.players, required this.rows, this.k = 1});
  final List<GamePlayer> players;
  final List<StatRow> rows;
  final double k;

  @override
  Widget build(BuildContext context) {
    final n = players.length;
    return LayoutBuilder(builder: (context, box) {
      final labelW = 150.0 * k;
      final minCol = 92.0 * k;
      final fits = labelW + n * minCol <= box.maxWidth;
      final colW = fits ? (box.maxWidth - labelW) / n : minCol;
      final table = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(labelW, colW),
          for (var r = 0; r < rows.length; r++) _row(rows[r], labelW, colW, r.isOdd),
        ],
      );
      if (fits) return table;
      // Viele Spieler: seitlich schiebbar
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: labelW + n * colW, child: table),
      );
    });
  }

  Widget _header(double labelW, double colW) => Padding(
        padding: EdgeInsets.only(bottom: 6 * k),
        child: Row(
          children: [
            SizedBox(width: labelW),
            for (final p in players)
              SizedBox(
                width: colW,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 10 * k,
                      height: 10 * k,
                      decoration: BoxDecoration(color: Color(p.color), shape: BoxShape.circle),
                    ),
                    SizedBox(width: 6 * k),
                    Flexible(
                      child: Text(p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15 * k, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

  Widget _row(StatRow row, double labelW, double colW, bool shaded) {
    final best = row.best;
    return Container(
      padding: EdgeInsets.symmetric(vertical: 7 * k, horizontal: 8 * k),
      decoration: BoxDecoration(
        color: shaded ? C.surface.withValues(alpha: 0.6) : Colors.transparent,
        borderRadius: BorderRadius.circular(10 * k),
      ),
      child: Row(
        children: [
          SizedBox(
            width: labelW - 16 * k,
            child: Text(row.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14 * k, color: C.muted, fontWeight: FontWeight.w700)),
          ),
          for (var i = 0; i < players.length; i++)
            SizedBox(
              width: colW,
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8 * k, vertical: 2 * k),
                  decoration: best == i
                      ? BoxDecoration(
                          color: Color(players[i].color).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8 * k),
                        )
                      : null,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      row.values[i],
                      style: TextStyle(
                        fontFamily: numFont,
                        fontSize: 20 * k,
                        fontWeight: FontWeight.w800,
                        color: best == i ? Color(players[i].color) : C.text,
                        fontFeatures: tabular,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Kurzliste aller Legs (Match-Statistik).
class LegList extends StatelessWidget {
  const LegList({super.key, required this.report, this.k = 1});
  final MatchReport report;
  final double k;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final l in report.legs)
            Padding(
              padding: EdgeInsets.only(bottom: 6 * k),
              child: Row(
                children: [
                  SizedBox(
                    width: 64 * k,
                    child: Text('Leg ${l.number}',
                        style: TextStyle(fontSize: 14 * k, color: C.muted, fontWeight: FontWeight.w700)),
                  ),
                  if (l.winner != null) ...[
                    Container(
                      width: 10 * k,
                      height: 10 * k,
                      decoration:
                          BoxDecoration(color: Color(report.players[l.winner!].color), shape: BoxShape.circle),
                    ),
                    SizedBox(width: 8 * k),
                    Expanded(
                      child: Text(report.players[l.winner!].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15 * k, fontWeight: FontWeight.w800)),
                    ),
                    Text(
                      '${l.players[l.winner!].darts} Darts · Finish ${l.players[l.winner!].finish ?? '–'}'
                      '${l.singleOut ? ' · Single Out' : ''}',
                      style: TextStyle(fontSize: 14 * k, color: C.muted2, fontFeatures: tabular),
                    ),
                  ] else
                    Expanded(child: Text('nicht beendet', style: TextStyle(fontSize: 14 * k, color: C.muted))),
                ],
              ),
            ),
        ],
      );
}

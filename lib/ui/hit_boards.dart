import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../models/player.dart';
import 'dartboard.dart';
import 'theme.dart';

/// Trefferbilder aller Spieler nebeneinander (Tablet) bzw. untereinander (schmales Handy):
/// je Spieler eine Scheibe mit eingefärbten Feldern und Anzahl, dazu Darts, Quote und Miss.
class HitBoards extends StatelessWidget {
  const HitBoards({super.key, required this.players, required this.hits, this.order});

  final List<GamePlayer> players;

  /// Treffer je Spieler (Schlüssel wie Dart.key).
  final List<Map<String, int>> hits;

  /// Reihenfolge der Spieler (z. B. nach Platzierung); Standard: wie [players].
  final List<int>? order;

  static String topLine(Map<String, int> h) {
    final top = (h.entries.where((x) => x.key != 'Miss').toList()..sort((a, b) => b.value.compareTo(a.value)))
        .take(3)
        .map((x) => '${x.key == '50' ? 'Bull' : x.key.startsWith('S') ? x.key.substring(1) : x.key} ×${x.value}');
    return top.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final idx = order ?? [for (var i = 0; i < players.length; i++) i];
    return LayoutBuilder(builder: (context, c) {
      // So viele Spalten wie mit mindestens 240 px Breite passen (max. 4).
      final cols = max(1, min(idx.length, min(4, (c.maxWidth / 240).floor())));
      const gap = 10.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final i in idx) SizedBox(width: w, child: _one(i, w))],
      );
    });
  }

  Widget _one(int i, double w) {
    final h = hits[i];
    final total = h.values.fold(0, (a, b) => a + b);
    final miss = h['Miss'] ?? 0;
    final rate = total == 0 ? 0 : ((total - miss) / total * 100).round();
    final col = Color(players[i].color);
    final top = topLine(h);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: C.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: col.withValues(alpha: 0.45)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(backgroundColor: col, radius: 6),
              const SizedBox(width: 6),
              Flexible(
                child: Text(players[i].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Dartboard(size: min(w - 20, 320), heat: h, color: col, showCounts: true),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              children: [
                _stat('Darts', '$total'),
                const SizedBox(width: 18),
                _stat('Getroffen', '$rate %'),
                const SizedBox(width: 18),
                _stat('Miss', '$miss'),
              ],
            ),
          ),
          if (top.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Am häufigsten: $top',
                textAlign: TextAlign.center, style: TextStyle(color: C.muted, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, fontFeatures: tabular)),
          Text(label, style: TextStyle(color: C.muted, fontSize: 11)),
        ],
      );
}

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../games/tournament.dart';
import 'logo.dart';
import 'theme.dart';
import 'tournament_screens.dart' show medalColor;

String _date(DateTime d) => '${d.day}.${d.month}.${d.year}';

/// Vorschau einer Ergebniskarte mit „Teilen“.
class ShareCardScreen extends StatefulWidget {
  const ShareCardScreen({super.key, required this.card, required this.fileName});
  final Widget card;
  final String fileName;

  @override
  State<ShareCardScreen> createState() => _ShareCardScreenState();
}

class _ShareCardScreenState extends State<ShareCardScreen> {
  final _key = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(data!.buffer.asUint8List(), mimeType: 'image/png', name: widget.fileName)],
        fileNameOverrides: [widget.fileName],
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
    return Scaffold(
      appBar: AppBar(title: const Text('Ergebnis teilen')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FittedBox(
                    child: RepaintBoundary(key: _key, child: SizedBox(width: 360, height: 450, child: widget.card)),
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

/// Gemeinsamer Rahmen der Karten.
class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.accent, required this.child, required this.footer});
  final Color accent;
  final Widget child;
  final String footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.alphaBlend(accent.withValues(alpha: 0.28), const Color(0xFF10132A)), const Color(0xFF080A16)],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontFamily: 'Barlow'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const DartsLogo(size: 30, radius: 8),
                const SizedBox(width: 8),
                const Text('Darts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const Spacer(),
                Text(footer, style: const TextStyle(fontSize: 12, color: Color(0xFFA8B0C2))),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// Siegerpodest eines Turniers.
class TournamentShareCard extends StatelessWidget {
  const TournamentShareCard({super.key, required this.t});
  final Tournament t;

  @override
  Widget build(BuildContext context) {
    final pl = t.placements();
    String nameOf(int rank) => pl.where((p) => p.rank == rank).map((p) => t.players[p.player].name).join(' / ');
    Widget step(int rank, double h) => Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (rank == 1) const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFC94A), size: 34),
              Text(nameOf(rank).isEmpty ? '–' : nameOf(rank),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: rank == 1 ? 16 : 13)),
              const SizedBox(height: 6),
              Container(
                height: h,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [medalColor(rank), medalColor(rank).withValues(alpha: 0.35)],
                  ),
                ),
                alignment: Alignment.center,
                child: Text('$rank',
                    style: const TextStyle(fontFamily: numFont, fontSize: 34, fontWeight: FontWeight.w800, color: C.ink)),
              ),
            ],
          ),
        );
    return _CardFrame(
      accent: const Color(0xFFFFC94A),
      footer: _date(t.created),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.system.label.toUpperCase(),
              style: const TextStyle(fontSize: 12, letterSpacing: 1.4, fontWeight: FontWeight.w800, color: Color(0xFFA8B0C2))),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(t.name, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
          ),
          Text('${t.n} Spieler · ${t.start} ${t.doubleOut ? 'Double Out' : 'Single Out'}',
              style: const TextStyle(fontSize: 13, color: Color(0xFFA8B0C2))),
          const Spacer(),
          SizedBox(
            height: 220,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [step(2, 80), step(1, 115), step(3, 55)]),
          ),
        ],
      ),
    );
  }
}

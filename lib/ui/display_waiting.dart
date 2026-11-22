import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../net/link.dart';
import 'logo.dart';

// Farben aus dem Logo (Lila → Pink → Orange)
// Farben passend zum Eis-Logo (3.0.0): tiefes Eisblau, Cyan, Frostweiß
const _purple = Color(0xFF2F6FD6);
const _pink = Color(0xFF5FD8EE);
const _orange = Color(0xFFDDF6FF);
const _black = Color(0xFF050507);

/// Wartebildschirm der Anzeige (Tablet), bis am Handy ein Spiel oder Turnier startet:
/// schwarz, oben das leuchtende Logo, feine Scheiben-Ringe im Hintergrund.
class DisplayWaiting extends StatefulWidget {
  const DisplayWaiting({super.key});

  @override
  State<DisplayWaiting> createState() => _DisplayWaitingState();
}

class _DisplayWaitingState extends State<DisplayWaiting> with SingleTickerProviderStateMixin {
  /// Ein langsamer Takt für Leuchten, Ringe und Punkte.
  late final AnimationController _t = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
    ..repeat();

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final k = (min(box.maxWidth, box.maxHeight) / 680).clamp(0.55, 1.7);
      return ColoredBox(
        color: _black,
        child: Stack(
          children: [
            // Ringe und Lichtschein hinter dem Logo
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _t,
                  builder: (_, _) => CustomPaint(painter: _Backdrop(_t.value, k, box.maxHeight)),
                ),
              ),
            ),
            Positioned.fill(
              child: Column(
                children: [
                  SizedBox(height: box.maxHeight * 0.09),
                  // Logo mit sanftem Atmen
                  AnimatedBuilder(
                    animation: _t,
                    builder: (_, child) {
                      final s = 0.5 + 0.5 * sin(_t.value * 2 * pi);
                      return Transform.scale(scale: 1 + 0.025 * s, child: child);
                    },
                    child: DartsMark(size: 170 * k),
                  ),
                  SizedBox(height: 14 * k),
                  Text(
                    'DARTS',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 18 * k,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 10 * k,
                    ),
                  ),
                  const Spacer(),
                  _fit(Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Warte auf Spielstart',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 56 * k,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                          height: 1.1,
                        ),
                      ),
                      Padding(padding: EdgeInsets.only(bottom: 16 * k), child: _Dots(t: _t, k: k)),
                    ],
                  )),
                  SizedBox(height: 18 * k),
                  // feine Linie im Farbverlauf des Logos
                  Container(
                    width: 220 * k,
                    height: 4 * k,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      gradient: const LinearGradient(colors: [_purple, _pink, _orange]),
                      boxShadow: [BoxShadow(color: _pink.withValues(alpha: 0.5), blurRadius: 16 * k)],
                    ),
                  ),
                  SizedBox(height: 34 * k),
                  ListenableBuilder(listenable: Link.I, builder: (_, _) => _status(k)),
                  const Spacer(),
                  _fit(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.phone_android_rounded, color: Colors.white.withValues(alpha: 0.45), size: 24 * k),
                      SizedBox(width: 10 * k),
                      Text(
                        'Starte am Handy ein Spiel oder Turnier',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 20 * k, fontWeight: FontWeight.w600),
                      ),
                    ],
                  )),
                  SizedBox(height: box.maxHeight * 0.07),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  /// Auf schmalen Bildschirmen verkleinern statt überlaufen.
  Widget _fit(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: FittedBox(fit: BoxFit.scaleDown, child: child),
      );

  Widget _status(double k) {
    final connected = Link.I.isConnected;
    final c = connected ? const Color(0xFF3DDC97) : const Color(0xFFFFB347);
    final text = connected
        ? 'Verbunden mit ${Link.I.hostName ?? 'Host'}'
        : (Link.I.status.isEmpty ? 'Nicht verbunden' : Link.I.status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 22 * k, vertical: 11 * k),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _t,
            builder: (_, _) {
              final s = 0.5 + 0.5 * sin(_t.value * 2 * pi);
              return Container(
                width: 12 * k,
                height: 12 * k,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: c.withValues(alpha: 0.35 + 0.45 * s), blurRadius: 6 * k + 8 * k * s)],
                ),
              );
            },
          ),
          SizedBox(width: 12 * k),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 21 * k, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Drei Punkte, die nacheinander aufleuchten.
class _Dots extends StatelessWidget {
  const _Dots({required this.t, required this.k});
  final Animation<double> t;
  final double k;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: t,
        builder: (_, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsets.only(left: 6 * k),
                child: Opacity(
                  opacity: 0.25 + 0.75 * max(0.0, sin((t.value - i * 0.15) * 2 * pi)),
                  child: Container(
                    width: 9 * k,
                    height: 9 * k,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// Hintergrund: weicher Schein in Logofarben oben, feine konzentrische Ringe (wie eine Scheibe),
/// die langsam nach außen wandern.
class _Backdrop extends CustomPainter {
  _Backdrop(this.t, this.k, this.h);
  final double t;
  final double k;
  final double h;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, h * 0.09 + 85 * k);
    final s = 0.5 + 0.5 * sin(t * 2 * pi);
    // Schein hinter dem Logo
    final glowR = 260 * k;
    canvas.drawCircle(
      c,
      glowR,
      Paint()
        ..shader = RadialGradient(colors: [
          _pink.withValues(alpha: 0.20 + 0.08 * s),
          _orange.withValues(alpha: 0.07),
          _black.withValues(alpha: 0),
        ], stops: const [0, 0.45, 1])
            .createShader(Rect.fromCircle(center: c, radius: glowR)),
    );
    // Ringe
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    const n = 7;
    final step = 110 * k;
    for (var i = 0; i < n; i++) {
      final r = (i + t) * step + 120 * k;
      final fade = (1 - (i + t) / n).clamp(0.0, 1.0);
      ring.color = Colors.white.withValues(alpha: 0.06 * fade);
      canvas.drawCircle(c, r, ring);
    }
    // ganz unten leichte Abdunklung für Ruhe
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_black.withValues(alpha: 0), _black.withValues(alpha: 0.6)],
          stops: const [0.55, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_Backdrop old) => old.t != t || old.k != k || old.h != h;
}

import 'dart:math';

import 'package:material_ui/material_ui.dart';

/// Hintergrund des App-Icons: heller Blauverlauf mit Lichtkegel oben links
/// und leichter Vignette. Auf einer 512er-Fläche gezeichnet.
void paintLogoBackground(Canvas canvas, Size size) {
  final k = size.width / 512;
  canvas.save();
  canvas.scale(k);
  const rect = Rect.fromLTWH(0, 0, 512, 512);
  canvas.drawRect(
    rect,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF39A6FF), Color(0xFF1366E0), Color(0xFF0A3FA8)],
        stops: [0, 0.55, 1],
      ).createShader(rect),
  );
  // Lichtkegel oben links
  canvas.drawRect(
    rect,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.56, -0.72),
        radius: 0.75,
        colors: [Colors.white.withValues(alpha: 0.42), Colors.white.withValues(alpha: 0.06), Colors.white.withValues(alpha: 0)],
        stops: const [0, 0.5, 1],
      ).createShader(rect),
  );
  // Vignette
  canvas.drawRect(
    rect,
    Paint()
      ..shader = RadialGradient(
        radius: 0.72,
        colors: [const Color(0xFF001A4D).withValues(alpha: 0), const Color(0xFF001A4D).withValues(alpha: 0.35)],
        stops: const [0.6, 1],
      ).createShader(rect),
  );
  canvas.restore();
}

/// Das App-Logo: senkrechter Pfeil in der Mitte (Flight oben, Spitze unten), umgeben von
/// einem dicken weißen Ring, der oben und unten am Pfeil offen ist – links und rechts
/// bleiben zwei Halbkreise. Gezeichnet auf einer 512er-Fläche und auf [size] skaliert.
class DartsLogoPainter extends CustomPainter {
  const DartsLogoPainter({this.background = true, this.scale = 1.0});

  /// Mit Blauverlauf (App-Icon) oder transparent.
  final bool background;

  /// Verkleinert das Motiv um die Mitte (für adaptive Icons mit Sicherheitszone).
  final double scale;

  static const _c = Offset(256, 256);

  /// Pfeil und Ring nehmen 80 % der Fläche ein.
  static const _len = 512 * 0.8;
  static const _stroke = 44.0;
  static const _ringR = _len / 2 - _stroke / 2;

  /// Halber Öffnungswinkel oben und unten (Flight-Breite plus Luft und runde Enden).
  static final _gap = asin(86 / _ringR);

  /// Zeichnet [draw] als weichen Schatten (versetzt, unscharf, halbtransparent).
  static void _shadow(Canvas canvas, Offset off, double blur, Color color, void Function(Paint solid) draw) {
    canvas.save();
    canvas.translate(off.dx, off.dy);
    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, color.a));
    final p = Paint()
      ..color = color.withValues(alpha: 1)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    draw(p);
    canvas.restore();
    canvas.restore();
  }

  static void _ring(Canvas canvas, Paint? solid) {
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    if (solid != null) {
      ring
        ..color = solid.color
        ..maskFilter = solid.maskFilter;
    } else {
      ring.shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.white, Color(0xFFDCEBFF)],
      ).createShader(Rect.fromCircle(center: _c, radius: _ringR + _stroke / 2));
    }
    final rect = Rect.fromCircle(center: _c, radius: _ringR);
    final sweep = pi - 2 * _gap;
    canvas.drawArc(rect, -pi / 2 + _gap, sweep, false, ring); // rechte Hälfte
    canvas.drawArc(rect, pi / 2 + _gap, sweep, false, ring); // linke Hälfte
  }

  /// Pfeil mit Spitze im Ursprung, der Körper reicht nach oben. [solid] = einfarbig (für den Schatten).
  static void _dart(Canvas canvas, Paint? solid) {
    const len = _len;
    const w = len / 330;
    Paint fill(Color c) => solid ?? (Paint()..color = c);
    RRect rr(double x, double y, double wd, double h, double r) =>
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, wd, h), Radius.circular(r));

    // Spitze
    canvas.drawRRect(rr(-5 * w, -len * 0.22, 10 * w, len * 0.22, 5 * w), fill(const Color(0xFFEEF3FB)));
    // Barrel
    final barrel = rr(-15 * w, -len * 0.56, 30 * w, len * 0.36, 12 * w);
    canvas.drawRRect(
      barrel,
      solid ??
          (Paint()
            ..shader = const LinearGradient(
              colors: [Color(0xFFC9D6EA), Colors.white, Color(0xFFB8C7DE)],
              stops: [0, 0.4, 1],
            ).createShader(barrel.outerRect)),
    );
    if (solid == null) {
      for (final k in [0.3, 0.38, 0.46]) {
        canvas.drawRect(Rect.fromLTWH(-15 * w, -len * k, 30 * w, 3 * w),
            Paint()..color = const Color(0xFF9FB3D1).withValues(alpha: 0.55));
      }
    }
    // Schaft
    canvas.drawRect(Rect.fromLTWH(-6 * w, -len * 0.76, 12 * w, len * 0.22), fill(Colors.white));
    // Flights
    final flight = Path()
      ..moveTo(0, -len * 0.66)
      ..lineTo(-40 * w, -len * 0.86)
      ..lineTo(-40 * w, -len)
      ..lineTo(0, -len * 0.88)
      ..lineTo(40 * w, -len)
      ..lineTo(40 * w, -len * 0.86)
      ..close();
    canvas.drawPath(
      flight,
      solid ??
          (Paint()
            ..shader = const LinearGradient(
              colors: [Colors.white, Colors.white, Color(0xFFDFEAF8), Color(0xFFDFEAF8)],
              stops: [0, 0.5, 0.5, 1],
            ).createShader(const Rect.fromLTWH(-40 * w, -len, 80 * w, len * 0.34))),
    );
  }

  static void _placeDart(Canvas canvas, void Function() draw) {
    canvas.save();
    canvas.translate(_c.dx, _c.dy + _len / 2); // Spitze unten, Flight oben
    draw();
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (background) paintLogoBackground(canvas, size);
    final k = size.width / 512;
    canvas.save();
    canvas.scale(k);
    canvas.translate(256, 256);
    canvas.scale(scale);
    canvas.translate(-256, -256);

    _shadow(canvas, const Offset(0, 12), 14, const Color(0xFF002A75).withValues(alpha: 0.45), (p) => _ring(canvas, p));
    _ring(canvas, null);
    _shadow(canvas, const Offset(8, 12), 9, const Color(0xFF002060).withValues(alpha: 0.45),
        (p) => _placeDart(canvas, () => _dart(canvas, p)));
    _placeDart(canvas, () => _dart(canvas, null));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DartsLogoPainter old) => old.background != background || old.scale != scale;
}

/// Logo als Widget (abgerundetes Quadrat).
class DartsLogo extends StatelessWidget {
  const DartsLogo({super.key, this.size = 32, this.radius});
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius ?? size * 0.26),
        child: CustomPaint(size: Size.square(size), painter: const DartsLogoPainter()),
      );
}

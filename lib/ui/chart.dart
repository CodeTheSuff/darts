import 'dart:math';

import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// Einfaches Liniendiagramm: Werte über die Zeit, mit Raster, Fläche und
/// hervorgehobenem letzten Punkt. [labels] = Beschriftung der x-Achse (erster/letzter Punkt).
class LineChart extends StatelessWidget {
  const LineChart({
    super.key,
    required this.values,
    required this.color,
    this.height = 180,
    this.suffix = '',
    this.firstLabel,
    this.lastLabel,
  });

  final List<double> values;
  final Color color;
  final double height;
  final String suffix;
  final String? firstLabel;
  final String? lastLabel;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox(
        height: height * 0.6,
        child: Center(
          child: Text(
            values.isEmpty ? 'Noch keine Daten im Zeitraum' : 'Ab zwei Matches erscheint hier der Verlauf',
            style: TextStyle(color: C.muted),
          ),
        ),
      );
    }
    return Column(
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _LinePainter(values, color, C.line, C.muted, C.surface, suffix),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const SizedBox(width: 36),
            Text(firstLabel ?? '', style: TextStyle(color: C.muted, fontSize: 11)),
            const Spacer(),
            Text(lastLabel ?? '', style: TextStyle(color: C.muted, fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.v, this.color, this.grid, this.label, this.bg, this.suffix);
  final List<double> v;
  final Color color;
  final Color grid;
  final Color label;
  final Color bg;
  final String suffix;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 36.0;
    const top = 10.0;
    const bottom = 6.0;
    final w = size.width - left - 8;
    final h = size.height - top - bottom;
    var lo = v.reduce(min);
    var hi = v.reduce(max);
    if (hi - lo < 1) {
      lo -= 5;
      hi += 5;
    }
    // „schöne“ Achsengrenzen
    final step = _niceStep((hi - lo) / 3);
    lo = (lo / step).floor() * step;
    hi = (hi / step).ceil() * step;
    double y(double val) => top + h - (val - lo) / (hi - lo) * h;
    double x(int i) => left + (v.length == 1 ? w / 2 : i / (v.length - 1) * w);

    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var g = lo; g <= hi + 0.001; g += step) {
      final yy = y(g);
      canvas.drawLine(Offset(left, yy), Offset(left + w, yy), gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: g.toStringAsFixed(0), style: TextStyle(color: label, fontSize: 10, fontFamily: 'Barlow')),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(left - tp.width - 6, yy - tp.height / 2));
    }

    final path = Path()..moveTo(x(0), y(v[0]));
    for (var i = 1; i < v.length; i++) {
      path.lineTo(x(i), y(v[i]));
    }
    final area = Path.from(path)
      ..lineTo(x(v.length - 1), top + h)
      ..lineTo(x(0), top + h)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.30), color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(left, top, w, h)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    if (v.length <= 40) {
      for (var i = 0; i < v.length; i++) {
        canvas.drawCircle(Offset(x(i), y(v[i])), 2.5, Paint()..color = color);
      }
    }
    final last = Offset(x(v.length - 1), y(v.last));
    canvas.drawCircle(last, 6, Paint()..color = bg);
    canvas.drawCircle(last, 4.5, Paint()..color = color);
  }

  static double _niceStep(double raw) {
    if (raw <= 0) return 1;
    final mag = pow(10, (log(raw) / ln10).floor()).toDouble();
    final n = raw / mag;
    final f = n < 1.5 ? 1 : n < 3 ? 2 : n < 7 ? 5 : 10;
    return f * mag;
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.v != v || old.color != color;
}

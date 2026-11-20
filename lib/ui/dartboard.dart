import 'dart:math';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../games/engine.dart';
import '../models/dart.dart';

const _order = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5];

// Radien relativ zum äußeren Double-Ring (= 1.0)
const _bullIn = 0.045;
const _bullOut = 0.10;
const _triIn = 0.56;
const _triOut = 0.63;
const _dblIn = 0.92;

double _rad(double deg) => deg * pi / 180;
double _center(int k) => _rad(-90 + 18.0 * k);
double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Dartscheibe im „Dark Glow“-Stil mit Mini-Darts.
class Dartboard extends StatefulWidget {
  const Dartboard({
    super.key,
    required this.size,
    this.darts = const [],
    this.color = const Color(0xFF5AA9FF),
    this.targets = const [],
    this.heat,
    this.showNumbers = true,
    this.showCounts = false,
  });

  final double size;
  final List<Dart> darts;
  final Color color;
  final List<Target> targets;
  final Map<String, int>? heat;
  final bool showNumbers;

  /// Zeigt auf jedem getroffenen Feld (aus [heat]) die Anzahl im Kreis.
  final bool showCounts;

  @override
  State<Dartboard> createState() => _DartboardState();
}

class _DartboardState extends State<Dartboard> with TickerProviderStateMixin {
  late final AnimationController _enter =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260), value: 1);
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  void _syncPulse() {
    if (widget.targets.isNotEmpty) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void didUpdateWidget(Dartboard old) {
    super.didUpdateWidget(old);
    if (widget.darts.length > old.darts.length) {
      _enter.forward(from: 0);
    }
    _syncPulse();
  }

  @override
  void dispose() {
    _enter.dispose();
    _pulse.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- Standbild
  //
  // Impeller merkt sich gezeichnete Ebenen nicht als Bild: Jede Scheibe mit ihren vielen
  // Unschärfe-Effekten würde beim Scrollen in jedem Bild neu berechnet (Ruckeln bei mehreren
  // Trefferbildern). Ruhende Scheiben (ohne Darts, Ziele und Animation) werden daher einmal
  // in ein Bild gerendert und nur noch dieses gezeichnet.

  static final _cache = <String, ui.Image>{}; // Einfügereihenfolge = zuletzt benutzt hinten
  static const _cacheMax = 24;

  ui.Image? _still;
  String? _stillKey;

  bool get _isStatic => widget.darts.isEmpty && widget.targets.isEmpty;

  String _keyFor(double dpr) {
    final h = widget.heat;
    final heat = h == null ? '' : (h.entries.map((e) => '${e.key}:${e.value}').toList()..sort()).join(',');
    return '${widget.size}|$dpr|${widget.color.toARGB32()}|${widget.showNumbers}|${widget.showCounts}|$heat';
  }

  DartboardPainter _painter() => DartboardPainter(
        darts: widget.darts,
        color: widget.color,
        targets: widget.targets,
        heat: widget.heat,
        enterT: Curves.easeOutBack.transform(_enter.value.clamp(0, 1)),
        pulse: Curves.easeInOut.transform(_pulse.value),
        showNumbers: widget.showNumbers,
        showCounts: widget.showCounts,
      );

  /// Liefert das fertige Standbild oder stößt das Rendern an (bis dahin wird live gezeichnet).
  ui.Image? _stillImage(double dpr) {
    final key = _keyFor(dpr);
    if (_stillKey == key && _still != null) return _still;
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit; // zuletzt benutzt ans Ende
      _still = hit;
      _stillKey = key;
      return hit;
    }
    if (_stillKey != key) {
      _stillKey = key;
      _still = null;
      final painter = _painter();
      final px = (widget.size * dpr).ceil();
      if (px <= 0) return null;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec);
        canvas.scale(dpr);
        painter.paint(canvas, Size.square(widget.size));
        final img = await rec.endRecording().toImage(px, px);
        _cache[key] = img;
        while (_cache.length > _cacheMax) {
          _cache.remove(_cache.keys.first);
        }
        if (mounted && _stillKey == key) setState(() => _still = img);
      });
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isStatic) {
      final img = _stillImage(MediaQuery.devicePixelRatioOf(context));
      if (img != null) {
        return RawImage(image: img, width: widget.size, height: widget.size, filterQuality: FilterQuality.medium);
      }
      return RepaintBoundary(child: CustomPaint(size: Size.square(widget.size), painter: _painter()));
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_enter, _pulse]),
        builder: (_, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: DartboardPainter(
            darts: widget.darts,
            color: widget.color,
            targets: widget.targets,
            heat: widget.heat,
            enterT: Curves.easeOutBack.transform(_enter.value.clamp(0, 1)),
            pulse: Curves.easeInOut.transform(_pulse.value),
            showNumbers: widget.showNumbers,
            showCounts: widget.showCounts,
          ),
        ),
      ),
    );
  }
}

class DartboardPainter extends CustomPainter {
  DartboardPainter({
    required this.darts,
    required this.color,
    required this.targets,
    required this.heat,
    required this.enterT,
    required this.pulse,
    required this.showNumbers,
    this.showCounts = false,
  });

  final List<Dart> darts;
  final Color color;
  final List<Target> targets;
  final Map<String, int>? heat;
  final double enterT;
  final double pulse;
  final bool showNumbers;
  final bool showCounts;

  late Offset c;
  late double rb; // äußerer Radius inkl. Zahlenring
  late double r; // Radius Double-Ring außen

  Offset _p(double radius, double ang) => c + Offset(cos(ang), sin(ang)) * radius;

  Path _sector(double r1, double r2, double a0, double a1) {
    final sweep = a1 - a0;
    return Path()
      ..moveTo(_p(r1 * r, a0).dx, _p(r1 * r, a0).dy)
      ..lineTo(_p(r2 * r, a0).dx, _p(r2 * r, a0).dy)
      ..arcTo(Rect.fromCircle(center: c, radius: r2 * r), a0, sweep, false)
      ..lineTo(_p(r1 * r, a1).dx, _p(r1 * r, a1).dy)
      ..arcTo(Rect.fromCircle(center: c, radius: r1 * r), a1, -sweep, false)
      ..close();
  }

  Path _ring(double r1, double r2) => Path()
    ..fillType = PathFillType.evenOdd
    ..addOval(Rect.fromCircle(center: c, radius: r2 * r))
    ..addOval(Rect.fromCircle(center: c, radius: r1 * r));

  Path _disc(double r1) => Path()..addOval(Rect.fromCircle(center: c, radius: r1 * r));

  /// Fläche eines Feldes; [inner] nur für Singles relevant.
  List<Path> _areas(int field, int? mult, {bool? inner}) {
    if (field == 25) {
      if (mult == 2) return [_disc(_bullIn)];
      if (mult == 1) return [_ring(_bullIn, _bullOut)];
      return [_disc(_bullOut)];
    }
    final out = <Path>[];
    final ks = field == -1 ? List.generate(20, (i) => i) : [_order.indexOf(field)];
    for (final k in ks) {
      if (k < 0) continue;
      final a0 = _center(k) - _rad(9), a1 = _center(k) + _rad(9);
      if (mult == null || mult == 1) {
        if (inner != false) out.add(_sector(_bullOut, _triIn, a0, a1));
        if (inner != true) out.add(_sector(_triOut, _dblIn, a0, a1));
      }
      if (mult == null || mult == 3) out.add(_sector(_triIn, _triOut, a0, a1));
      if (mult == null || mult == 2) out.add(_sector(_dblIn, 1, a0, a1));
    }
    if (field == -1 && mult == 2) out.add(_disc(_bullIn));
    return out;
  }

  Offset dartPos(Dart d) {
    double ang, rr;
    if (d.isMiss) {
      ang = d.jitterA * pi;
      rr = 1.04 + 0.1 * d.jitterR;
    } else if (d.isBull) {
      ang = d.jitterA * pi;
      rr = d.mult == 2 ? _bullIn * 0.8 * d.jitterR : _lerp(_bullIn + 0.012, _bullOut - 0.012, d.jitterR);
    } else {
      final k = _order.indexOf(d.field);
      ang = _center(k) + d.jitterA * _rad(7);
      rr = switch (d.mult) {
        3 => _lerp(_triIn + 0.012, _triOut - 0.012, d.jitterR),
        2 => _lerp(_dblIn + 0.012, 1 - 0.012, d.jitterR),
        _ => d.inner
            ? _lerp(_bullOut + 0.06, _triIn - 0.05, d.jitterR)
            : _lerp(_triOut + 0.04, _dblIn - 0.04, d.jitterR),
      };
    }
    return _p(rr * r, ang);
  }

  @override
  void paint(Canvas canvas, Size size) {
    c = size.center(Offset.zero);
    rb = size.width / 2;
    r = rb / 1.2;

    // ---- Hintergrund ----
    canvas.drawCircle(
      c,
      rb,
      Paint()
        ..shader = const RadialGradient(colors: [Color(0xFF1C1F25), Color(0xFF0A0B0D)])
            .createShader(Rect.fromCircle(center: c, radius: rb)),
    );
    canvas.drawCircle(
        c, rb - 0.5, Paint()..style = PaintingStyle.stroke..color = const Color(0xFF2A2E35)..strokeWidth = 1);

    // Glühender Rand in Spielerfarbe
    canvas.drawCircle(
      c,
      r * 1.01,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05
        ..color = color.withValues(alpha: 0.28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.06),
    );

    // ---- Segmente ----
    const singleA = Color(0xFF15171B);
    const singleB = Color(0xFF30343B);
    const red = Color(0xFFAE3A40);
    const green = Color(0xFF23855A);
    final fill = Paint();
    for (var k = 0; k < 20; k++) {
      final even = k.isEven;
      final a0 = _center(k) - _rad(9), a1 = _center(k) + _rad(9);
      fill.color = even ? singleA : singleB;
      canvas.drawPath(_sector(_bullOut, _triIn, a0, a1), fill);
      canvas.drawPath(_sector(_triOut, _dblIn, a0, a1), fill);
      fill.color = even ? red : green;
      canvas.drawPath(_sector(_triIn, _triOut, a0, a1), fill);
      canvas.drawPath(_sector(_dblIn, 1, a0, a1), fill);
    }
    canvas.drawPath(_ring(_bullIn, _bullOut), fill..color = green);
    canvas.drawPath(_disc(_bullIn), fill..color = red);

    // ---- Heatmap (Statistik) ----
    final h = heat;
    if (h != null && h.isNotEmpty) {
      final maxV = h.entries.where((e) => e.key != 'Miss').fold<int>(1, (a, e) => max(a, e.value));
      h.forEach((key, v) {
        if (key == 'Miss' || v == 0) return;
        final t = v / maxV;
        final paint = Paint()..color = color.withValues(alpha: 0.12 + 0.78 * t);
        final List<Path> areas;
        if (key == '25') {
          areas = _areas(25, 1);
        } else if (key == '50') {
          areas = _areas(25, 2);
        } else {
          final m = key[0] == 'T' ? 3 : key[0] == 'D' ? 2 : 1;
          areas = _areas(int.parse(key.substring(1)), m);
        }
        for (final a in areas) {
          canvas.drawPath(a, paint);
        }
      });
    }

    // ---- Schattierung: Tiefe + Glanz ----
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.35)],
          stops: const [0.55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: 0.07), Colors.transparent],
          stops: const [0, 0.55],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // ---- Ziele (Training) ----
    for (final t in targets) {
      final areas = _areas(t.field, t.mult);
      final glow = Paint()
        ..color = Colors.white.withValues(alpha: 0.10 + 0.25 * pulse)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.03);
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, r * 0.012)
        ..color = Colors.white.withValues(alpha: 0.45 + 0.45 * pulse);
      for (final a in areas) {
        canvas.drawPath(a, glow);
        canvas.drawPath(a, stroke);
      }
    }

    // ---- Getroffene Felder leuchten ----
    for (var i = 0; i < darts.length; i++) {
      final d = darts[i];
      if (d.isMiss) continue;
      final isNew = i == darts.length - 1;
      final boost = isNew ? (1 - enterT).clamp(0.0, 1.0) * 0.5 : 0.0;
      final areas = _areas(d.field, d.mult, inner: d.inner);
      for (final a in areas) {
        canvas.drawPath(
          a,
          Paint()
            ..color = color.withValues(alpha: 0.55 + boost)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.05),
        );
        canvas.drawPath(a, Paint()..color = color.withValues(alpha: 0.45));
      }
    }

    // ---- Drähte (leichte Lichtlinien) ----
    final wireW = max(0.6, r * 0.007);
    final wireGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = wireW * 3
      ..color = const Color(0xFFDDE6F0).withValues(alpha: 0.08)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, wireW * 1.5);
    final wire = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = wireW
      ..color = const Color(0xFFDDE6F0).withValues(alpha: 0.30);
    for (final rr in [_bullIn, _bullOut, _triIn, _triOut, _dblIn, 1.0]) {
      canvas.drawCircle(c, rr * r, wireGlow);
      canvas.drawCircle(c, rr * r, wire);
    }
    for (var k = 0; k < 20; k++) {
      final a = _center(k) - _rad(9);
      final p1 = _p(_bullOut * r, a), p2 = _p(r, a);
      canvas.drawLine(p1, p2, wireGlow);
      canvas.drawLine(p1, p2, wire);
    }

    // ---- Zahlenring ----
    if (showNumbers) {
      final hitNums = darts.where((d) => !d.isMiss && !d.isBull).map((d) => d.field).toSet();
      final targetNums = targets.where((t) => t.field > 0 && t.field != 25).map((t) => t.field).toSet();
      final fs = rb * 0.095;
      for (var k = 0; k < 20; k++) {
        final num = _order[k];
        final col = hitNums.contains(num)
            ? color
            : targetNums.contains(num)
                ? Colors.white
                : const Color(0xFF8D959E);
        final tp = TextPainter(
          text: TextSpan(
            text: '$num',
            style: TextStyle(
              color: col,
              fontSize: fs,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final pos = _p(r * 1.1, _center(k));
        tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
      }
    }

    // ---- Mini-Darts ----
    for (var i = 0; i < darts.length; i++) {
      final isNew = i == darts.length - 1;
      _drawDart(canvas, darts[i], isNew ? enterT : 1);
    }

    // ---- Trefferzahlen ----
    if (showCounts && h != null) _drawCounts(canvas, h);
  }

  void _drawCounts(Canvas canvas, Map<String, int> h) {
    final badgeR = max(7.5, r * 0.062);
    final fill = Paint()..color = const Color(0xF00B0C0E);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.2, badgeR * 0.16)
      ..color = color;
    h.forEach((key, v) {
      if (key == 'Miss' || v <= 0) return;
      Offset pos;
      if (key == '50') {
        pos = c;
      } else if (key == '25') {
        pos = _p((_bullIn + _bullOut) / 2 * r + badgeR * 0.9, _rad(45));
      } else {
        final num = int.parse(key.substring(1));
        final k = _order.indexOf(num);
        final rr = switch (key[0]) {
          'T' => (_triIn + _triOut) / 2,
          'D' => (_dblIn + 1) / 2,
          _ => (_triOut + _dblIn) / 2,
        };
        pos = _p(rr * r, _center(k));
      }
      canvas.drawCircle(pos, badgeR, fill);
      canvas.drawCircle(pos, badgeR, ring);
      final tp = TextPainter(
        text: TextSpan(
          text: '$v',
          style: TextStyle(
            color: Colors.white,
            fontSize: badgeR * (v >= 100 ? 0.8 : 1.05),
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    });
  }

  void _drawDart(Canvas canvas, Dart d, double t) {
    final pos = dartPos(d);
    final s = r / 80;
    final k = (1 - t).clamp(-0.3, 1.0);
    canvas.save();
    canvas.translate(pos.dx + 14 * s * k, pos.dy - 22 * s * k);
    canvas.rotate(_rad(d.tilt));
    canvas.scale(s * (1 + 0.45 * k));

    final alpha = t.clamp(0.0, 1.0);

    // Schatten
    canvas.drawLine(
      const Offset(2.5, 2.5),
      const Offset(7, -33),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55 * alpha)
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    // Einschlagloch
    canvas.drawCircle(Offset.zero, 1.6, Paint()..color = const Color(0xFF050506));
    // Spitze
    canvas.drawLine(
        Offset.zero,
        const Offset(0, -6),
        Paint()
          ..color = const Color(0xFF8A9098)
          ..strokeWidth = 1.3
          ..strokeCap = StrokeCap.round);
    // Barrel (metallisch)
    final barrel = Path()
      ..moveTo(-2, -6)
      ..lineTo(2, -6)
      ..lineTo(1.6, -18)
      ..lineTo(-1.6, -18)
      ..close();
    canvas.drawPath(
      barrel,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF7E848C), Color(0xFFF1F4F7), Color(0xFF9097A0), Color(0xFF5F656D)],
          stops: [0, 0.4, 0.7, 1],
        ).createShader(const Rect.fromLTRB(-2, -18, 2, -6)),
    );
    final grip = Paint()
      ..color = const Color(0xFF4F555D)
      ..strokeWidth = 0.6;
    for (final y in [-9.0, -11.5, -14.0, -16.0]) {
      canvas.drawLine(Offset(-1.8, y), Offset(1.8, y), grip);
    }
    // Schaft
    canvas.drawLine(
        const Offset(0, -18),
        const Offset(0, -26),
        Paint()
          ..color = const Color(0xFF23262B)
          ..strokeWidth = 1.9);
    // Flight in Spielerfarbe
    final flight = Path()
      ..moveTo(0, -24)
      ..lineTo(-6.8, -32)
      ..lineTo(-5.8, -39.5)
      ..lineTo(0, -35.5)
      ..lineTo(5.8, -39.5)
      ..lineTo(6.8, -32)
      ..close();
    final hsl = HSLColor.fromColor(color);
    canvas.drawPath(
      flight,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            hsl.withLightness((hsl.lightness - 0.18).clamp(0, 1)).toColor(),
            color,
            hsl.withLightness((hsl.lightness + 0.12).clamp(0, 1)).toColor(),
          ],
        ).createShader(const Rect.fromLTRB(-7, -40, 7, -24)),
    );
    canvas.drawPath(
        flight,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFF0B0C0E));
    canvas.drawLine(
        const Offset(0, -24.5),
        const Offset(0, -36),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.4)
          ..strokeWidth = 0.8);
    canvas.restore();
  }

  @override
  bool shouldRepaint(DartboardPainter old) => true;
}

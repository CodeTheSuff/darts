// Erzeugt alle Icon- und Logo-Bilder aus darts_logo_paket/darts_icon_eis_2000.jpg (2048², Version 3.0.0):
//   flutter test screens_test/icon_test.dart
// danach: dart run flutter_launcher_icons && dart run flutter_native_splash:create
//
// Stil: eisblauer Pfeil auf gebürstetem Metall im Frost-Rahmen; Rahmen ganz am Rand (iPhone/Web/Logo),
// auf Android an die Samsung-Iconform (Squircle) angepasst.
// (Vorheriges Neon-Logo: darts_logo_paket/darts_icon_1024.png)
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _src = 'darts_logo_paket/darts_icon_eis_2000.jpg';

/// Hintergrund des Originals (Ecken) – für adaptive/maskable Icons.
const _bg = Color(0xFF1E2430);

/// Außenkante des Frost-Rahmens (gemessen, ohne Leuchten) – „Rahmen ganz am Rand“ (3.0.0, Simon).
const _edge = Rect.fromLTRB(165, 165, 1883, 1883);

/// Eckradius des Rahmens relativ zur Kantenlänge.
const _edgeRound = 0.24;

/// Innenfläche (Metall) ohne Rahmen – hier wird der Pfeil freigestellt.
const _panel = Rect.fromLTRB(262, 262, 1786, 1786);

/// Abgerundete Maske knapp innerhalb des Rahmens (ohne dessen Leuchten an den Ecken).
final _inner = RRect.fromRectAndRadius(_panel.deflate(42), const Radius.circular(190));

Future<ui.Image> _load(WidgetTester t, String path) async {
  final bytes = File(path).readAsBytesSync();
  return (await t.runAsync(() async {
    final codec = await ui.instantiateImageCodec(bytes);
    return (await codec.getNextFrame()).image;
  }))!;
}

Future<ui.Image> _fromRaw(WidgetTester t, Uint8List px, int w, int h) async => (await t.runAsync(() async {
      final buf = await ui.ImmutableBuffer.fromUint8List(px);
      final desc = ui.ImageDescriptor.raw(buf, width: w, height: h, pixelFormat: ui.PixelFormat.rgba8888);
      return (await (await desc.instantiateCodec()).getNextFrame()).image;
    }))!;

/// Pfeil freistellen: Alpha aus der Helligkeit über dem dunklen Metall (nur Innenfläche),
/// danach auf seine Begrenzung zugeschnitten und quadratisch zentriert.
Future<(ui.Image, Rect)> _dart(WidgetTester t, ui.Image src) async {
  final data = (await t.runAsync(() => src.toByteData(format: ui.ImageByteFormat.rawStraightRgba)))!;
  final px = data.buffer.asUint8List();
  final w = src.width, h = src.height;
  final out = Uint8List(px.length);
  var x0 = w, x1 = 0, y0 = h, y1 = 0;
  for (var y = _panel.top.toInt(); y < _panel.bottom; y++) {
    for (var x = _panel.left.toInt(); x < _panel.right; x++) {
      if (!_inner.contains(Offset(x.toDouble(), y.toDouble()))) continue;
      final i = (y * w + x) * 4;
      final r = px[i], g = px[i + 1], b = px[i + 2];
      final l = (r * 3 + g * 6 + b) / 10;
      final a = ((l - 66) * 255 / 95).clamp(0, 255).round();
      if (a <= 3) continue;
      // vormultipliziert (Flutter-Rohformat)
      out[i] = (r * a / 255).round();
      out[i + 1] = (g * a / 255).round();
      out[i + 2] = (b * a / 255).round();
      out[i + 3] = a;
      if (a > 40) {
        x0 = min(x0, x);
        x1 = max(x1, x);
        y0 = min(y0, y);
        y1 = max(y1, y);
      }
    }
  }
  final img = await _fromRaw(t, out, w, h);
  // quadratische Begrenzung um den Pfeil
  final side = max(x1 - x0, y1 - y0) * 1.06;
  final c = Offset((x0 + x1) / 2, (y0 + y1) / 2);
  return (img, Rect.fromCenter(center: c, width: side, height: side));
}

// Samsung One UI / AOSP "Squircle" (Standard-Iconform auf Samsung):
// M50,0 C10,0 0,10 0,50 0,90 10,100 50,100 C90,100 100,90 100,50 C100,10 90,0 50,0 Z
Path _squircle(Rect r) {
  final k = r.width / 100;
  Offset p(double x, double y) => r.topLeft + Offset(x * k, y * k);
  final a = p(50, 0);
  final path = Path()..moveTo(a.dx, a.dy);
  void cub(List<double> v) {
    final c1 = p(v[0], v[1]), c2 = p(v[2], v[3]), e = p(v[4], v[5]);
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, e.dx, e.dy);
  }

  cub([10, 0, 0, 10, 0, 50]);
  cub([0, 90, 10, 100, 50, 100]);
  cub([90, 100, 100, 90, 100, 50]);
  cub([100, 10, 90, 0, 50, 0]);
  return path..close();
}

/// Android-Vordergrund (n²): Der sichtbare Bereich (mittlere 2/3) zeigt den Rahmen so gebogen,
/// dass seine Außenkante genau der Squircle-Maske folgt. Pfeil und Metallfläche bleiben unverändert,
/// nur der Randbereich wird radial angepasst (an den Ecken um höchstens ~7 %).
Future<ui.Image> _warpToSquircle(WidgetTester t, ui.Image src, {int n = 1024}) async {
  final data = (await t.runAsync(() => src.toByteData(format: ui.ImageByteFormat.rawStraightRgba)))!;
  final sp = data.buffer.asUint8List();
  final w = src.width, h = src.height;
  final half = n / 3;
  const steps = 2880;
  // Randabstand der Maske je Winkel (Halbbreite = 1)
  final m = _squircle(const Rect.fromLTWH(-1000, -1000, 2000, 2000));
  final bm = List<double>.filled(steps + 1, 1);
  for (var k = 0; k <= steps; k++) {
    final a = k / steps * 2 * pi;
    var lo = 0.5, hi = 1.6;
    for (var i = 0; i < 30; i++) {
      final mid = (lo + hi) / 2;
      if (m.contains(Offset(cos(a) * mid * 1000, sin(a) * mid * 1000))) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    bm[k] = lo;
  }
  // Randabstand des Rahmens: im Original gemessen (äußerster heller Punkt je Winkel), geglättet
  final cx = _edge.center.dx, cy = _edge.center.dy, hs = _edge.width / 2;
  int lum(int x, int y) {
    final i = (y * w + x) * 4;
    return (sp[i] * 3 + sp[i + 1] * 6 + sp[i + 2]) ~/ 10;
  }

  final raw = List<double>.filled(steps + 1, 1);
  for (var k = 0; k <= steps; k++) {
    final a = k / steps * 2 * pi;
    var last = 1.0;
    for (var r = 0.85; r < 1.5; r += 0.001) {
      final x = (cx + cos(a) * r * hs).round(), y = (cy + sin(a) * r * hs).round();
      if (x < 0 || y < 0 || x >= w || y >= h) break;
      if (lum(x, y) > 150) last = r;
    }
    raw[k] = last;
  }
  final bf = List<double>.filled(steps + 1, 1);
  const win = 12;
  for (var k = 0; k <= steps; k++) {
    var sum = 0.0;
    for (var d = -win; d <= win; d++) {
      sum += raw[(k + d) % steps];
    }
    bf[k] = sum / (2 * win + 1);
  }

  const f = 0.125, band = 0.32; // Rahmenbreite, Übergangszone (normiert)
  final out = Uint8List(n * n * 4);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final ux = (x + 0.5 - n / 2) / half, uy = (y + 0.5 - n / 2) / half;
      final rho = sqrt(ux * ux + uy * uy);
      var a = atan2(uy, ux);
      if (a < 0) a += 2 * pi;
      final idx = (a / (2 * pi) * steps).round();
      final bM = bm[idx], bF = bf[idx];
      double rs;
      if (rho <= bM - band) {
        rs = rho;
      } else if (rho <= bM - f) {
        rs = (bM - band) + (rho - (bM - band)) * ((bF - f) - (bM - band)) / (band - f);
      } else {
        rs = bF + (rho - bM);
      }
      final k = rho == 0 ? 0.0 : rs / rho;
      final sx = cx + ux * k * hs, sy = cy + uy * k * hs;
      final x0 = sx.floor().clamp(0, w - 2), y0 = sy.floor().clamp(0, h - 2);
      final fx = (sx - x0).clamp(0.0, 1.0), fy = (sy - y0).clamp(0.0, 1.0);
      final o = (y * n + x) * 4;
      for (var ch = 0; ch < 3; ch++) {
        final i00 = (y0 * w + x0) * 4 + ch;
        final v = sp[i00] * (1 - fx) * (1 - fy) +
            sp[i00 + 4] * fx * (1 - fy) +
            sp[i00 + w * 4] * (1 - fx) * fy +
            sp[i00 + w * 4 + 4] * fx * fy;
        out[o + ch] = v.round();
      }
      out[o + 3] = 255;
    }
  }
  return _fromRaw(t, out, n, n);
}

/// Zeichnet [area] des Bildes zentriert mit Anteil [fill] in ein Quadrat [size].
/// [bg] füllt vorher die Fläche, [round] schneidet auf ein abgerundetes Quadrat (Anteil des Radius).
Future<void> _render(WidgetTester t, String path, ui.Image img, Rect area,
    {required int size, double fill = 1, Color? bg, double? round}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final s = size.toDouble();
  final r = Rect.fromLTWH(0, 0, s, s);
  if (bg != null) canvas.drawRect(r, Paint()..color = bg);
  final dst = Rect.fromCenter(center: r.center, width: s * fill, height: s * fill);
  if (round != null) {
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(dst, Radius.circular(dst.width * round)));
  }
  canvas.drawImageRect(img, area, dst, Paint()..filterQuality = FilterQuality.high);
  if (round != null) canvas.restore();
  final out = await t.runAsync(() => rec.endRecording().toImage(size, size));
  final png = await t.runAsync(() => out!.toByteData(format: ui.ImageByteFormat.png));
  File(path).parent.createSync(recursive: true);
  File(path).writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  testWidgets('Icons und Logo erzeugen (Eis-Logo)', (t) async {
    final src = await _load(t, _src);
    final full = Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble());
    final (dart, dartBox) = await _dart(t, src);

    // ---- Android
    // Klassisches Icon (vor Android 8): Rahmen ganz am Rand, Ecken frei
    await _render(t, 'assets/icon/icon.png', src, _edge, size: 1024, round: _edgeRound);
    // Adaptiv: Hintergrund einfarbig, Vordergrund mit Rahmen auf die Samsung-Form gebogen
    await _render(t, 'assets/icon/background.png', src, full, size: 1024, fill: 0, bg: _bg);
    final fg = await _warpToSquircle(t, src);
    await _render(t, 'assets/icon/foreground.png', fg, const Rect.fromLTWH(0, 0, 1024, 1024), size: 1024);
    // Startbildschirm (Android 12 zeigt das Bild in einem Kreis von 2/3): nur der Rahmen, Ecken frei
    await _render(t, 'assets/icon/splash.png', src, _edge, size: 768, fill: 0.46, round: _edgeRound);

    // ---- In der App
    // Logo (wird in der App abgerundet zugeschnitten): Rahmen ganz am Rand
    await _render(t, 'assets/logo/logo.png', src, _edge, size: 512, round: _edgeRound);
    // Nur der Pfeil, freigestellt (Wasserzeichen, Wartebildschirm der Anzeige)
    await _render(t, 'assets/logo/mark.png', dart, dartBox, size: 512);

    // ---- Web / iPhone
    await _render(t, 'web/icons/Icon-192.png', src, _edge, size: 192, round: _edgeRound);
    await _render(t, 'web/icons/Icon-512.png', src, _edge, size: 512, round: _edgeRound);
    // maskable (Android-Chrome/Samsung Internet): wie das Android-Icon – sichtbarer Teil des Vordergrunds
    const visible = Rect.fromLTWH(1024 / 6, 1024 / 6, 1024 * 2 / 3, 1024 * 2 / 3);
    await _render(t, 'web/icons/Icon-maskable-192.png', fg, visible, size: 192);
    await _render(t, 'web/icons/Icon-maskable-512.png', fg, visible, size: 512);
    // iOS rundet selbst ab (Radius ≈ 22 %) – Rahmen ganz am Rand, Ecken dunkel gefüllt (iOS braucht deckend)
    await _render(t, 'web/icons/apple-touch-icon.png', src, _edge, size: 180, bg: _bg);
    await _render(t, 'web/favicon.png', src, _edge, size: 32, round: _edgeRound);
    // Ladebildschirm der Web-App
    await _render(t, 'web/icons/splash.png', src, _edge, size: 288, round: _edgeRound);
  });
}

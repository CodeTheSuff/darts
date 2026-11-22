// Erzeugt alle Icon- und Logo-Bilder aus darts_logo_paket/darts_icon_eis_2000.jpg (2048², Version 3.0.0):
//   flutter test screens_test/icon_test.dart
// danach: dart run flutter_launcher_icons && dart run flutter_native_splash:create
//
// Stil: eisblauer Pfeil auf gebürstetem Metall im Frost-Rahmen, dunkler Hintergrund.
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

/// Frost-Rahmen samt etwas Leuchten (im 2048er-Original).
const _frame = Rect.fromLTRB(150, 150, 1898, 1898);

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
    // Klassisches Icon: komplettes Bild
    await _render(t, 'assets/icon/icon.png', src, full, size: 1024);
    // Adaptiv: Hintergrund einfarbig wie das Original, Vordergrund = ganzes Bild so klein,
    // dass der Rahmen in der sichtbaren Zone (≈ 66 %) liegt.
    await _render(t, 'assets/icon/background.png', src, full, size: 1024, fill: 0, bg: _bg);
    await _render(t, 'assets/icon/foreground.png', src, full, size: 1024, fill: 0.76);
    // Startbildschirm (Android 12 zeigt das Bild in einem Kreis von 2/3): nur der Rahmen, Ecken frei
    await _render(t, 'assets/icon/splash.png', src, _frame, size: 768, fill: 0.46, round: 0.17);

    // ---- In der App
    // Logo (wird in der App rund zugeschnitten): Rahmen mit etwas dunklem Rand
    await _render(t, 'assets/logo/logo.png', src, _frame.inflate(40), size: 512);
    // Nur der Pfeil, freigestellt (Wasserzeichen, Wartebildschirm der Anzeige)
    await _render(t, 'assets/logo/mark.png', dart, dartBox, size: 512);

    // ---- Web / iPhone
    await _render(t, 'web/icons/Icon-192.png', src, full, size: 192);
    await _render(t, 'web/icons/Icon-512.png', src, full, size: 512);
    // maskable: sichere Zone = Kreis mit 80 % Durchmesser → Rahmen klein genug
    await _render(t, 'web/icons/Icon-maskable-192.png', src, full, size: 192, fill: 0.66, bg: _bg);
    await _render(t, 'web/icons/Icon-maskable-512.png', src, full, size: 512, fill: 0.66, bg: _bg);
    // iOS rundet selbst ab – komplettes Bild
    await _render(t, 'web/icons/apple-touch-icon.png', src, full, size: 180);
    await _render(t, 'web/favicon.png', src, _frame, size: 32);
    // Ladebildschirm der Web-App: Rahmen, Ecken frei
    await _render(t, 'web/icons/splash.png', src, _frame, size: 288, round: 0.17);
  });
}

// Erzeugt die Icon- und Logo-Bilder aus darts_logo_paket/darts_icon_1024.png:
//   flutter test screens_test/icon_test.dart
// danach: dart run flutter_launcher_icons && dart run flutter_native_splash:create
//
// Stil: Pfeil in kräftigen Neon-Farben mit orangem Leuchten auf Anthrazit-Verlauf.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Pfeil im Original (1024²): Begrenzung etwa x 278–845, y 178–745.
const _arrow = Rect.fromLTRB(278, 178, 845, 745);
const _bgTop = Color(0xFF2A2D36);
const _bgBottom = Color(0xFF0E0F13);
const _glow = Color(0xFFFF7A3C);

Future<ui.Image> _load(WidgetTester t, String path) async {
  final bytes = File(path).readAsBytesSync();
  return (await t.runAsync(() async {
    final codec = await ui.instantiateImageCodec(bytes);
    return (await codec.getNextFrame()).image;
  }))!;
}

/// Pfeil deckend freistellen, Farben kräftiger und etwas heller (Neon).
Future<ui.Image> _neon(WidgetTester t, ui.Image src, {double boost = 0.35}) async {
  final data = (await t.runAsync(() => src.toByteData(format: ui.ImageByteFormat.rawStraightRgba)))!;
  final px = data.buffer.asUint8List();
  final out = Uint8List(px.length);
  for (var i = 0; i < px.length; i += 4) {
    var r = px[i].toDouble(), g = px[i + 1].toDouble(), b = px[i + 2].toDouble();
    final a = ((255 - min(r, min(g, b))) * 4).clamp(0, 255).toDouble();
    if (a <= 2) continue;
    final l = (r + g + b) / 3;
    r = (l + (r - l) * (1 + boost) + 18 * boost).clamp(0, 255);
    g = (l + (g - l) * (1 + boost) + 18 * boost).clamp(0, 255);
    b = (l + (b - l) * (1 + boost) + 18 * boost).clamp(0, 255);
    // vormultipliziert (Flutter-Rohformat)
    out[i] = (r * a / 255).round();
    out[i + 1] = (g * a / 255).round();
    out[i + 2] = (b * a / 255).round();
    out[i + 3] = a.round();
  }
  return (await t.runAsync(() async {
    final buf = await ui.ImmutableBuffer.fromUint8List(out);
    final desc = ui.ImageDescriptor.raw(buf, width: src.width, height: src.height, pixelFormat: ui.PixelFormat.rgba8888);
    return (await (await desc.instantiateCodec()).getNextFrame()).image;
  }))!;
}

/// Zeichnet: optional Hintergrund-Verlauf, optional Leuchten, Pfeil zentriert mit Anteil [fill].
Future<void> _render(WidgetTester t, String path, ui.Image arrow,
    {required double fill, bool bg = false, bool glow = true, int size = 1024}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final s = size.toDouble();
  final r = Rect.fromLTWH(0, 0, s, s);
  if (bg) {
    canvas.drawRect(
        r,
        Paint()
          ..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_bgTop, _bgBottom])
              .createShader(r));
  }
  final side = s * fill;
  if (glow && fill > 0) {
    final gr = side * 0.56;
    canvas.drawCircle(
        r.center,
        gr,
        Paint()
          ..shader = RadialGradient(colors: [_glow.withValues(alpha: 0.45), _glow.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: r.center, radius: gr)));
  }
  if (fill > 0) {
    canvas.drawImageRect(arrow, _arrow, Rect.fromCenter(center: r.center, width: side, height: side),
        Paint()..filterQuality = FilterQuality.high);
  }
  final img = await t.runAsync(() => rec.endRecording().toImage(size, size));
  final png = await t.runAsync(() => img!.toByteData(format: ui.ImageByteFormat.png));
  File(path).writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  testWidgets('Icons und Logo erzeugen', (t) async {
    final src = await _load(t, 'darts_logo_paket/darts_icon_1024.png');
    final neon = await _neon(t, src);
    Directory('assets/logo').createSync(recursive: true);
    // In der App: Anthrazit-Quadrat mit Leuchten, Pfeil groß
    await _render(t, 'assets/logo/logo.png', neon, fill: 0.74, bg: true, size: 512);
    // Nur der Pfeil, freigestellt (Wasserzeichen)
    await _render(t, 'assets/logo/mark.png', neon, fill: 1.0, glow: false, size: 512);
    // App-Icon (alt): Pfeil 78 % wie in der abgestimmten Vorschau
    await _render(t, 'assets/icon/icon.png', neon, fill: 0.78, bg: true);
    // Adaptives Icon: sichtbar ist die mittlere 66-%-Zone → 0,78 × 0,667 ≈ 0,52
    await _render(t, 'assets/icon/background.png', neon, fill: 0, bg: true);
    await _render(t, 'assets/icon/foreground.png', neon, fill: 0.52);
    // Startbildschirm (Android 12 zeigt das Bild in einem Kreis), Hintergrundfarbe Anthrazit
    await _render(t, 'assets/icon/splash.png', neon, fill: 0.60, size: 768);
  });
}

// Erzeugt die Icon- und Logo-Bilder aus darts_logo_paket/darts_icon_1024.png:
//   flutter test screens_test/icon_test.dart
// danach: dart run flutter_launcher_icons && dart run flutter_native_splash:create
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Pfeil im Original (1024²): Begrenzung etwa x 278–845, y 178–745.
const _arrow = Rect.fromLTRB(278, 178, 845, 745);

Future<ui.Image> _load(WidgetTester t, String path) async {
  final bytes = File(path).readAsBytesSync();
  return (await t.runAsync(() async {
    final codec = await ui.instantiateImageCodec(bytes);
    return (await codec.getNextFrame()).image;
  }))!;
}

/// Weiß wird durchsichtig; auf Weiß gelegt ergibt sich wieder genau das Original.
Future<ui.Image> _knockOutWhite(WidgetTester t, ui.Image src) async {
  final data = (await t.runAsync(() => src.toByteData(format: ui.ImageByteFormat.rawStraightRgba)))!;
  final px = data.buffer.asUint8List();
  final out = Uint8List(px.length);
  for (var i = 0; i < px.length; i += 4) {
    final r = px[i], g = px[i + 1], b = px[i + 2];
    final a = 255 - [r, g, b].reduce((x, y) => x < y ? x : y);
    if (a <= 2) continue;
    // Flutter erwartet hier vormultiplizierte Werte: Farbe × Deckkraft = c − (255 − a)
    int un(int c) => (c - (255 - a)).clamp(0, a);
    out[i] = un(r);
    out[i + 1] = un(g);
    out[i + 2] = un(b);
    out[i + 3] = a;
  }
  return (await t.runAsync(() async {
    final buf = await ui.ImmutableBuffer.fromUint8List(out);
    final desc = ui.ImageDescriptor.raw(buf, width: src.width, height: src.height, pixelFormat: ui.PixelFormat.rgba8888);
    final codec = await desc.instantiateCodec();
    return (await codec.getNextFrame()).image;
  }))!;
}

/// Zeichnet den Pfeil zentriert so, dass seine Begrenzung [fill] der Kantenlänge einnimmt.
Future<void> _render(WidgetTester t, String path, ui.Image src, {required double fill, Color? bg, int size = 1024}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final s = size.toDouble();
  if (bg != null) canvas.drawRect(Rect.fromLTWH(0, 0, s, s), Paint()..color = bg);
  final side = s * fill;
  final dst = Rect.fromCenter(center: Offset(s / 2, s / 2), width: side, height: side);
  canvas.drawImageRect(src, _arrow, dst, Paint()..filterQuality = FilterQuality.high);
  final img = await t.runAsync(() => rec.endRecording().toImage(size, size));
  final png = await t.runAsync(() => img!.toByteData(format: ui.ImageByteFormat.png));
  File(path).writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  testWidgets('Icons und Logo erzeugen', (t) async {
    final src = await _load(t, 'darts_logo_paket/darts_icon_1024.png');
    final mark = await _knockOutWhite(t, src);
    Directory('assets/logo').createSync(recursive: true);
    // In der App: weißes Quadrat, Pfeil groß
    await _render(t, 'assets/logo/logo.png', mark, fill: 0.74, bg: Colors.white, size: 512);
    // Freigestellt (Wasserzeichen)
    await _render(t, 'assets/logo/mark.png', mark, fill: 1.0, size: 512);
    // App-Icon (alt) und adaptives Icon (sichtbar ist nur die mittlere 66-%-Zone)
    await _render(t, 'assets/icon/icon.png', mark, fill: 0.70, bg: Colors.white);
    await _render(t, 'assets/icon/foreground.png', mark, fill: 0.50);
    // Startbildschirm (Android 12 zeigt das Bild in einem Kreis)
    await _render(t, 'assets/icon/splash.png', mark, fill: 0.55, size: 768);
  });
}

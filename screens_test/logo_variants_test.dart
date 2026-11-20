// Vorschau dunkler Logo-Varianten: flutter test screens_test/logo_variants_test.dart → build/logo_varianten.png
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'v4_screens_test.dart' show loadFonts;

const _arrow = Rect.fromLTRB(278, 178, 845, 745);

Future<ui.Image> _load(WidgetTester t, String path) async {
  final bytes = File(path).readAsBytesSync();
  return (await t.runAsync(() async {
    final codec = await ui.instantiateImageCodec(bytes);
    return (await codec.getNextFrame()).image;
  }))!;
}

/// Pfeil deckend freistellen (Originalfarben); [boost] hellt/sättigt die Farben auf.
Future<ui.Image> _solid(WidgetTester t, ui.Image src, {double boost = 0}) async {
  final data = (await t.runAsync(() => src.toByteData(format: ui.ImageByteFormat.rawStraightRgba)))!;
  final px = data.buffer.asUint8List();
  final out = Uint8List(px.length);
  for (var i = 0; i < px.length; i += 4) {
    var r = px[i].toDouble(), g = px[i + 1].toDouble(), b = px[i + 2].toDouble();
    final cover = 255 - min(r, min(g, b));
    final a = (cover * 4).clamp(0, 255).toDouble();
    if (a <= 2) continue;
    if (boost > 0) {
      // Sättigung anheben und etwas aufhellen
      final l = (r + g + b) / 3;
      r = (l + (r - l) * (1 + boost) + 18 * boost).clamp(0, 255);
      g = (l + (g - l) * (1 + boost) + 18 * boost).clamp(0, 255);
      b = (l + (b - l) * (1 + boost) + 18 * boost).clamp(0, 255);
    }
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

class _V {
  const _V(this.title, this.paintBg, this.img, {this.glow});
  final String title;
  final void Function(Canvas c, Rect r) paintBg;
  final ui.Image img;
  final Color? glow;
}

void main() {
  setUpAll(loadFonts);
  testWidgets('Logo-Varianten', (t) async {
    final src = await _load(t, 'darts_logo_paket/darts_icon_1024.png');
    final solid = await _solid(t, src);
    final neon = await _solid(t, src, boost: 0.35);

    void flat(Canvas c, Rect r, Color col) => c.drawRect(r, Paint()..color = col);
    void grad(Canvas c, Rect r, List<Color> cols) => c.drawRect(
        r, Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: cols).createShader(r));

    final variants = [
      _V('1  Dunkelgrau', (c, r) => flat(c, r, const Color(0xFF15171D)), solid),
      _V('2  Nachtblau', (c, r) => grad(c, r, const [Color(0xFF1E2550), Color(0xFF0A0D1F)]), solid),
      _V('3  Aubergine + Leuchten', (c, r) => grad(c, r, const [Color(0xFF34143F), Color(0xFF110818)]), solid,
          glow: const Color(0xFFE0407A)),
      _V('4  Schwarz + Neon-Farben', (c, r) => flat(c, r, const Color(0xFF07070A)), neon, glow: const Color(0xFFFF7A3C)),
      _V('5  Anthrazit-Verlauf + Neon', (c, r) => grad(c, r, const [Color(0xFF2A2D36), Color(0xFF0E0F13)]), neon),
      _V('6  Weiß (aktuell)', (c, r) => flat(c, r, Colors.white), src),
    ];

    const tile = 300.0, gap = 40.0, label = 56.0, cols = 3;
    final rows = (variants.length / cols).ceil();
    final w = cols * tile + (cols + 1) * gap;
    final h = rows * (tile + label) + (rows + 1) * gap;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF3A3F4A));
    for (var i = 0; i < variants.length; i++) {
      final v = variants[i];
      final x = gap + (i % cols) * (tile + gap);
      final y = gap + (i ~/ cols) * (tile + label + gap);
      final r = Rect.fromLTWH(x, y, tile, tile);
      c.save();
      // Form wie auf dem Samsung-Homebildschirm (abgerundetes Quadrat)
      c.clipRRect(RRect.fromRectAndRadius(r, const Radius.circular(tile * 0.30)));
      v.paintBg(c, r);
      if (v.glow != null) {
        c.drawCircle(r.center, tile * 0.42,
            Paint()..shader = RadialGradient(colors: [v.glow!.withValues(alpha: 0.45), v.glow!.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: r.center, radius: tile * 0.42)));
      }
      // Pfeil größer als bisher: 78 % der sichtbaren Fläche (bisher 75 %, Spitze bleibt frei)
      final side = tile * 0.78;
      final img = v.img;
      final srcRect = img == src ? _arrow : _arrow;
      c.drawImageRect(img, srcRect, Rect.fromCenter(center: r.center, width: side, height: side),
          Paint()..filterQuality = FilterQuality.high);
      c.restore();
      final tp = TextPainter(
        text: TextSpan(text: v.title, style: const TextStyle(fontFamily: 'Barlow', fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: tile + gap);
      tp.paint(c, Offset(x + (tile - tp.width) / 2, y + tile + 12));
    }
    final img = await t.runAsync(() => rec.endRecording().toImage(w.round(), h.round()));
    final png = await t.runAsync(() => img!.toByteData(format: ui.ImageByteFormat.png));
    File('build/logo_varianten.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

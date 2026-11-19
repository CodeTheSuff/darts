// Erzeugt die Icon-Quellbilder: flutter test screens_test/icon_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:darts_counter/ui/logo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> render(WidgetTester t, String path, CustomPainter painter, {Color? bg, int size = 1024}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  if (bg != null) canvas.drawRect(Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()), Paint()..color = bg);
  painter.paint(canvas, Size(size.toDouble(), size.toDouble()));
  final img = await t.runAsync(() => rec.endRecording().toImage(size, size));
  final data = await t.runAsync(() => img!.toByteData(format: ui.ImageByteFormat.png));
  File(path).writeAsBytesSync(data!.buffer.asUint8List());
}

class _Bg extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => paintLogoBackground(canvas, size);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void main() {
  testWidgets('Icons erzeugen', (t) async {
    await render(t, 'assets/icon/icon.png', const DartsLogoPainter());
    // Adaptive Icon: Motiv in der sicheren Zone (66 %), Hintergrund separat
    await render(t, 'assets/icon/foreground.png', const DartsLogoPainter(background: false, scale: 0.62));
    await render(t, 'assets/icon/background.png', _Bg());
    await render(t, 'assets/icon/splash.png', const DartsLogoPainter(background: false, scale: 0.9), size: 768);
  });
}

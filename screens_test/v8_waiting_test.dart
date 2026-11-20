// Bildschirmfoto des Wartebildschirms der Anzeige: flutter test screens_test/v8_waiting_test.dart
import 'package:darts_counter/ui/about_screen.dart';
import 'package:darts_counter/ui/display_waiting.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'v4_screens_test.dart' show loadFonts, shot, prep;

void main() {
  setUpAll(loadFonts);
  for (final size in const [Size(1280, 800), Size(800, 1280), Size(412, 915)]) {
    testWidgets('Wartebildschirm ${size.width.toInt()}x${size.height.toInt()}', (t) async {
      await prep(t, {'onboarded': true, 'seenVersion': appVersion}, size: size);
      await t.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(C.p),
        home: Builder(builder: (context) {
          return const Scaffold(body: DisplayWaiting());
        }),
      ));
      final ctx = t.element(find.byType(DisplayWaiting));
      await t.runAsync(() => precacheImage(const AssetImage('assets/logo/mark.png'), ctx));
      await t.pump(const Duration(milliseconds: 600));
      await shot(t, 'v8_waiting_${size.width.toInt()}x${size.height.toInt()}');
      await t.pumpWidget(const SizedBox());
    });
  }
}

import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/ui/about_screen.dart';
import 'package:darts_counter/ui/celebration.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'v4_screens_test.dart' show loadFonts, shot, prep;

void main() {
  setUpAll(loadFonts);
  testWidgets('180 mit Feuerwerk', (t) async {
    await prep(t, {'onboarded': true, 'seenVersion': appVersion});
    var done = false;
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(C.p),
      home: Scaffold(
        body: CelebrationOverlay(
          kind: CelebrationKind.max180,
          name: 'Simon',
          color: const Color(0xFF5AA9FF),
          darts: const [Dart(20, 3), Dart(20, 3), Dart(20, 3)],
          value: 180,
          onDone: () => done = true,
        ),
      ),
    ));
    var ms = 0;
    for (final at in [1300, 2600, 4200, 6000]) {
      while (ms < at) {
        await t.pump(const Duration(milliseconds: 50));
        ms += 50;
      }
      await shot(t, 'fw_180_$at');
    }
    while (!done && ms < 9000) {
      await t.pump(const Duration(milliseconds: 100));
      ms += 100;
    }
    expect(done, isTrue);
    expect(ms, inInclusiveRange(7300, 7700), reason: '180 dauert jetzt 7,4 s');
  });
}

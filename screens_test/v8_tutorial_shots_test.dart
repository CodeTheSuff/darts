// Bildschirmfotos des Tutorials: flutter test screens_test/v8_tutorial_shots_test.dart
import 'package:darts_counter/ui/about_screen.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:darts_counter/ui/tutorial/tutorial_content.dart';
import 'package:darts_counter/ui/tutorial/tutorial_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'v4_screens_test.dart' show loadFonts, shot, prep;

void main() {
  setUpAll(loadFonts);
  for (final size in const [Size(412, 915), Size(1280, 800)]) {
    final tag = size.width > 600 ? 'tab' : 'phone';
    testWidgets('Tutorial $tag', (t) async {
      await prep(t, {'onboarded': true, 'seenVersion': appVersion, 'tutorialSeen': ['start', 'x01']}, size: size);
      await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(C.p), home: const TutorialScreen()));
      await t.pump(const Duration(milliseconds: 300));
      await shot(t, 'v8_tut_${tag}_overview');
      final ch = buildTutorial();
      for (final (ci, pages) in [(0, [0, 3]), (2, [1, 4]), (3, [1, 3]), (4, [1]), (6, [3]), (7, [3]), (10, [2])]) {
        await t.pumpWidget(MaterialApp(
            debugShowCheckedModeBanner: false, theme: buildTheme(C.p), home: TutorialChapterScreen(key: ValueKey(ci), chapters: ch, index: ci)));
        await t.pump(const Duration(milliseconds: 300));
        var cur = 0;
        for (final p in pages) {
          while (cur < p) {
            if (find.text('Weiter').evaluate().isEmpty) {
              debugPrint('KEIN WEITER: ${ch[ci].id} Seite $cur von ${ch[ci].pages.length}');
              break;
            }
            await t.tap(find.text('Weiter'));
            await t.pump(const Duration(milliseconds: 400));
            cur++;
          }
          await shot(t, 'v8_tut_${tag}_${ch[ci].id}_$p');
        }
      }
      await t.pumpWidget(const SizedBox());
    });
  }
}

import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/games/catalog.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:darts_counter/ui/tutorial/tutorial_content.dart';
import 'package:darts_counter/ui/tutorial/tutorial_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _steps(WidgetTester t, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  test('Trainings- und Minispiel-Kapitel enthalten jeden Modus aus dem Katalog', () {
    final ch = buildTutorial();
    final titles = {for (final c in ch) for (final p in c.pages) p.title};
    for (final m in modes.where((m) => m.category != ModeCategory.game)) {
      expect(titles, contains(m.name), reason: '${m.name} fehlt im Tutorial');
    }
  });

  for (final size in const [Size(412, 915), Size(360, 740), Size(1280, 800)]) {
    testWidgets('Alle Tutorial-Seiten ohne Layoutfehler (${size.width.toInt()}×${size.height.toInt()})', (t) async {
      SharedPreferences.setMockInitialValues({'sound': false});
      await Store.init();
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buildTheme(C.p), home: const TutorialScreen()));
      await _steps(t);
      expect(find.text('Alles, was die App kann'), findsOneWidget);

      final chapters = buildTutorial();
      for (var i = 0; i < chapters.length; i++) {
        await t.pumpWidget(MaterialApp(
            theme: buildTheme(C.p), home: TutorialChapterScreen(chapters: chapters, index: i)));
        await _steps(t);
        for (var p = 0; p < chapters[i].pages.length; p++) {
          expect(find.text(chapters[i].pages[p].title), findsWidgets);
          expect(t.takeException(), isNull, reason: '${chapters[i].title}, Seite ${p + 1}');
          if (p < chapters[i].pages.length - 1) {
            await t.tap(find.text('Weiter'));
            await _steps(t, 3);
          }
        }
        // letzte Seite: Kapitel gilt als angesehen
        expect(Store.tutorialSeen, contains(chapters[i].id));
        await t.pumpWidget(const SizedBox());
      }
    });
  }
}

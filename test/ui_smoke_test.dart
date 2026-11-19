import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/main.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).first);
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  for (final size in const [Size(412, 915), Size(360, 740)]) {
    testWidgets('X01 und Cricket laufen ohne Layoutfehler (${size.width.toInt()}×${size.height.toInt()})',
        (tester) async {
      SharedPreferences.setMockInitialValues({'onboarded': true, 'seenVersion': '2.4.3', 'sound': false});
      await Store.init();
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const DartsApp());
      await tester.pumpAndSettle();
      // Spiel-Tab: Kacheln X01 und Turnier
      expect(find.text('Turnier'), findsOneWidget);
      await _tapText(tester, 'X01');
      await tester.pumpAndSettle();
      expect(find.text('Match starten'), findsOneWidget);
      expect(find.text('+ Bot'), findsOneWidget);

      // Zweiten Spieler anlegen, Match starten, ausbullen
      await tester.enterText(find.byType(TextField).first, 'Anna');
      await tester.tap(find.text('Spieler hinzufügen'));
      await tester.pumpAndSettle();
      expect(find.text('+ Bot'), findsNothing); // Bot nur bei genau einem Menschen
      await tester.enterText(find.byType(TextField).at(1), 'Ben');
      await tester.tap(find.bySemanticsLabel('Match starten'));
      await tester.pumpAndSettle();
      expect(find.text('Ausbullen'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Anna beginnt'));
      await tester.pumpAndSettle();
      expect(find.text('501'), findsWidgets);

      // 180 werfen: Triple + 20, dreimal
      for (var i = 0; i < 3; i++) {
        await _tapText(tester, 'Triple');
        await tester.tap(find.bySemanticsLabel('Triple 20'));
        await tester.pump(const Duration(milliseconds: 100));
      }
      // Pause + große Animation durchlaufen lassen
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('ONE HUNDRED AND EIGHTY'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('321'), findsWidgets);

      // Undo nimmt den Pfeil zurück
      await tester.tap(find.bySemanticsLabel('Letzten Pfeil rückgängig machen'));
      await tester.pumpAndSettle();
      expect(find.text('381'), findsWidgets);

      // Zurück zur Startseite, Cricket starten
      await tester.tap(find.byWidgetPredicate((w) => w is Key3 && w.semantics == 'Zurück'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Match fortsetzen'), findsOneWidget);
      await _tapText(tester, 'Minispiele');
      await tester.pumpAndSettle();
      await _tapText(tester, 'Cricket');
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Starten'));
      // Zielfelder pulsieren dauerhaft → feste Zeitschritte statt pumpAndSettle
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Cricket'), findsWidgets);
      await tester.tap(find.byWidgetPredicate((w) => w is Key3 && w.semantics == '20'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('/'), findsOneWidget); // eine Markierung auf der 20

      // Shanghai: nur Schnelltasten für die Zielzahl – S1, D1, T1 = Sofortsieg
      await tester.tap(find.byWidgetPredicate((w) => w is Key3 && w.semantics == 'Zurück'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pageBack();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await _tapText(tester, 'Shanghai');
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.bySemanticsLabel('Starten'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Ziel: 1'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Key3 && w.semantics == '7'), findsNothing);
      for (final label in ['1, Single · +1', 'D1, Double · +2', 'T1, Triple · +3']) {
        await tester.tap(find.byWidgetPredicate((w) => w is Key3 && w.semantics == label));
        await tester.pump(const Duration(milliseconds: 100));
      }
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.text('TREFFERBILD'), findsOneWidget);
      expect(find.text('Revanche'), findsOneWidget);
    });
  }
}

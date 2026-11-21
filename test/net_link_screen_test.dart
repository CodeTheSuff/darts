import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/net/link.dart';
import 'package:darts_counter/ui/link_screen.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _setup(WidgetTester tester, Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues({'onboarded': true, 'seenVersion': '3.0.0', 'sound': false, ...prefs});
  await Store.init();
  ThemeHost.apply(palettes.first);
  tester.view.physicalSize = const Size(412, 915) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _steps(WidgetTester tester, [int n = 5]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('Koppeln: mit eingestelltem Server zuerst „Online“, Umschalten auf „Im WLAN“', (tester) async {
    await _setup(tester, {'serverUrl': 'http://127.0.0.1:9'});
    await tester.pumpWidget(MaterialApp(theme: buildTheme(palettes.first), home: const LinkScreen()));
    await _steps(tester);
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('Im WLAN'), findsOneWidget);
    expect(find.text('Online-Raum eröffnen'), findsOneWidget);
    expect(find.text('RAUM BEITRETEN'), findsOneWidget);
    expect(find.text('Erweitert'), findsOneWidget);
    expect(find.textContaining('Noch kein Server'), findsNothing);

    // Ungültiger Code → Hinweis, keine Verbindung
    await tester.enterText(find.byType(TextField).at(1), 'ab');
    await tester.tap(find.text('Mitspielen'));
    await _steps(tester, 2);
    expect(find.textContaining('6 Zeichen'), findsOneWidget);
    expect(Link.I.role, LinkRole.none);

    await tester.tap(find.text('Im WLAN'));
    await _steps(tester);
    expect(find.text('Raum eröffnen'), findsOneWidget);
    expect(find.text('Adresse und Code eingeben'), findsOneWidget);
    Link.I.stopDiscovery();
    await tester.pumpWidget(const SizedBox());
    await _steps(tester, 2);
  });

  testWidgets('Koppeln: ohne Server-Adresse Hinweis im Online-Teil, „Erweitert“ zeigt das Feld', (tester) async {
    await _setup(tester, {});
    await tester.pumpWidget(MaterialApp(theme: buildTheme(palettes.first), home: const LinkScreen()));
    await _steps(tester);
    // Standard: WLAN (Platzhalter-Server)
    expect(find.text('Raum eröffnen'), findsOneWidget);
    await tester.tap(find.text('Online'));
    await _steps(tester);
    expect(find.textContaining('Noch kein Server'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Erweitert'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Erweitert'));
    await _steps(tester);
    expect(find.text('Server-Adresse'), findsOneWidget);
    expect(find.text('Verbindung testen'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Server-Adresse'), '192.168.0.10:8080');
    await tester.ensureVisible(find.text('Speichern'));
    await _steps(tester, 2);
    await tester.tap(find.text('Speichern'));
    await _steps(tester, 2);
    expect(Store.serverUrl, 'http://192.168.0.10:8080');
    await tester.pumpWidget(const SizedBox());
    await _steps(tester, 2);
  });
}

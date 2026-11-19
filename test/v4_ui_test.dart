import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/main.dart';
import 'package:darts_counter/ui/about_screen.dart';
import 'package:darts_counter/ui/look.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _setup(WidgetTester t, Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues({'sound': false, ...prefs});
  await Store.init();
  applyStoredTheme();
  t.view.physicalSize = const Size(412, 915) * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

Future<void> _steps(WidgetTester t, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  testWidgets('Erster Start: Einführung erscheint, Überspringen beendet sie dauerhaft', (t) async {
    await _setup(t, {});
    await t.pumpWidget(const DartsApp());
    await _steps(t);
    expect(find.text('1/7'), findsOneWidget);
    await t.tap(find.text('Weiter'));
    await _steps(t);
    expect(find.text('2/7'), findsOneWidget);
    await t.tap(find.text('Überspringen'));
    await _steps(t);
    expect(find.text('2/7'), findsNothing);
    expect(Store.onboarded, isTrue);
    expect(Store.seenVersion, appVersion);
  });

  testWidgets('Nach Update: „Was ist neu“ erscheint einmal', (t) async {
    await _setup(t, {'onboarded': true, 'seenVersion': '1.0.0', 'profiles': '[{"id":"a","name":"Simon"}]'});
    await t.pumpWidget(const DartsApp());
    await _steps(t);
    expect(find.text('Was ist neu'), findsOneWidget);
    expect(Store.seenVersion, appVersion);
  });

  testWidgets('Design „Automatisch“ folgt dem System, Farbschwäche-Modus schaltet Palette um', (t) async {
    await _setup(t, {'theme': 'auto', 'nightTheme': 'neon'});
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    applyStoredTheme();
    expect(C.p.id, 'neon');
    t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    applyStoredTheme();
    expect(C.p.id, 'hell');
    Store.colorblind = true;
    applyStoredTheme();
    expect(C.cb, isTrue);
    expect(C.dbl, isNot(paletteById('hell').dbl));
  });

  testWidgets('Große Schrift: Startseite und Einstellungen ohne Layoutfehler', (t) async {
    await _setup(t, {'onboarded': true, 'seenVersion': appVersion, 'fontScale': 1.15});
    t.view.physicalSize = const Size(360, 740) * 3;
    await t.pumpWidget(const DartsApp());
    await _steps(t);
    await t.tap(find.byTooltip('Einstellungen'));
    await _steps(t);
    await t.scrollUntilVisible(find.text('Schriftgröße'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Schriftgröße'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}

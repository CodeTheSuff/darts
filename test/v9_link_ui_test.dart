import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/data/tournament_store.dart';
import 'package:darts_counter/games/tournament.dart';
import 'package:darts_counter/net/link.dart';
import 'package:darts_counter/ui/link_badge.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:darts_counter/ui/tournament_display.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Tournament _tour() {
  final t = Tournament(
    id: 'tv',
    name: 'Anzeige-Test',
    created: DateTime(2026, 11, 25),
    system: TSystem.league,
    players: [for (final n in ['Simon', 'Max', 'Lena', 'Tom']) TPlayer(n, n)],
    start: 101,
    doubleOut: true,
    formats: const {TStage.group: TFormat(legs: 1)},
  )..build();
  TournamentStore.save(t);
  return t;
}

Future<void> _setup(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'onboarded': true, 'seenVersion': '9.9.9', 'sound': false});
  await Store.init();
  ThemeHost.apply(palettes.first);
  tester.view.physicalSize = const Size(1280, 800) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('Turnier-Anzeige: Tabs antippen, „Letztes Spiel“, Automatik ausschalten (gespeichert)', (tester) async {
    await _setup(tester);
    final t = _tour();
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(palettes.first),
      home: Scaffold(
        body: TournamentDisplay(
          t: t,
          interval: const Duration(seconds: 2),
          lastMatch: const Center(child: Text('STATISTIK-INHALT')),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('tour-tab-standing')), findsOneWidget);
    expect(find.byKey(const ValueKey('tour-tab-next')), findsOneWidget);
    expect(find.byKey(const ValueKey('tour-tab-lastMatch')), findsOneWidget);

    // Antippen wechselt sofort; danach bleibt die Ansicht 1 Minute stehen.
    await tester.tap(find.byKey(const ValueKey('tour-tab-lastMatch')));
    await tester.pumpAndSettle();
    expect(find.text('STATISTIK-INHALT'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('STATISTIK-INHALT'), findsOneWidget);

    // Automatik aus → bleibt dauerhaft stehen
    await tester.tap(find.byKey(const ValueKey('tour-auto')));
    await tester.pump();
    expect(Store.tournamentAutoCycle, isFalse);
    expect(find.text('Auto aus'), findsOneWidget);
    await tester.pump(const Duration(minutes: 3));
    await tester.pumpAndSettle();
    expect(find.text('STATISTIK-INHALT'), findsOneWidget);

    // Wischen wechselt die Ansicht
    await tester.fling(find.text('STATISTIK-INHALT'), const Offset(-400, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('STATISTIK-INHALT'), findsNothing);

    // Automatik an → wechselt wieder von selbst
    await tester.tap(find.byKey(const ValueKey('tour-auto')));
    await tester.pump();
    expect(Store.tournamentAutoCycle, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Verbindungs-Symbol im Spiel öffnet „Geräte verbinden“', (tester) async {
    await _setup(tester);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(palettes.first),
      home: Scaffold(appBar: AppBar(actions: const [LinkBadge()])),
    ));
    await tester.pump();
    expect(Link.I.role, LinkRole.none);
    await tester.tap(find.byKey(const ValueKey('link-badge')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Geräte verbinden'), findsWidgets);
    expect(find.text('Online-Raum eröffnen'), findsOneWidget);
    await tester.tap(find.byTooltip('Schließen'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Online-Raum eröffnen'), findsNothing);
    Link.I.stopDiscovery();
    await tester.pumpWidget(const SizedBox());
  });
}

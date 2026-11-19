import 'dart:math';

import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/data/tournament_store.dart';
import 'package:darts_counter/games/tournament.dart';
import 'package:darts_counter/main.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:darts_counter/ui/tournament_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _setup(WidgetTester tester, {Size size = const Size(412, 915), Map<String, Object>? prefs}) async {
  SharedPreferences.setMockInitialValues({'onboarded': true, 'seenVersion': '2.4.2', 'sound': false, ...?prefs});
  await Store.init();
  ThemeHost.apply(palettes.first);
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _steps(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Tournament _tournament(TSystem system, int n, {double playedShare = 0.5, int seed = 1}) {
  final (g, a) = suggestGroups(n);
  final t = Tournament(
    id: 'T${system.name}$n',
    name: 'Turnier ${system.label}',
    created: DateTime(2026, 11, 18),
    system: system,
    players: [for (var i = 0; i < n; i++) TPlayer('p$i', 'Spieler Nummer $i')],
    start: 501,
    doubleOut: true,
    formats: const {},
    groupCount: g,
    advance: a,
  )..build();
  final rng = Random(seed);
  final target = (t.realCount * playedShare).round();
  var guard = 0;
  while (t.playedCount < target && !t.finished && guard++ < 500) {
    final m = t.playable.first;
    final side = rng.nextInt(2);
    t.record(m.id,
        winnerSide: side, legs: side == 0 ? [3, 1] : [1, 3], points: [300, 280], darts: [15, 15]);
  }
  return t;
}

void main() {
  testWidgets('Einstellungen: alle Themes umschalten ohne Fehler', (tester) async {
    await _setup(tester);
    await tester.pumpWidget(const DartsApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Einstellungen'));
    await tester.pumpAndSettle();
    expect(find.text('Ton & Feedback'.toUpperCase()), findsOneWidget);
    for (final p in palettes.reversed) {
      final tile = find.text(p.tagline);
      await tester.scrollUntilVisible(tile, 200, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(C.p.id, p.id);
      expect(Store.themeId, p.id);
    }
    // Schalter setzen die Einstellungen
    await tester.scrollUntilVisible(find.text('Vibration'), -300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Vibration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vibration'));
    await tester.pump();
    expect(Store.vibration, isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('X01'), findsOneWidget);
    expect(find.text('Turnier'), findsOneWidget);
  });

  for (final size in const [Size(412, 915), Size(360, 740)]) {
    testWidgets('Bot-Match: Bot wirft automatisch (${size.width.toInt()})', (tester) async {
      await _setup(tester, size: size, prefs: {'botSpeed': 2});
      await tester.pumpWidget(const DartsApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('X01'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Anna');
      await tester.tap(find.text('+ Bot'));
      await tester.pumpAndSettle();
      expect(find.text('Bot (Mittel)'), findsOneWidget);
      await tester.tap(find.text('Profi'));
      await tester.pumpAndSettle();
      expect(find.text('Bot (Profi)'), findsOneWidget);
      expect(find.text('Spieler hinzufügen'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Match starten'));
      await _steps(tester);
      expect(find.text('Ausbullen'), findsNothing); // gegen Bots wird ausgelost
      // Anna wirft drei Mal (falls sie beginnt), danach muss der Bot von selbst werfen.
      for (var round = 0; round < 6; round++) {
        final key = find.bySemanticsLabel('20');
        final enabled = tester.widgetList<Key3>(find.byWidgetPredicate((w) => w is Key3 && w.semantics == '20'));
        if (enabled.isNotEmpty && enabled.first.enabled) {
          await tester.tap(key.first);
          await tester.pump(const Duration(milliseconds: 100));
        }
        await _steps(tester, 8);
      }
      expect(find.textContaining('Bot (Profi)'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byWidgetPredicate((w) => w is Key3 && w.semantics == 'Zurück'));
      await _steps(tester);
    });
  }

  testWidgets('Turnier-Assistent erstellt ein Turnier', (tester) async {
    await _setup(tester);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(palettes.first), home: const TournamentSetupScreen()));
    await tester.pumpAndSettle();
    for (final name in ['Anna', 'Ben', 'Cleo', 'Dora', 'Emil']) {
      await tester.enterText(find.byType(TextField).at(1), name);
      await tester.tap(find.byTooltip('Spieler hinzufügen'));
      await tester.pump();
    }
    expect(find.text('5 / 32'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Weiter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Doppel-K.o.'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Weiter'));
    await tester.pumpAndSettle();
    expect(find.byType(ReorderableListView), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Weiter'));
    await tester.pumpAndSettle();
    expect(find.text('Finale'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Turnier starten'));
    await tester.pumpAndSettle();
    final all = TournamentStore.all();
    expect(all.length, 1);
    expect(all.first.system, TSystem.doubleKo);
    expect(all.first.n, 5);
    expect(find.text('JETZT SPIELBAR'), findsOneWidget);
    // Ansichten durchschalten
    await tester.tap(find.text('Baum'));
    await tester.pumpAndSettle();
    expect(find.text('VERLIERERRUNDE'), findsOneWidget);
  });

  for (final system in TSystem.values) {
    for (final n in [4, 9, 32]) {
      for (final share in [0.4, 1.0]) {
        testWidgets('Turnier-Ansicht ${system.name} $n Spieler, ${(share * 100).round()} % gespielt', (tester) async {
          await _setup(tester, size: const Size(360, 740));
          final t = _tournament(system, n, playedShare: share);
          TournamentStore.save(t);
          await tester.pumpWidget(
              MaterialApp(theme: buildTheme(palettes.first), home: TournamentScreen(id: t.id)));
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
          if (share == 1.0) expect(find.text('SIEGEREHRUNG'), findsWidgets);
          for (final v in ['Baum', 'Tabelle', 'Spiele']) {
            final f = find.text(v);
            if (f.evaluate().isEmpty) continue;
            await tester.tap(f.first);
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

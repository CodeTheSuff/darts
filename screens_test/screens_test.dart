// ignore_for_file: invalid_use_of_visible_for_testing_member
// Rendert Screenshots der wichtigsten Bildschirme mit echter Schrift.
// Aufruf: flutter test screens_test/screens_test.dart  (SHOT_DIR, SHOT_THEMES optional)
import 'dart:io';

import 'dart:ui' as ui;

import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/data/tournament_store.dart';
import 'package:darts_counter/games/bot.dart';
import 'package:darts_counter/games/catalog.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/games/tournament.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:darts_counter/ui/game_screen.dart';
import 'package:darts_counter/ui/home_screen.dart';
import 'package:darts_counter/ui/link_screen.dart';
import 'package:darts_counter/ui/share_screens.dart';
import 'package:darts_counter/data/sync.dart';
import 'package:darts_counter/ui/settings_screen.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:darts_counter/ui/tournament_screens.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

final outDir = Platform.environment['SHOT_DIR'] ?? 'build/screens';

Future<void> loadFonts() async {
  Future<ByteData> f(String p) async => ByteData.view(Uint8List.fromList(File(p).readAsBytesSync()).buffer);
  final barlow = FontLoader('Barlow');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    barlow.addFont(f('assets/fonts/Barlow-$w.ttf'));
  }
  await barlow.load();
  final cond = FontLoader('BarlowCondensed');
  for (final w in ['SemiBold', 'Bold', 'ExtraBold']) {
    cond.addFont(f('assets/fonts/BarlowCondensed-$w.ttf'));
  }
  await cond.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(f('C:/dev/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf'));
  await icons.load();
}

final _key = GlobalKey();

Future<void> shot(WidgetTester tester, String name) async {
  final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final img = await tester.runAsync(() => boundary.toImage(pixelRatio: 1.0));
  final data = await tester.runAsync(() => img!.toByteData(format: ui.ImageByteFormat.png));
  Directory(outDir).createSync(recursive: true);
  File('$outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
}

Widget app(AppPalette p, Widget home) => RepaintBoundary(
  key: _key,
  child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(p), home: home),
);

Future<void> prep(WidgetTester tester, AppPalette p) async {
  SharedPreferences.setMockInitialValues({'onboarded': true, 'seenVersion': '2.4.1', 'sound': false, 'celebrations': false});
  await Store.init();
  ThemeHost.apply(p);
  tester.view.physicalSize = const Size(412, 900) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  for (final n in ['Simon', 'Max', 'Lena', 'Tom', 'Jana', 'Paul', 'Mia', 'Ben']) {
    Store.ensureProfile(n);
  }
  Store.lastSetup = {
    'players': [
      {'name': 'Simon', 'color': C.players[0].toARGB32()},
      {'bot': 'hard', 'color': C.players[1].toARGB32()},
    ],
  };
  Store.saveOptions('x01', {'start': 501, 'doubleOut': true, 'format': 'sets', 'sets': 3, 'legs': 3});
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUpAll(loadFonts);

  final themes = Platform.environment['SHOT_THEMES']?.split(',') ?? ['arena', 'pub', 'turnier', 'neon', 'hell'];
  for (final id in themes) {
    final p = paletteById(id);
    testWidgets('home $id', (tester) async {
      await prep(tester, p);
      await tester.pumpWidget(app(p, const HomeScreen()));
      await settle(tester);
      await shot(tester, '${id}_1_home');
    });

    testWidgets('game $id', (tester) async {
      await prep(tester, p);
      final ctl = MatchController(
        config: const GameConfig('x01', {'start': 501, 'doubleOut': true, 'format': 'sets', 'sets': 3, 'legs': 3}),
        players: const [GamePlayer('a', 'Simon', 0xFF5AA9FF), GamePlayer('b', 'Max', 0xFFF5C84C)],
      );
      for (final d in const [
        Dart(20, 3),
        Dart(20, 3),
        Dart(20, 1),
        Dart(19, 3),
        Dart(19, 1),
        Dart(7, 1),
        Dart(20, 3),
        Dart(5, 1),
      ]) {
        ctl.throwDart(Dart.thrown(d.field, d.mult));
      }
      await tester.pumpWidget(app(p, GameScreen(controller: ctl)));
      await settle(tester);
      await shot(tester, '${id}_2_game');
    });

    testWidgets('settings $id', (tester) async {
      await prep(tester, p);
      await tester.pumpWidget(app(p, const SettingsScreen()));
      await settle(tester);
      await shot(tester, '${id}_3_settings');
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await settle(tester);
      await shot(tester, '${id}_4_settings2');
    });

    testWidgets('tournament $id', (tester) async {
      await prep(tester, p);
      final t = Tournament(
        id: 'x',
        name: 'Darts-Abend',
        created: DateTime(2026, 11, 18),
        system: TSystem.doubleKo,
        players: [
          for (final n in ['Simon', 'Max', 'Lena', 'Tom', 'Jana', 'Paul']) TPlayer(n, n),
        ],
        start: 501,
        doubleOut: true,
        formats: const {},
      )..build();
      for (var i = 0; i < 5; i++) {
        final m = t.playable.first;
        t.record(m.id, winnerSide: i % 2, legs: i.isEven ? [3, 1] : [2, 3], points: [400, 350], darts: [18, 18]);
      }
      TournamentStore.save(t);
      await tester.pumpWidget(app(p, TournamentScreen(id: t.id)));
      await settle(tester);
      await shot(tester, '${id}_5_tournament');
      await tester.tap(find.text('Baum'));
      await settle(tester);
      await shot(tester, '${id}_6_bracket');
    });
  }

  testWidgets('podium', (tester) async {
    final p = paletteById('arena');
    await prep(tester, p);
    final t = Tournament(
      id: 'y',
      name: 'Liga-Finale',
      created: DateTime(2026, 11, 18),
      system: TSystem.league,
      players: [
        for (final n in ['Simon', 'Max', 'Lena', 'Tom', 'Jana']) TPlayer(n, n),
      ],
      start: 501,
      doubleOut: true,
      formats: const {},
    )..build();
    var i = 0;
    while (!t.finished) {
      final m = t.playable.first;
      t.record(m.id, winnerSide: i++ % 3 == 0 ? 1 : 0, legs: [3, 1], points: [400, 350], darts: [18, 18]);
    }
    TournamentStore.save(t);
    await tester.pumpWidget(app(p, TournamentScreen(id: t.id)));
    await settle(tester);
    await shot(tester, 'arena_7_podium');
    await tester.tap(find.text('Tabelle'));
    await settle(tester);
    await shot(tester, 'arena_8_table');
  });

  testWidgets('v3 screens', (tester) async {
    final p = paletteById('arena');
    await prep(tester, p);
    await tester.pumpWidget(app(p, const HomeScreen()));
    await settle(tester);
    await shot(tester, 'v3_1_home');
    await tester.tap(find.text('Turnier'));
    await settle(tester);
    await shot(tester, 'v3_2_hub');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(app(p, const LinkScreen()));
    await settle(tester);
    await shot(tester, 'v3_3_link');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(app(p, const ShareScreen()));
    await settle(tester);
    await shot(tester, 'v3_4_share');
    final pkg = SharePackage(
      device: 'x',
      deviceName: 'Handy von Max',
      created: DateTime(2026),
      profiles: const [Profile('r1', 'Simon'), Profile('r2', 'Max'), Profile('r3', 'Jonas')],
      entries: [
        for (final id in ['r1', 'r2', 'r3'])
          LogEntry(rid: 'm1', oid: id, pid: id, t: 1, mode: 'x01', d: PlayerStats()..x01.matches = 1),
      ],
      tournaments: const [],
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(app(p, ImportPreviewScreen(pkg: pkg)));
    await settle(tester);
    await shot(tester, 'v3_5_import');
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  for (final id in ['arena', 'hell']) {
    for (final (mode, opts) in [
      ('x01', <String, dynamic>{}),
      ('atc', {'variant': 'doubles'}),
      ('atc', {'variant': 'classic'}),
      ('shanghai', <String, dynamic>{}),
      ('killer', <String, dynamic>{}),
      ('bobs27', <String, dynamic>{}),
    ]) {
      testWidgets('colors $id $mode ${opts.values.join()}', (tester) async {
        final p = paletteById(id);
        await prep(tester, p);
        final ctl = MatchController(
          config: GameConfig(mode, {...modeById(mode).defaults, ...opts}),
          players: const [GamePlayer('a', 'Simon', 0xFF5AA9FF), GamePlayer('b', 'Max', 0xFFF5C84C)],
        );
        await tester.pumpWidget(app(p, GameScreen(controller: ctl)));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        await shot(tester, 'c_${id}_$mode${opts.values.join()}');
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
      });
    }
  }

  testWidgets('bot game', (tester) async {
    final p = paletteById('neon');
    await prep(tester, p);
    final ctl = MatchController(
      config: const GameConfig('x01', {'start': 501, 'doubleOut': true, 'legs': 3}),
      players: [
        const GamePlayer('a', 'Simon', 0xFF5AA9FF),
        GamePlayer(botIdFor(BotLevel.pro), 'Bot (Profi)', 0xFFB48CFF),
      ],
      startIndex: 1,
    );
    for (var k = 0; k < 2; k++) {
      ctl.throwDart(ctl.nextBotDart());
    }
    await tester.pumpWidget(app(p, GameScreen(controller: ctl)));
    await tester.pump(const Duration(milliseconds: 100));
    await shot(tester, 'neon_9_botgame');
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}

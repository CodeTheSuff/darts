// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:darts_counter/data/match_report.dart';
import 'package:darts_counter/ui/match_share.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/games/catalog.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/main.dart';
import 'package:darts_counter/models/player.dart';
import 'package:darts_counter/ui/about_screen.dart';
import 'package:darts_counter/ui/game_screen.dart';
import 'package:darts_counter/ui/look.dart';
import 'package:darts_counter/ui/stats_screen.dart';
import 'package:darts_counter/data/analytics.dart';
import 'package:darts_counter/games/bot.dart';
import 'package:darts_counter/ui/link_coordinator.dart';
import 'package:darts_counter/ui/scoreboard_screen.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/ui/settings_screen.dart';
import 'package:darts_counter/ui/theme.dart';
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
  await (FontLoader('MaterialIcons')
        ..addFont(f('C:/dev/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')))
      .load();
}

Future<void> shot(WidgetTester t, String name) async {
  final ro = t.binding.rootElement!.findRenderObject()!;
  final layer = (ro as RenderView).debugLayer! as OffsetLayer;
  final img = await t.runAsync(() => layer.toImage(Offset.zero & t.view.physicalSize / t.view.devicePixelRatio));
  final data = await t.runAsync(() => img!.toByteData(format: ui.ImageByteFormat.png));
  Directory(outDir).createSync(recursive: true);
  File('$outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
}

Future<void> prep(WidgetTester t, Map<String, Object> prefs, {Size size = const Size(412, 900)}) async {
  SharedPreferences.setMockInitialValues({'sound': false, ...prefs});
  await Store.init();
  applyStoredTheme();
  t.view.physicalSize = size * 1;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  for (final n in ['Simon', 'Max']) {
    Store.ensureProfile(n);
  }
}

Future<void> settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUpAll(loadFonts);

  testWidgets('Einführung', (t) async {
    await prep(t, {});
    await t.pumpWidget(const DartsApp());
    await settle(t);
    await shot(t, 'v4_tour1');
    await t.tap(find.text('Weiter'));
    await settle(t);
    await t.tap(find.text('Weiter'));
    await settle(t);
    await shot(t, 'v4_tour3');
    for (var i = 0; i < 4; i++) {
      await t.tap(find.text('Weiter'));
      await settle(t, 3);
    }
    await shot(t, 'v4_tour7');
    await t.tap(find.text('Los geht’s'));
    await settle(t);
    expect(Store.onboarded, isTrue);
    await shot(t, 'v4_home');
  });

  testWidgets('Was ist neu + Über', (t) async {
    await prep(t, {'onboarded': true, 'seenVersion': '1.0.0'});
    await t.pumpWidget(const DartsApp());
    await settle(t);
    await shot(t, 'v4_whatsnew');
    await t.pumpWidget(MaterialApp(theme: buildTheme(C.p), home: const AboutScreen()));
    await settle(t);
    await shot(t, 'v4_about');
  });

  testWidgets('Einstellungen', (t) async {
    await prep(t, {'onboarded': true, 'seenVersion': appVersion, 'theme': 'auto', 'caller': true});
    await t.pumpWidget(MaterialApp(theme: buildTheme(C.p), home: const SettingsScreen()));
    await settle(t);
    await shot(t, 'v4_settings1');
    await t.drag(find.byType(ListView), const Offset(0, -800));
    await settle(t);
    await shot(t, 'v4_settings2');
    await t.drag(find.byType(ListView), const Offset(0, -900));
    await settle(t);
    await shot(t, 'v4_settings3');
  });

  for (final (name, prefs, size) in [
    ('cb', <String, Object>{'colorblind': true}, const Size(412, 900)),
    ('big360', <String, Object>{'fontScale': 1.15}, const Size(360, 740)),
  ]) {
    for (final mode in ['x01', 'shanghai']) {
      testWidgets('Spiel $name $mode', (t) async {
        await prep(t, {'onboarded': true, 'seenVersion': appVersion, ...prefs}, size: size);
        final ctl = MatchController(
          config: GameConfig(mode, modeById(mode).defaults),
          players: const [GamePlayer('a', 'Simon', 0xFF5AA9FF), GamePlayer('b', 'Max', 0xFFF5C84C)],
        );
        await t.pumpWidget(MaterialApp(
          theme: buildTheme(C.p),
          builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(ThemeHost.fontScale)),
            child: child!,
          ),
          home: GameScreen(controller: ctl),
        ));
        await settle(t, 3);
        if (mode == 'x01') {
          await t.tap(find.byWidgetPredicate((w) => w is Key3 && (w.semantics ?? '').startsWith('Triple')));
          await settle(t, 2);
        }
        await shot(t, 'v4_${name}_$mode');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await settle(t, 2);
      });
    }
  }

  for (final size in const [Size(412, 900), Size(900, 412)]) {
    testWidgets('Scoreboard ${size.width}', (t) async {
      await prep(t, {'onboarded': true, 'seenVersion': appVersion}, size: size);
      final c = MatchController(
        config: const GameConfig('x01', {'start': 501, 'doubleOut': true, 'format': 'sets', 'sets': 2, 'legs': 3}),
        players: const [GamePlayer('a', 'Simon', 0xFF5AA9FF), GamePlayer('b', 'Max', 0xFFF5C84C)],
      );
      for (final d in const [Dart(20, 3), Dart(20, 3), Dart(20, 1), Dart(19, 3), Dart(19, 1), Dart(7, 1)]) {
        c.throwDart(Dart.thrown(d.field, d.mult));
      }
      LinkCoordinator.viewerState.value = {'match': c.toJson()};
      await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(C.p), home: const ScoreboardScreen()));
      await settle(t, 3);
      await shot(t, 'v5_board_${size.width.toInt()}');
      await t.pumpWidget(const SizedBox());
      await settle(t, 2);
    });
  }

  testWidgets('Ergebniskarte', (t) async {
    await prep(t, {'onboarded': true, 'seenVersion': appVersion});
    final c = MatchController(
      config: const GameConfig('x01', {'start': 101, 'doubleOut': true, 'legs': 1}),
      players: const [GamePlayer('a', 'Simon', 0xFF5AA9FF), GamePlayer('b', 'Max', 0xFFF5C84C)],
    );
    for (final d in const [Dart(20, 3), Dart(1, 1), Dart(20, 2)]) {
      c.throwDart(d);
    }
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(C.p),
      home: MatchShareScreen(
        engine: c.engine,
        rows: matchRows(MatchReport.build(
            config: c.config, players: c.players, startIndex: c.startIndex, seed: c.seed, darts: c.darts)!),
        date: DateTime(2026, 11, 19),
      ),
    ));
    await settle(t, 3);
    await shot(t, 'v5_card');
    await shot(t, 'v8_share_single');
    await t.tap(find.text('Alle'));
    await settle(t, 3);
    await shot(t, 'v8_share_all');
  });

  testWidgets('Statistik-Ansichten', (t) async {
    await prep(t, {'onboarded': true, 'seenVersion': appVersion});
    final a = Store.ensureProfile('Simon');
    final b = Store.ensureProfile('Max');
    final pa = GamePlayer(a.id, a.name, 0xFF5AA9FF);
    final pb = GamePlayer(b.id, b.name, 0xFFF5C84C);
    // 8 simulierte Matches: Simon als Profi-Bot-Stärke, Max als Mittel
    for (var k = 0; k < 8; k++) {
      final c = MatchController(config: const GameConfig('x01', {'start': 501, 'doubleOut': true, 'legs': 2}), players: [pa, pb]);
      final bots = [Bot(BotLevel.pro), Bot(BotLevel.medium)];
      var guard = 0;
      while (!c.engine.finished && guard++ < 800) {
        final e = c.engine as dynamic;
        final i = e.cur as int;
        if ((e.turn as List).isEmpty) bots[i].startVisit();
        c.throwDart(bots[i].next((e.scores as List<int>)[i], 3 - (e.turn as List).length, doubleOut: true));
      }
      c.commitStats();
    }
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(C.p), home: PlayerStatsScreen(profile: a, color: C.players[0])));
    await settle(t, 3);
    await shot(t, 'v6_player1');
    await t.drag(find.byType(ListView), const Offset(0, -700));
    await settle(t, 3);
    await shot(t, 'v6_player2');
    final h = Analytics.history(a.id);
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(C.p), home: MatchDetailScreen(summary: h.first)));
    await settle(t, 3);
    await shot(t, 'v6_detail');
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(C.p), home: DoublesScreen(pid: a.id, name: a.name, color: C.players[0])));
    await settle(t, 3);
    await shot(t, 'v6_doubles');
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(C.p), home: AchievementsScreen(pid: a.id, name: a.name)));
    await settle(t, 3);
    await shot(t, 'v6_ach');
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(C.p), home: HeadToHeadScreen(a: a.id, b: b.id)));
    await settle(t, 3);
    await shot(t, 'v6_h2h');
  });
}

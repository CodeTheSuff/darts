import 'package:darts_counter/data/match_report.dart';
import 'package:darts_counter/data/mode_report.dart';
import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/games/catalog.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:darts_counter/net/link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _p = [GamePlayer('a', 'Simon', 0xFF5AA9FF), GamePlayer('b', 'Max', 0xFFF5C84C)];

ModeReport _mode(String id, List<Dart> darts) => ModeReport.build(
      config: GameConfig(id, {...modeById(id).defaults}),
      players: _p,
      startIndex: 0,
      seed: 1,
      darts: darts,
    )!;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });

  group('Statistik nach Trainings-/Minispielen', () {
    test('Cricket: Marks pro Runde, Bull 50 zählt 2 Marks, Trefferbild je Spieler', () {
      final r = _mode('cricket', const [
        Dart(20, 3), Dart(25, 2), Dart(1, 1), // Simon: 3 + 2 Marks, 1 zählt nicht
        Dart(19, 1), Dart(0, 1), Dart(0, 1), // Max: 1 Mark
      ]);
      expect(r.players[0].marks, 5);
      expect(r.players[0].mpr, closeTo(5.0, 0.01));
      expect(r.players[1].marks, 1);
      expect(r.players[0].hits, {'T20': 1, '50': 1, 'S1': 1});
      expect(r.players[1].hits['Miss'], 2);
      final rows = modeRows(r, const []);
      expect(rows.map((x) => x.label), contains('Marks pro Runde'));
    });

    test("Bob's 27: Doubles getroffen", () {
      final r = _mode('bobs27', const [Dart(1, 2), Dart(1, 1), Dart(0, 1)]);
      expect(r.players[0].targetHits, 1);
      expect(r.players[0].targetDarts, 3);
      final row = modeRows(r, const []).firstWhere((x) => x.label == 'Doubles getroffen');
      expect(row.values[0], '1 / 3');
    });

    test('X01 hat keinen Modus-Report', () {
      expect(
          ModeReport.build(
              config: const GameConfig('x01', {'start': 301}), players: _p, startIndex: 0, seed: 1, darts: const []),
          isNull);
    });
  });

  test('Leg-Statistik enthält das Trefferbild nur dieses Legs', () {
    final r = MatchReport.build(
      config: const GameConfig('x01', {'start': 101, 'doubleOut': true, 'legs': 2}),
      players: _p,
      startIndex: 0,
      seed: 1,
      darts: const [
        Dart(20, 3), Dart(1, 1), Dart(20, 2), // Leg 1: Simon checkt 101
        Dart(5, 1), Dart(5, 1), Dart(5, 1), // Leg 2: Max beginnt
      ],
    )!;
    expect(r.legs.first.players[0].hits, {'T20': 1, 'S1': 1, 'D20': 1});
    expect(r.legs.first.players[1].hits, isEmpty);
    expect(r.legs[1].players[1].hits, {'S5': 3});
    expect(r.total[0].hits['T20'], 1);
  });

  group('Kopplung nach Neustart wiederherstellen', () {
    test('Host merkt sich den offenen Raum, Schließen löscht ihn', () async {
      final host = Link.forTest();
      await host.startHost(preferredPort: 0);
      expect(Link.recentSession()?['role'], 'host');
      // Absturz = kein leave(): bleibt gemerkt
      await host.stop();
      expect(Link.recentSession()?['role'], 'host');
      await host.startHost(preferredPort: 0);
      await host.leave();
      expect(Link.recentSession(), isNull);
    });

    test('Gast merkt sich Adresse und Code; Trennen löscht', () async {
      final host = Link.forTest();
      await host.startHost(preferredPort: 0);
      final guest = Link.forTest();
      expect(await guest.join('127.0.0.1', host.port, host.code!, name: 'Tablet', viewer: true), isTrue);
      final s = Link.recentSession()!;
      expect(s['role'], 'client');
      expect(s['address'], '127.0.0.1');
      expect(s['port'], host.port);
      expect(s['viewer'], true);
      await guest.leave();
      expect(Link.recentSession(), isNull);
      await host.stop();
    });

    test('Nur innerhalb von 30 Minuten', () {
      final now = DateTime(2026, 11, 20, 12);
      Store.linkSession = {'role': 'host', 'ts': now.subtract(const Duration(minutes: 29)).millisecondsSinceEpoch};
      expect(Link.recentSession(now), isNotNull);
      Store.linkSession = {'role': 'host', 'ts': now.subtract(const Duration(minutes: 31)).millisecondsSinceEpoch};
      expect(Link.recentSession(now), isNull);
      expect(Store.linkSession, isNull, reason: 'alte Sitzung wird gelöscht');
    });
  });
}

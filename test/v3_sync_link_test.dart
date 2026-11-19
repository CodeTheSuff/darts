import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/data/sync.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/games/x01.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:darts_counter/net/link.dart';
import 'package:darts_counter/ui/link_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ein simuliertes Handy: sein kompletter Speicher.
class Device {
  Device(this.name);
  final String name;
  Map<String, Object> prefs = {};

  Future<void> use() async {
    SharedPreferences.setMockInitialValues(prefs);
    await Store.init();
    Store.deviceName = name;
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    prefs = {for (final k in p.getKeys()) k: p.get(k)!};
  }
}

/// Spielt ein 101-Match: [a] checkt in 3 Darts.
MatchController playMatch(GamePlayer a, GamePlayer b, {String? matchId}) {
  final ctl = MatchController(
    config: const GameConfig('x01', {'start': 101, 'doubleOut': true, 'legs': 1}),
    players: [a, b],
    matchId: matchId,
  );
  ctl.throwDart(const Dart(20, 3));
  ctl.throwDart(const Dart(1, 1));
  ctl.throwDart(const Dart(20, 2));
  ctl.commitStats();
  return ctl;
}

GamePlayer gp(String name) {
  final p = Store.ensureProfile(name);
  return GamePlayer(p.id, p.name, 0xFF5AA9FF);
}

void main() {
  group('Datenabgleich', () {
    test('Zwei Handys: zusammenführen ohne doppelt zu zählen, in beide Richtungen', () async {
      final a = Device('Handy A');
      final b = Device('Handy B');

      await a.use();
      for (var i = 0; i < 3; i++) {
        playMatch(gp('Simon'), gp('Max'));
      }
      expect(Store.statsFor(gp('Simon').profileId).x01.matches, 3);
      await a.save();

      await b.use();
      for (var i = 0; i < 2; i++) {
        playMatch(gp('simon'), gp('Lena'));
      }
      await b.save();

      // A → B
      await a.use();
      final pkgA = Sync.build({for (final p in Store.profiles) p.id}).encode();
      await b.use();
      var pkg = SharePackage.fromJson(Map<String, dynamic>.from(jsonDecode(pkgA) as Map));
      var choices = Sync.suggest(pkg);
      final simonA = pkg.profiles.firstWhere((p) => p.name == 'Simon');
      expect(choices[simonA.id]!.kind, MergeKind.merge); // gleicher Name (Groß/Klein egal)
      final maxA = pkg.profiles.firstWhere((p) => p.name == 'Max');
      expect(choices[maxA.id]!.kind, MergeKind.create);
      Sync.apply(pkg, choices);
      final simonB = Store.profiles.firstWhere((p) => p.name.toLowerCase() == 'simon').id;
      expect(Store.statsFor(simonB).x01.matches, 5);
      expect(Store.profiles.map((p) => p.name).toSet(), {'simon', 'Lena', 'Max'});

      // Gleiches Paket noch einmal: nichts kommt doppelt dazu
      final (added, _, _) = Sync.apply(pkg, Sync.suggest(pkg));
      expect(added, 0);
      expect(Store.statsFor(simonB).x01.matches, 5);
      await b.save();

      // B → A (enthält auch A's eigene Matches zurück): A hat danach ebenfalls 5
      final pkgB = Sync.build({for (final p in Store.profiles) p.id}).encode();
      await a.use();
      pkg = SharePackage.fromJson(Map<String, dynamic>.from(jsonDecode(pkgB) as Map));
      choices = Sync.suggest(pkg);
      Sync.apply(pkg, choices);
      final simonOnA = Store.profiles.firstWhere((p) => p.name == 'Simon').id;
      expect(Store.statsFor(simonOnA).x01.matches, 5);
      expect(Store.profiles.length, 3); // Simon, Max, Lena – kein doppelter Simon/Max
      expect(Store.statsFor(Store.profiles.firstWhere((p) => p.name == 'Max').id).x01.matches, 3);
    });

    test('Gekoppeltes Match auf beiden Handys gespeichert → beim Abgleich nicht doppelt', () async {
      final a = Device('A');
      final b = Device('B');
      await a.use();
      final simon = gp('Simon');
      final max = gp('Max');
      final host = playMatch(simon, max);
      await a.save();

      // Gast speichert dasselbe Match (gleiche Match-ID, Spieler-IDs vom Host)
      await b.use();
      playMatch(simon, max, matchId: host.matchId);
      expect(Store.profiles.map((p) => p.name).toSet(), {'Simon', 'Max'});
      await b.save();

      final pkg = SharePackage.fromJson(
          Map<String, dynamic>.from(jsonDecode(Sync.build({for (final p in Store.profiles) p.id}).encode()) as Map));
      await a.use();
      final (added, created, _) = Sync.apply(pkg, Sync.suggest(pkg));
      expect(added, 0);
      expect(created, 0);
      expect(Store.statsFor(simon.profileId).x01.matches, 1);
    });

    test('Umstellung: alte summierte Statistik bleibt als Grundstand erhalten', () async {
      final old = PlayerStats();
      old.x01.matches = 7;
      old.x01.darts = 300;
      old.x01.points = 4000;
      old.tournaments = 2;
      SharedPreferences.setMockInitialValues({
        'profiles': jsonEncode([
          {'id': 'p1', 'name': 'Simon'}
        ]),
        'stats_p1': jsonEncode(old.toJson()),
      });
      await Store.init();
      expect(Store.log.length, 1);
      expect(Store.statsFor('p1').x01.matches, 7);
      playMatch(const GamePlayer('p1', 'Simon', 0), gp('Max'));
      final s = Store.statsFor('p1');
      expect(s.x01.matches, 8);
      expect(s.tournaments, 2);
      // Erneutes Starten migriert nicht noch einmal
      await Store.init();
      expect(Store.statsFor('p1').x01.matches, 8);
    });

    test('Überspringen und neu anlegen bei Namensgleichheit', () async {
      final a = Device('A');
      await a.use();
      playMatch(gp('Simon'), gp('Max'));
      final pkg = Sync.build({for (final p in Store.profiles) p.id});
      final b = Device('B');
      await b.use();
      gp('Simon');
      final choices = Sync.suggest(pkg);
      final simonA = pkg.profiles.firstWhere((p) => p.name == 'Simon');
      final maxA = pkg.profiles.firstWhere((p) => p.name == 'Max');
      choices[simonA.id] = MergeChoice(MergeKind.create);
      choices[maxA.id] = MergeChoice(MergeKind.skip);
      Sync.apply(pkg, choices);
      expect(Store.profiles.map((p) => p.name).toSet(), {'Simon', 'Simon (2)'});
    });
  });

  group('Kopplung (echte Sockets)', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Store.init();
    });

    test('Falscher Code wird abgelehnt, richtiger verbindet', () async {
      final host = Link.forTest();
      await host.startHost(preferredPort: 0);
      final guest = Link.forTest();
      expect(await guest.join('127.0.0.1', host.port, '0000' == host.code ? '1111' : '0000'), isFalse);
      expect(await guest.join('127.0.0.1', host.port, host.code!), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(host.peerCount, 1);
      await guest.stop();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(host.peerCount, 0);
      await host.stop();
    });

    test('Gast wirft, Host übernimmt, alle haben denselben Stand – auch nach Undo', () async {
      // Host = Link.I mit Koordinator, Gast = eigene Instanz
      LinkCoordinator.init();
      Link.I.trustAll = true;
      await Link.I.startHost(preferredPort: 0);
      final hostCtl = MatchController(
        config: const GameConfig('x01', {'start': 501, 'doubleOut': true, 'legs': 1}),
        players: [gp('Simon'), gp('Max')],
      );
      LinkCoordinator.gameOpened(hostCtl);

      final guest = Link.forTest();
      final states = StreamController<Map<String, dynamic>>.broadcast();
      guest.onState = states.add;
      expect(await guest.join('127.0.0.1', Link.I.port, Link.I.code!), isTrue);

      // erster Stand mit dem laufenden Match
      var st = await states.stream.firstWhere((s) => s['match'] != null).timeout(const Duration(seconds: 3));
      final guestCtl = MatchController.fromJson(Map<String, dynamic>.from(st['match'] as Map))!..remote = false;
      expect(guestCtl.matchId, hostCtl.matchId);

      List<Dart> dartsOf(Map<String, dynamic> s) => [
            for (final d in (s['match'] as Map)['darts'] as List) Dart.fromJson(Map<String, dynamic>.from(d as Map)),
          ];

      // Gast trägt T20 ein
      final next = states.stream.firstWhere((s) => dartsOf(s).length == 1);
      guest.sendToHost({'t': 'dart', 'mid': guestCtl.matchId, 'd': const Dart(20, 3).toJson()});
      st = await next.timeout(const Duration(seconds: 3));
      expect(hostCtl.darts.length, 1);
      expect((hostCtl.engine as X01Game).scores[0], 441);
      guestCtl.applyRemote(dartsOf(st));
      expect((guestCtl.engine as X01Game).scores[0], 441);

      // Host trägt ein → Gast bekommt es
      final next2 = states.stream.firstWhere((s) => dartsOf(s).length == 2);
      hostCtl.throwDart(const Dart(19, 3));
      guestCtl.applyRemote(dartsOf(await next2.timeout(const Duration(seconds: 3))));
      expect((guestCtl.engine as X01Game).scores[0], 384);

      // Undo vom Gast
      final next3 = states.stream.firstWhere((s) => dartsOf(s).length == 1);
      guest.sendToHost({'t': 'undo', 'mid': guestCtl.matchId});
      guestCtl.applyRemote(dartsOf(await next3.timeout(const Duration(seconds: 3))));
      expect((guestCtl.engine as X01Game).scores[0], 441);
      expect(guestCtl.resynced, 1);

      // Gast schaltet Single Out ein → Host und Gast haben es
      final next4 = states.stream.firstWhere((s) => dartsOf(s).length == 2);
      guest.sendToHost({'t': 'dart', 'mid': guestCtl.matchId, 'd': Dart.singleOutOn.toJson()});
      guestCtl.applyRemote(dartsOf(await next4.timeout(const Duration(seconds: 3))));
      expect((hostCtl.engine as X01Game).singleOutLeg, isTrue);
      expect((guestCtl.engine as X01Game).singleOutLeg, isTrue);

      // Host verlässt das Spiel → Stand ohne Match
      final idle = states.stream.firstWhere((s) => s['match'] == null);
      LinkCoordinator.gameClosed(hostCtl);
      await idle.timeout(const Duration(seconds: 3));

      await guest.stop();
      await Link.I.stop();
    });

    test('Gast verbindet sich nach Abbruch automatisch neu', () async {
      final host = Link.forTest();
      await host.startHost(preferredPort: 0);
      final port = host.port;
      final code = host.code!;
      final guest = Link.forTest();
      expect(await guest.join('127.0.0.1', port, code), isTrue);
      // Host-Verbindung hart trennen (Server läuft weiter)
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await host.dropAllForTest();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(guest.isConnected, isFalse);
      expect(guest.status, contains('verbinde neu'));
      // Innerhalb weniger Sekunden wieder verbunden
      var ok = false;
      for (var i = 0; i < 40 && !ok; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        ok = guest.isConnected;
      }
      expect(ok, isTrue);
      await guest.stop();
      await host.stop();
    });

    test('Raumsuche findet den Host per UDP-Broadcast', () async {
      final host = Link.forTest();
      await host.startHost(preferredPort: 0);
      final guest = Link.forTest();
      // Der Gast hat eine andere Geräte-ID nur auf echten Handys – hier filtern wir nach Code.
      await guest.startDiscovery(includeSelf: true);
      Room? found;
      for (var i = 0; i < 30 && found == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        found = guest.rooms.value.where((r) => r.port == host.port).firstOrNull;
      }
      expect(found, isNotNull);
      expect(found!.port, host.port);
      guest.stopDiscovery();
      await host.stop();
    });

    test('Host beantwortet die direkte Raumabfrage (Suche ohne Broadcast)', () async {
      final host = Link.forTest();
      await host.startHost(preferredPort: 0);
      final client = HttpClient();
      final req = await client.get('127.0.0.1', host.port, '/darts/info');
      final res = await req.close();
      final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
      expect(res.statusCode, 200);
      expect(j['app'], 'darts_counter');
      expect(j.containsKey('code'), isFalse); // Code wird nicht verraten
      expect(j['port'], host.port);
      client.close(force: true);
      await host.stop();
    });

    test('Suchziele: eigenes /24-Netz ohne eigene Adresse', () async {
      final targets = await Link.scanTargets();
      final own = await Link.localAddresses();
      for (final a in own) {
        expect(targets.contains(a), isFalse);
      }
    });

    test('Spielerdaten über die Kopplung senden', () async {
      final host = Link.forTest();
      await host.startHost(preferredPort: 0);
      final guest = Link.forTest();
      final got = Completer<Map<String, dynamic>>();
      host.onShare = (pkg, from) => got.complete(pkg);
      expect(await guest.join('127.0.0.1', host.port, host.code!), isTrue);
      playMatch(gp('Simon'), gp('Max'));
      guest.sendShare(Sync.build({for (final p in Store.profiles) p.id}));
      final pkg = SharePackage.fromJson(await got.future.timeout(const Duration(seconds: 3)));
      expect(pkg.profiles.length, 2);
      expect(pkg.entries.length, 2);
      await guest.stop();
      await host.stop();
    });
  });
}

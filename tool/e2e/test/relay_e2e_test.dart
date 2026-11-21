// Ende-zu-Ende-Test: echter Server (server/bin/server.dart) + Host + 2 Gäste als reine Protokoll-Clients.
//
// Ablauf wie in der App: Umschläge (RelayFrame) mit unveränderten Link-Nachrichten im Feld `d`.
// Der "Host" hier ist eine Mini-Schiedsstelle (X01 501, Double-Out) – der Server versteht davon nichts,
// er reicht nur weiter. Geprüft werden Weiterleitung, Zielgenauigkeit, Host-Abbruch + Zurückholen mit
// Token, Kick, Raum schließen mit 4000, Fehlercodes und dass Namen nicht in den Server-Logs landen.
//
// Aufruf:  cd tool/e2e && dart pub get && dart test
// Ohne server/ überspringt sich der Test (siehe README.md).

import 'dart:convert';

import 'package:darts_e2e/e2e.dart';
import 'package:test/test.dart';

/// Mini-X01 auf dem Host: zwei Spieler, je 3 Darts, 501 Double-Out.
class MiniX01 {
  MiniX01(this.players);

  final List<String> players; // Gast-IDs in Wurfreihenfolge
  final scores = <String, int>{};
  final _history = <({String peer, int before, int turn, int darts})>[];
  int turn = 0;
  int dartsInTurn = 0;
  int turnStart = 501;
  String? winner;
  int version = 0;

  void reset() {
    for (final p in players) {
      scores[p] = 501;
    }
    turn = 0;
    dartsInTurn = 0;
    turnStart = 501;
  }

  String get current => players[turn];

  /// Wurf anwenden; false = nicht dran / Spiel vorbei.
  bool dart(String peer, int seg, int mul) {
    if (winner != null || peer != current) return false;
    _history.add((peer: peer, before: scores[peer]!, turn: turn, darts: dartsInTurn));
    if (dartsInTurn == 0) turnStart = scores[peer]!;
    final rest = scores[peer]! - seg * mul;
    dartsInTurn++;
    if (rest == 0 && mul == 2) {
      scores[peer] = 0;
      winner = peer;
    } else if (rest < 2) {
      // Überworfen: zurück auf Stand vor der Aufnahme, Nächster ist dran.
      scores[peer] = turnStart;
      _next();
    } else {
      scores[peer] = rest;
      if (dartsInTurn == 3) _next();
    }
    version++;
    return true;
  }

  bool undo(String peer) {
    if (_history.isEmpty || _history.last.peer != peer || winner != null) return false;
    final h = _history.removeLast();
    scores[h.peer] = h.before;
    turn = h.turn;
    dartsInTurn = h.darts;
    version++;
    return true;
  }

  void _next() {
    turn = (turn + 1) % players.length;
    dartsInTurn = 0;
  }

  Map<String, Object?> state() => {
        't': 'state',
        'v': version,
        'scores': {for (final p in players) p: scores[p]},
        'turn': current,
        'winner': winner,
      };
}

void main() {
  final skip = skipReason();
  if (skip != null) {
    // ignore: avoid_print
    print('HINWEIS: $skip');
  }

  group('Relais E2E', skip: skip, () {
    late ServerUnderTest server;
    late RelayClient host, g1, g2;
    late String room, token, p1, p2;
    late MiniX01 game;

    setUpAll(() async {
      server = await ServerUnderTest.start();
    });

    tearDownAll(() async {
      await server.stop();
    });

    test('HTTP: /health, /version.json, /apk, Web-App', () async {
      final h = await server.get('/health');
      expect(h.status, 200);

      final v = await server.get('/version.json');
      expect(v.status, 200);
      final info = VersionInfo.fromJson(Map<String, dynamic>.from(jsonDecode(utf8.decode(v.body)) as Map));
      if (server.local) {
        expect(info.version, testVersion.version);
        expect(info.build, testVersion.build);
        expect(info.minProtocol, testVersion.minProtocol);
        expect(info.apkUrl, testVersion.apkUrl);

        final apk = await server.get('/apk/Darts_3.0.0.apk');
        expect(apk.status, 200);
        expect(apk.body, testApkBytes);

        final web = await server.get('/');
        expect(web.status, 200);
        expect(utf8.decode(web.body), contains('web-ok'));

        final missing = await server.get('/apk/gibtsnicht.apk');
        expect(missing.status, 404);
      } else {
        expect(info.build, greaterThan(0));
      }
    });

    test('Raum öffnen, 2 Gäste treten bei, Freigabe (hello → pending/welcome + state)', () async {
      host = await RelayClient.connect(server.wsUri, 'host');
      host.send(RelayFrame.host(app: '3.0.0'));
      final hosted = await host.expect('hosted');
      room = hosted.str('room')!;
      token = hosted.str('token')!;
      expect(RoomCode.isValid(room), isTrue, reason: 'Raum-Code $room');
      expect(token.length, greaterThanOrEqualTo(16));
      expect(hosted.flag('resumed'), isFalse);

      // Gast 1
      g1 = await RelayClient.connect(server.wsUri, 'gast1');
      g1.send(RelayFrame.join(app: '3.0.0', room: room));
      final j1 = await g1.expect('joined');
      p1 = j1.str('peer')!;
      expect(j1.flag('hostOnline'), isTrue);
      await host.expect('peer+', where: (f) => f.str('peer') == p1);

      // Gast 2
      g2 = await RelayClient.connect(server.wsUri, 'gast2');
      g2.send(RelayFrame.join(app: '3.0.0', room: room));
      final j2 = await g2.expect('joined');
      p2 = j2.str('peer')!;
      expect(p2, isNot(p1));
      await host.expect('peer+', where: (f) => f.str('peer') == p2);

      game = MiniX01([p1, p2])..reset();

      // Gast 1: bekanntes Protokoll – hello, Host antwortet welcome + state (nur an ihn)
      g1.send(RelayFrame.toHost(link({'t': 'hello', 'device': 'dev-anna-e2e', 'name': 'Anna E2E'})));
      final hello1 = await host.expectFrom(p1, 'hello');
      expect(hello1['name'], 'Anna E2E');
      host.send(RelayFrame.to(p1, link({'t': 'welcome', 'key': 'k' * 32, 'hostDevice': 'dev-host-e2e'})));
      host.send(RelayFrame.to(p1, link({...game.state(), 'full': true})));
      final w1 = await g1.expectLink('welcome');
      expect(w1['hostDevice'], 'dev-host-e2e');
      final s1 = await g1.expectLink('state');
      expect(s1['full'], isTrue);

      // "to" ist zielgenau: Gast 2 hat nichts davon bekommen.
      expect(await g2.receivesNothing((f) => f.type == 'd'), isTrue);

      // Gast 2: erst "pending" (Host fragt nach), dann Freigabe
      g2.send(RelayFrame.toHost(link({'t': 'hello', 'device': 'dev-ben-e2e', 'name': 'Ben E2E'})));
      await host.expectFrom(p2, 'hello');
      host.send(RelayFrame.to(p2, link({'t': 'pending'})));
      await g2.expectLink('pending');
      host.send(RelayFrame.to(p2, link({'t': 'welcome', 'key': 'q' * 32, 'hostDevice': 'dev-host-e2e'})));
      host.send(RelayFrame.to(p2, link({...game.state(), 'full': true})));
      await g2.expectLink('welcome');
      await g2.expectLink('state');
      expect(await g1.receivesNothing((f) => f.type == 'd', wait: const Duration(milliseconds: 200)), isTrue);
    });

    test('Ping → Pong', () async {
      g1.send(RelayFrame.ping());
      await g1.expect('pong');
      host.send(RelayFrame.ping());
      await host.expect('pong');
    });

    /// Gast wirft, Host wendet an und verteilt den Stand an alle; beide Gäste prüfen ihn.
    Future<void> throwDart(RelayClient guest, String peer, int seg, int mul) async {
      guest.send(RelayFrame.toHost(link({'t': 'dart', 'seg': seg, 'mul': mul})));
      final msg = await host.expectFrom(peer, 'dart');
      expect(game.dart(peer, msg['seg'] as int, msg['mul'] as int), isTrue, reason: '$peer ist nicht dran');
      host.send(RelayFrame.all(link(game.state())));
      for (final g in [g1, g2]) {
        final s = await g.expectLink('state', timeout: const Duration(seconds: 5));
        expect(s['v'], game.version);
        expect(Map<String, dynamic>.from(s['scores'] as Map), game.scores);
      }
    }

    test('X01 501 über das Relais bis zum Sieg (mit Undo)', () async {
      // Anna: 180
      for (var i = 0; i < 3; i++) {
        await throwDart(g1, p1, 20, 3);
      }
      // Ben: Fehlwurf 1, Undo, dann 180
      await throwDart(g2, p2, 1, 1);
      g2.send(RelayFrame.toHost(link({'t': 'undo'})));
      await host.expectFrom(p2, 'undo');
      expect(game.undo(p2), isTrue);
      host.send(RelayFrame.all(link(game.state())));
      for (final g in [g1, g2]) {
        final s = await g.expectLink('state');
        expect((s['scores'] as Map)[p2], 501);
      }
      for (var i = 0; i < 3; i++) {
        await throwDart(g2, p2, 20, 3);
      }
      // Anna: 180 → 141
      for (var i = 0; i < 3; i++) {
        await throwDart(g1, p1, 20, 3);
      }
      // Ben: 60 → 261
      for (var i = 0; i < 3; i++) {
        await throwDart(g2, p2, 20, 1);
      }
      // Anna checkt 141: T20 T19 D12
      await throwDart(g1, p1, 20, 3);
      await throwDart(g1, p1, 19, 3);
      await throwDart(g1, p1, 12, 2);
      expect(game.winner, p1);
      expect(game.scores[p1], 0);
      expect(game.scores[p2], 261);
    });

    test('Fehler: unbekannter Raum, zu alte Protokollversion', () async {
      // Ein gültiger, aber (sehr wahrscheinlich) nicht vergebener Code
      var other = RoomCode.generate();
      while (other == room) {
        other = RoomCode.generate();
      }
      final x = await RelayClient.connect(server.wsUri, 'fremd');
      x.send(RelayFrame.join(app: '3.0.0', room: other));
      final e = await x.expect('error');
      expect(e.str('code'), RelayError.noRoom.name);
      await x.close();

      final old = await RelayClient.connect(server.wsUri, 'alt');
      old.sendRaw(jsonEncode({'r': 'join', 'proto': 2, 'app': '2.10.1', 'room': room}));
      final u = await old.expect('error');
      expect(u.str('code'), RelayError.update.name);
      await old.close();
    });

    test('Host bricht ab → hostOffline; falsches Token abgewiesen; Zurückholen mit Token', () async {
      // Normale Trennung (kein 4000) = nur "Host offline", Raum bleibt.
      await host.close(1000, 'weg');
      await g1.expect('hostOffline');
      await g2.expect('hostOffline');

      final fake = await RelayClient.connect(server.wsUri, 'falscherHost');
      fake.send(RelayFrame.host(app: '3.0.0', room: room, token: '00' * 24));
      final e = await fake.expect('error');
      expect(e.str('code'), RelayError.token.name);
      await fake.close();
      // Gäste merken davon nichts
      expect(await g1.receivesNothing((f) => f.type == 'hostOnline', wait: const Duration(milliseconds: 200)), isTrue);

      host = await RelayClient.connect(server.wsUri, 'host2');
      host.send(RelayFrame.host(app: '3.0.0', room: room, token: token));
      final hosted = await host.expect('hosted');
      expect(hosted.str('room'), room);
      expect(hosted.flag('resumed'), isTrue);
      await g1.expect('hostOnline');
      await g2.expect('hostOnline');

      // Spielstand liegt beim Host und wird wie in der App neu verteilt.
      host.send(RelayFrame.all(link({...game.state(), 'full': true})));
      for (final g in [g1, g2]) {
        final s = await g.expectLink('state');
        expect(s['winner'], p1);
      }
      // Weg Gast → Host geht auch nach dem Zurückholen (gleiche Gast-IDs).
      g1.send(RelayFrame.toHost(link({'t': 'mode', 'viewer': true})));
      final m = await host.expectFrom(p1, 'mode');
      expect(m['viewer'], isTrue);
    });

    test('Kick: Gast 2 wird getrennt und bekommt nichts mehr', () async {
      host.send(RelayFrame.kick(p2));
      await host.expect('peer-', where: (f) => f.str('peer') == p2);
      host.send(RelayFrame.all(link({'t': 'state', 'v': 999})));
      await g1.expectLink('state');
      expect(await g2.receivesNothing((f) => f.type == 'd'), isTrue);
    });

    test('Host schließt den Raum (Close-Code 4000) → closed, Raum weg', () async {
      await host.close(4000, 'Raum schließen');
      await g1.expect('closed');

      final spaet = await RelayClient.connect(server.wsUri, 'spaet');
      spaet.send(RelayFrame.join(app: '3.0.0', room: room));
      final e = await spaet.expect('error');
      expect(e.str('code'), RelayError.noRoom.name);
      await spaet.close();
      await g1.close();
      if (!g2.isClosed) await g2.close();
    });

    test('Datenschutz: keine Namen, Geräte-IDs oder Tokens in den Server-Logs', () async {
      if (!server.local) {
        markTestSkipped('nur mit lokal gestartetem Server');
        return;
      }
      final logs = server.output.toString();
      for (final secret in ['Anna E2E', 'Ben E2E', 'dev-anna-e2e', 'dev-ben-e2e', token]) {
        expect(logs.contains(secret), isFalse, reason: '"$secret" steht im Server-Log');
      }
    });
  });
}

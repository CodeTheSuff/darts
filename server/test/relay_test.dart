import 'dart:convert';
import 'dart:io';

import 'package:darts_protocol/darts_protocol.dart';
import 'package:darts_server/darts_server.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('Räume und Weiterleitung', () {
    test('Raum erstellen: Code, Token, nicht zurückgeholt', () async {
      final s = await startServer(testConfig());
      final host = await Client.connect(s);
      host.send(RelayFrame.host(app: 'test'));
      final f = await host.expectFrame('hosted');
      expect(RoomCode.isValid(f.str('room')!), isTrue);
      expect(f.str('token'), matches(RegExp(r'^[0-9a-f]{48}$')));
      expect(f.flag('resumed'), isFalse);
      expect(s.hub.roomCount, 1);
      expect(s.hub.hasRoom(f.str('room')!), isTrue);
    });

    test('Gast tritt bei (Code auch mit Leerzeichen/klein), Host bekommt peer+', () async {
      final s = await startServer(testConfig());
      final r = await openRoom(s);
      final pretty = RoomCode.pretty(r.room).toLowerCase();
      final g = await joinRoom(s, pretty);
      expect(g.peer, 'p1');
      final pj = await r.host.expectFrame('peer+');
      expect(pj.str('peer'), 'p1');
    });

    test('Weiterleitung in beide Richtungen: to, all, d → from', () async {
      final s = await startServer(testConfig());
      final r = await openRoom(s);
      final g1 = await joinRoom(s, r.room);
      await r.host.expectFrame('peer+');
      final g2 = await joinRoom(s, r.room);
      await r.host.expectFrame('peer+');
      expect(g2.peer, 'p2');

      const msg = '{"t":"hello","name":"x"}';
      g1.guest.send(RelayFrame.toHost(msg));
      final from = await r.host.expectFrame('from');
      expect(from.str('peer'), 'p1');
      expect(from.str('d'), msg);

      g2.guest.send(RelayFrame.toHost('zwei'));
      final from2 = await r.host.expectFrame('from');
      expect(from2.str('peer'), 'p2');
      expect(from2.str('d'), 'zwei');

      r.host.send(RelayFrame.to('p2', 'nur für p2'));
      expect((await g2.guest.expectFrame('d')).str('d'), 'nur für p2');
      await g1.guest.expectSilence();

      r.host.send(RelayFrame.all('an alle'));
      expect((await g1.guest.expectFrame('d')).str('d'), 'an alle');
      expect((await g2.guest.expectFrame('d')).str('d'), 'an alle');

      // An unbekannten Gast: still verworfen, Host bleibt verbunden.
      r.host.send(RelayFrame.to('p99', 'weg'));
      r.host.send(RelayFrame.ping());
      await r.host.expectFrame('pong');
    });

    test('Gast-IDs fortlaufend, peer- beim Trennen, IDs nicht wiederverwendet', () async {
      final s = await startServer(testConfig());
      final r = await openRoom(s);
      final g1 = await joinRoom(s, r.room);
      final g2 = await joinRoom(s, r.room);
      final g3 = await joinRoom(s, r.room);
      expect([g1.peer, g2.peer, g3.peer], ['p1', 'p2', 'p3']);
      for (final _ in [1, 2, 3]) {
        await r.host.expectFrame('peer+');
      }
      await g2.guest.close();
      expect((await r.host.expectFrame('peer-')).str('peer'), 'p2');
      final g4 = await joinRoom(s, r.room);
      expect(g4.peer, 'p4');
      expect((await r.host.expectFrame('peer+')).str('peer'), 'p4');
    });

    test('Host kick → Gast getrennt (4002), Host bekommt peer-', () async {
      final s = await startServer(testConfig());
      final r = await openRoom(s);
      final g = await joinRoom(s, r.room);
      await r.host.expectFrame('peer+');
      r.host.send(RelayFrame.kick(g.peer));
      expect(await g.guest.expectClosed(), CloseCodes.kicked);
      expect((await r.host.expectFrame('peer-')).str('peer'), g.peer);
    });

    test('Gast-Frames, die nur der Host darf → error bad, Verbindung bleibt', () async {
      final s = await startServer(testConfig());
      final r = await openRoom(s);
      final g = await joinRoom(s, r.room);
      g.guest.send(RelayFrame.all('x'));
      await g.guest.expectError(RelayError.bad);
      g.guest.send(RelayFrame.ping());
      await g.guest.expectFrame('pong');
      r.host.send(RelayFrame.toHost('x'));
      await r.host.expectFrame('peer+');
      await r.host.expectError(RelayError.bad);
    });
  });

  group('Host offline / zurückholen', () {
    test('Host trennt → hostOffline; Gast-Nachrichten verworfen; mit Token zurückholen', () async {
      final s = await startServer(testConfig());
      final r = await openRoom(s);
      final g = await joinRoom(s, r.room);
      await r.host.expectFrame('peer+');

      await r.host.close(WebSocketStatus.normalClosure);
      await g.guest.expectFrame('hostOffline');
      expect(s.hub.hasRoom(r.room), isTrue);
      g.guest.send(RelayFrame.toHost('verloren')); // wird verworfen

      // Neuer Gast, während der Host weg ist.
      final g2 = await joinRoom(s, r.room, hostOnline: false);

      final h2 = await Client.connect(s);
      h2.send(RelayFrame.host(app: 'test', room: r.room, token: r.token));
      final f = await h2.expectFrame('hosted');
      expect(f.str('room'), r.room);
      expect(f.str('token'), r.token);
      expect(f.flag('resumed'), isTrue);
      final peers = {(await h2.expectFrame('peer+')).str('peer'), (await h2.expectFrame('peer+')).str('peer')};
      expect(peers, {'p1', 'p2'});
      await g.guest.expectFrame('hostOnline');
      await g2.guest.expectFrame('hostOnline');

      g.guest.send(RelayFrame.toHost('wieder da'));
      final from = await h2.expectFrame('from');
      expect(from.str('d'), 'wieder da'); // „verloren“ kam nie an
    });

    test('Neue Host-Verbindung ersetzt die alte (4001)', () async {
      final s = await startServer(testConfig());
      final r = await openRoom(s);
      final g = await joinRoom(s, r.room);
      await r.host.expectFrame('peer+');
      final h2 = await Client.connect(s);
      h2.send(RelayFrame.host(app: 'test', room: r.room, token: r.token));
      expect((await h2.expectFrame('hosted')).flag('resumed'), isTrue);
      await h2.expectFrame('peer+');
      expect(await r.host.expectClosed(), CloseCodes.replaced);
      await g.guest.expectFrame('hostOnline');
      // Die alte Verbindung löst kein hostOffline aus.
      await g.guest.expectSilence();
      h2.send(RelayFrame.to(g.peer, 'neu'));
      expect((await g.guest.expectFrame('d')).str('d'), 'neu');
    });

    test('Falsches Token → error token und Trennung, Raum bleibt', () async {
      final s = await startServer(testConfig());
      final r = await openRoom(s);
      final h2 = await Client.connect(s);
      h2.send(RelayFrame.host(app: 'test', room: r.room, token: 'f' * 48));
      await h2.expectError(RelayError.token);
      expect(await h2.expectClosed(), CloseCodes.policy);
      r.host.send(RelayFrame.ping());
      await r.host.expectFrame('pong');
    });

    test('Nach Server-Neustart: Raum mit demselben Code und Token neu anlegen', () async {
      final s1 = await startServer(testConfig());
      final r = await openRoom(s1);
      await s1.stop();
      expect(await r.host.expectClosed(), WebSocketStatus.goingAway);

      final s2 = await startServer(testConfig());
      final h = await Client.connect(s2);
      h.send(RelayFrame.host(app: 'test', room: r.room, token: r.token));
      final f = await h.expectFrame('hosted');
      expect(f.str('room'), r.room);
      expect(f.str('token'), r.token);
      expect(f.flag('resumed'), isFalse);
      final g = await joinRoom(s2, r.room);
      expect(g.peer, 'p1');
      // Danach gilt das Token wie gewohnt.
      final bad = await Client.connect(s2);
      bad.send(RelayFrame.host(app: 'test', room: r.room, token: 'a' * 48));
      await bad.expectError(RelayError.token);
    });

    test('Ungültiger Code beim Zurückholen → neuer Raum', () async {
      final s = await startServer(testConfig());
      final h = await Client.connect(s);
      h.send(RelayFrame.host(app: 'test', room: 'OOO000', token: 'a' * 48));
      final f = await h.expectFrame('hosted');
      expect(f.str('room'), isNot('OOO000'));
      expect(f.str('token'), isNot('a' * 48));
    });

    test('Close-Code 4000 → Raum gelöscht, Gäste bekommen closed und werden getrennt', () async {
      final s = await startServer(testConfig());
      final r = await openRoom(s);
      final g1 = await joinRoom(s, r.room);
      final g2 = await joinRoom(s, r.room);
      await r.host.close(CloseCodes.hostClosesRoom);
      await g1.guest.expectFrame('closed');
      await g2.guest.expectFrame('closed');
      expect(await g1.guest.expectClosed(), WebSocketStatus.normalClosure);
      expect(await g2.guest.expectClosed(), WebSocketStatus.normalClosure);
      expect(s.hub.hasRoom(r.room), isFalse);
      final g3 = await Client.connect(s);
      g3.send(RelayFrame.join(app: 'test', room: r.room));
      await g3.expectError(RelayError.noRoom);
    });
  });

  group('Grenzen und Schutz', () {
    test('Raum voll → error full', () async {
      final s = await startServer(testConfig(maxPeersPerRoom: 2));
      final r = await openRoom(s);
      await joinRoom(s, r.room);
      await joinRoom(s, r.room);
      final g3 = await Client.connect(s);
      g3.send(RelayFrame.join(app: 'test', room: r.room));
      await g3.expectError(RelayError.full);
      await g3.expectClosed();
    });

    test('MAX_ROOMS → error busy', () async {
      final s = await startServer(testConfig(maxRooms: 1));
      await openRoom(s);
      final h = await Client.connect(s);
      h.send(RelayFrame.host(app: 'test'));
      await h.expectError(RelayError.busy);
      await h.expectClosed();
    });

    test('Unbekannter Raum → noRoom; nach zu vielen Fehlversuchen Sperre je IP', () async {
      final s = await startServer(testConfig(maxBadJoins: 3, blockFor: const Duration(milliseconds: 600)));
      final r = await openRoom(s);
      for (var i = 0; i < 3; i++) {
        final g = await Client.connect(s);
        g.send(RelayFrame.join(app: 'test', room: 'ZZZZZZ'));
        await g.expectError(RelayError.noRoom);
        await g.expectClosed();
      }
      // Jetzt gesperrt – auch für den richtigen Code.
      final blocked = await Client.connect(s);
      blocked.send(RelayFrame.join(app: 'test', room: r.room));
      await blocked.expectError(RelayError.rate);
      await blocked.expectClosed();
      // Nach Ablauf der Sperre geht es wieder.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await joinRoom(s, r.room);
    });

    test('TRUST_PROXY: Sperre gilt je IP aus X-Forwarded-For', () async {
      final s = await startServer(testConfig(maxBadJoins: 2, trustProxy: true));
      final r = await openRoom(s);
      Future<Client> fromIp(String ip) => Client.connect(s, headers: {'X-Forwarded-For': '9.9.9.9, $ip'});
      for (var i = 0; i < 2; i++) {
        final g = await fromIp('10.0.0.1');
        g.send(RelayFrame.join(app: 'test', room: 'ZZZZZZ'));
        await g.expectError(RelayError.noRoom);
      }
      final blocked = await fromIp('10.0.0.1');
      blocked.send(RelayFrame.join(app: 'test', room: r.room));
      await blocked.expectError(RelayError.rate);
      final other = await fromIp('10.0.0.2');
      other.send(RelayFrame.join(app: 'test', room: r.room));
      await other.expectFrame('joined');
    });

    test('Rate-Limit → error rate und Trennung', () async {
      final s = await startServer(testConfig(messagesPerSecond: 5, burst: 10));
      final r = await openRoom(s);
      for (var i = 0; i < 30; i++) {
        r.host.send(RelayFrame.ping());
      }
      var pongs = 0;
      while (true) {
        final f = await r.host.next();
        if (f.type == 'pong') {
          pongs++;
          continue;
        }
        expect(f.type, 'error');
        expect(f.str('code'), RelayError.rate.name);
        break;
      }
      expect(pongs, lessThan(30));
      expect(await r.host.expectClosed(), CloseCodes.policy);
    });

    test('Zu großer Frame → error bad und Trennung', () async {
      final s = await startServer(testConfig(maxFrameBytes: 1000));
      final r = await openRoom(s);
      r.host.send(RelayFrame.all('x' * 1500));
      await r.host.expectError(RelayError.bad);
      expect(await r.host.expectClosed(), CloseCodes.policy);
    });

    test('Riesiger Frame wird schon auf Socket-Ebene abgebrochen', () async {
      final s = await startServer(testConfig(maxFrameBytes: 1000));
      final r = await openRoom(s);
      r.host.sendRaw('y' * 100000);
      await r.host.expectClosed();
      await eventually(() => s.hub.connectionCount == 0);
    });

    test('Kaputter Frame → error bad und Trennung; Binär-Frame ebenso', () async {
      final s = await startServer(testConfig());
      final r = await openRoom(s);
      r.host.sendRaw('kein json');
      await r.host.expectError(RelayError.bad);
      await r.host.expectClosed();

      final r2 = await openRoom(s);
      r2.host.sendRaw(utf8.encode('{"r":"ping"}'));
      await r2.host.expectError(RelayError.bad);
      await r2.host.expectClosed();
    });

    test('Erster Frame muss host oder join sein', () async {
      final s = await startServer(testConfig());
      final c = await Client.connect(s);
      c.send(RelayFrame.ping());
      await c.expectError(RelayError.bad);
      await c.expectClosed();
    });

    test('Hello-Timeout: ohne host/join getrennt', () async {
      final s = await startServer(testConfig(helloTimeout: const Duration(milliseconds: 200)));
      final c = await Client.connect(s);
      expect(await c.expectClosed(), CloseCodes.timeout);
      await eventually(() => s.hub.connectionCount == 0);
    });

    test('Idle-Timeout: stiller Host wird getrennt, Gäste bekommen hostOffline', () async {
      final s = await startServer(testConfig(idleTimeout: const Duration(milliseconds: 400)));
      final r = await openRoom(s);
      final g = await joinRoom(s, r.room);
      // Der Gast hält sich mit Pings am Leben, der Host schweigt.
      var offline = false;
      for (var i = 0; i < 6 && !offline; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        g.guest.send(RelayFrame.ping());
        var f = await g.guest.next();
        if (f.type == 'hostOffline') {
          offline = true;
          f = await g.guest.next();
        }
        expect(f.type, 'pong');
      }
      expect(offline, isTrue);
      await r.host.expectFrame('peer+');
      expect(await r.host.expectClosed(), CloseCodes.timeout);
    });

    test('Veraltetes Protokoll → error update mit Version und APK-Link', () async {
      final dir = await Directory.systemTemp.createTemp('darts_v');
      addTearDown(() => dir.delete(recursive: true));
      final vf = File('${dir.path}/version.json');
      await vf.writeAsString(jsonEncode(const VersionInfo(
        version: '3.0.0',
        build: 20,
        minProtocol: 3,
        apkUrl: '/apk/Darts_3.0.0.apk',
        notes: ['Neu'],
      ).toJson()));
      final s = await startServer(testConfig(versionFile: vf.path, publicUrl: 'https://darts.example.org', minProtocol: 4));
      final c = await Client.connect(s);
      c.send(RelayFrame.host(app: 'alt')); // proto 3 < 4
      final e = await c.expectError(RelayError.update);
      expect(e.fields['update'], {'version': '3.0.0', 'apk': 'https://darts.example.org/apk/Darts_3.0.0.apk'});
      await c.expectClosed();
      expect(s.hub.roomCount, 0);

      // Ganz ohne proto (Fremd-Client) ebenso.
      final c2 = await Client.connect(s);
      c2.sendRaw('{"r":"join","room":"ABCDEF"}');
      await c2.expectError(RelayError.update);
    });

    test('error update ohne version.json: ohne update-Feld', () async {
      final s = await startServer(testConfig(minProtocol: 99));
      final c = await Client.connect(s);
      c.send(RelayFrame.join(app: 'alt', room: 'ABCDEF'));
      final e = await c.expectError(RelayError.update);
      expect(e.fields.containsKey('update'), isFalse);
    });

    test('TTL: inaktiver Raum wird aufgeräumt, aktiver bleibt', () async {
      final s = await startServer(testConfig(roomTtl: const Duration(milliseconds: 300)));
      final idle = await openRoom(s);
      await idle.host.close();
      final active = await openRoom(s);
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        active.host.send(RelayFrame.ping());
        await active.host.expectFrame('pong');
      }
      expect(s.hub.hasRoom(idle.room), isFalse);
      expect(s.hub.hasRoom(active.room), isTrue);
      final g = await Client.connect(s);
      g.send(RelayFrame.join(app: 'test', room: idle.room));
      await g.expectError(RelayError.noRoom);
    });

    test('Keine Inhalte und keine vollen Codes im Log', () async {
      final lines = <String>[];
      final s = await startServer(testConfig(), logLines: lines);
      final r = await openRoom(s);
      final g = await joinRoom(s, r.room);
      g.guest.send(RelayFrame.toHost('GEHEIMER-INHALT Simon'));
      await r.host.expectFrame('peer+');
      await r.host.expectFrame('from');
      await r.host.close(CloseCodes.hostClosesRoom);
      await g.guest.expectFrame('closed');
      expect(lines, isNotEmpty);
      final all = lines.join('\n');
      expect(all, isNot(contains('GEHEIM')));
      expect(all, isNot(contains('Simon')));
      expect(all, isNot(contains(r.room)));
      expect(all, isNot(contains(r.token)));
      expect(all, isNot(contains('127.0.0.1')));
    });
  });
}

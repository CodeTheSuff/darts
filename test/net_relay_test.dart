import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/net/link.dart';
import 'package:darts_counter/net/relay.dart';
import 'package:darts_protocol/darts_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'net_test_relay.dart';

/// Online-Kopplung über das Relais: dasselbe Link-Protokoll wie im WLAN.
Future<void> _wait(bool Function() cond, {int ms = 4000}) async {
  for (var i = 0; i < ms ~/ 20 && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late TestRelay relay;
  final links = <Link>[];

  Link mk({String? device}) {
    final l = Link.forTest()..deviceForTest = device;
    links.add(l);
    return l;
  }

  /// Host, der neue Geräte erst nach Nachfrage zulässt.
  Future<(Link, List<String>)> strictHost({bool allow = true, Map<String, dynamic> Function()? state}) async {
    final asked = <String>[];
    final host = mk()..trustAll = false;
    host.onJoinRequest = (dev, name) async {
      asked.add(dev);
      return allow;
    };
    host.hostState = state ?? () => {'match': null, 'tournament': null};
    await host.startOnlineHost();
    return (host, asked);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    RelayClient.retryDelays = const [Duration(milliseconds: 50)];
    relay = await TestRelay.start();
    Store.serverUrl = relay.url;
  });

  tearDown(() async {
    for (final l in links) {
      await l.stop();
    }
    links.clear();
    await relay.stop();
  });

  test('Online-Host öffnet einen Raum mit 6-stelligem Code und merkt sich Code + Token', () async {
    final (host, _) = await strictHost();
    expect(host.isOnline, isTrue);
    expect(host.isHost, isTrue);
    expect(RoomCode.isValid(host.code!), isTrue);
    expect(host.isConnected, isTrue);
    expect(Store.onlineRoom, host.code);
    expect(Store.onlineToken, isNotNull);
    expect(Link.recentSession()?['mode'], 'online');
  });

  test('Online-Host + 2 Gäste mit Freigabe: Würfe und Stand fließen', () async {
    var n = 0;
    final (host, asked) = await strictHost(state: () => {'match': {'n': n}, 'tournament': null});
    final got = <String>[];
    host.onHostMessage = (m) => got.add('${m['t']}:${m['_dev']}');

    final g1 = mk(device: 'g1'), g2 = mk(device: 'g2');
    final s1 = <Map<String, dynamic>>[], s2 = <Map<String, dynamic>>[];
    g1.onState = s1.add;
    g2.onState = s2.add;
    // Eingabe wird normalisiert (Kleinbuchstaben, Leerzeichen)
    final pretty = RoomCode.pretty(host.code!).toLowerCase();
    expect(await g1.joinOnline(pretty), isTrue);
    expect(await g2.joinOnline(host.code!), isTrue);
    await _wait(() => s1.isNotEmpty && s2.isNotEmpty);
    expect(asked, ['g1', 'g2']);
    expect(host.peerCount, 2);
    expect(g1.isConnected && g2.isConnected, isTrue);
    expect(g1.code, host.code);

    g1.sendToHost({'t': 'dart', 'mid': 'm', 'd': {'f': 20, 'm': 3}});
    g2.sendToHost({'t': 'undo', 'mid': 'm'});
    await _wait(() => got.length >= 2);
    expect(got, containsAll(['dart:g1', 'undo:g2']));

    n = 7;
    host.broadcastState();
    await _wait(() => (s1.last['match'] as Map)['n'] == 7 && (s2.last['match'] as Map)['n'] == 7);
    expect((s1.last['match'] as Map)['n'], 7);
    expect((s2.last['match'] as Map)['n'], 7);
    expect(s1.last['devices'], 3);
    // Online-Gast merkt sich den Raum (statt einer Adresse)
    final known = Store.knownHosts.single;
    expect(known.room, host.code);
    expect(known.online, isTrue);
    expect(known.key, isNotNull);
  });

  test('Abgelehnter Gast bekommt nichts und verlässt den Raum', () async {
    final (host, asked) = await strictHost(allow: false);
    final g = mk(device: 'g1');
    var states = 0;
    g.onState = (_) => states++;
    expect(await g.joinOnline(host.code!), isTrue);
    await _wait(() => g.denied);
    expect(asked, ['g1']);
    expect(g.denied, isTrue);
    expect(g.isConnected, isFalse);
    expect(states, 0);
    expect(host.peerCount, 0);
    await _wait(() => relay.rooms[host.code]!.guests.isEmpty);
    expect(relay.rooms[host.code]!.guests, isEmpty);
  });

  test('Bekanntes Gerät verbindet sich online mit Schlüssel ohne neue Freigabe', () async {
    final (host, asked) = await strictHost();
    final g = mk(device: 'g1');
    var s = 0;
    g.onState = (_) => s++;
    expect(await g.joinOnline(host.code!), isTrue);
    await _wait(() => s > 0);
    await g.stop();
    final known = Store.knownHosts.single;

    final again = mk(device: 'g1');
    var s2 = 0;
    again.onState = (_) => s2++;
    expect(await again.joinOnline(known.room!, hostDevice: known.device), isTrue);
    await _wait(() => s2 > 0);
    expect(s2, greaterThan(0));
    expect(asked, ['g1']);
    expect(again.isConnected, isTrue);
  });

  test('Host offline und zurück (Token): Gäste warten und verbinden sich ohne neue Freigabe', () async {
    final (host, asked) = await strictHost();
    final code = host.code!;
    final g = mk(device: 'g1');
    var s = 0;
    g.onState = (_) => s++;
    expect(await g.joinOnline(code), isTrue);
    await _wait(() => s > 0);

    await relay.dropHost(code);
    await _wait(() => g.relayStatus == RelayStatus.hostOffline);
    expect(g.relayStatus, RelayStatus.hostOffline);
    expect(g.status, contains('Host offline'));
    expect(g.isConnected, isFalse);

    final epoch = g.connectionEpoch;
    // Host baut die Verbindung selbst wieder auf und holt denselben Raum zurück.
    final before = s;
    await _wait(() => s > before && g.isConnected);
    // Neue Verbindung erkannt → die App gleicht offline Eingetragenes ab (Nachsync).
    expect(g.connectionEpoch, greaterThan(epoch));
    expect(g.hostCompat, linkCompat);
    expect(host.code, code);
    expect(host.isConnected, isTrue);
    expect(g.isConnected, isTrue);
    expect(host.peerCount, 1);
    expect(asked, ['g1']);
    expect(relay.received.where((t) => t == 'host').length, 2);
  });

  test('Host zurück ohne peer+-Meldung des Servers: Gast wird über seine Nachricht erkannt', () async {
    relay.announceOnResume = false;
    final (host, asked) = await strictHost();
    final g = mk(device: 'g1');
    var s = 0;
    g.onState = (_) => s++;
    expect(await g.joinOnline(host.code!), isTrue);
    await _wait(() => s > 0);
    await relay.dropHost(host.code!);
    await _wait(() => g.relayStatus == RelayStatus.hostOffline);
    final before = s;
    await _wait(() => s > before && g.isConnected);
    expect(g.isConnected, isTrue);
    expect(host.peerCount, 1);
    expect(asked, ['g1']);
  });

  test('Gast verliert die Verbindung zum Server und tritt demselben Raum wieder bei', () async {
    final (host, asked) = await strictHost();
    final g = mk(device: 'g1');
    var s = 0;
    g.onState = (_) => s++;
    expect(await g.joinOnline(host.code!), isTrue);
    await _wait(() => s > 0);
    final peer = relay.rooms[host.code]!.guests.keys.single;

    await relay.dropGuest(host.code!, peer);
    await _wait(() => !g.isConnected);
    final epoch = g.connectionEpoch;
    final before = s;
    await _wait(() => s > before && g.isConnected);
    expect(g.isConnected, isTrue);
    expect(host.peerCount, 1);
    expect(relay.rooms[host.code]!.guests.keys.single, isNot(peer));
    expect(g.connectionEpoch, greaterThan(epoch));
    expect(asked, ['g1']);
  });

  test('Host-Neustart holt denselben Raum mit gespeichertem Token zurück', () async {
    final (host, _) = await strictHost();
    final code = host.code!;
    await host.stop(); // nur „offline“, Raum bleibt
    expect(relay.rooms.containsKey(code), isTrue);
    final again = mk()..trustAll = false;
    again.hostState = () => {'match': null};
    await again.startOnlineHost();
    expect(again.code, code);
  });

  test('Falsches Token: es wird ein neuer Raum geöffnet', () async {
    final (host, _) = await strictHost();
    final code = host.code!;
    await host.stop();
    Store.onlineToken = 'falsch';
    final again = mk();
    again.hostState = () => {'match': null};
    await again.startOnlineHost();
    expect(again.code, isNot(code));
    expect(Store.onlineRoom, again.code);
  });

  test('Ersetzte Host-Verbindung (Close-Code 4001) verbindet sich nicht neu', () async {
    final (host, _) = await strictHost();
    await relay.replaceHost(host.code!);
    await _wait(() => host.relayStatus == RelayStatus.failed);
    expect(host.relayStatus, RelayStatus.failed);
    expect(host.isConnected, isFalse);
    expect(host.status, contains('anderen Verbindung'));
    final hosts = relay.received.where((t) => t == 'host').length;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(relay.received.where((t) => t == 'host').length, hosts);
  });

  test('Raum schließen (Close-Code 4000): Gast wird getrennt und verbindet sich nicht neu', () async {
    final (host, _) = await strictHost();
    final code = host.code!;
    final g = mk(device: 'g1');
    var s = 0;
    g.onState = (_) => s++;
    expect(await g.joinOnline(code), isTrue);
    await _wait(() => s > 0);

    await host.leave();
    await _wait(() => g.relayStatus == RelayStatus.closed);
    expect(g.relayStatus, RelayStatus.closed);
    expect(g.isConnected, isFalse);
    expect(g.status, contains('geschlossen'));
    expect(relay.rooms.containsKey(code), isFalse);
    expect(Link.recentSession(), isNull);
    final joins = relay.received.where((t) => t == 'join').length;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(relay.received.where((t) => t == 'join').length, joins);
  });

  test('Fehlermeldungen: falscher Code, ungültiger Code, Server weg, Raum voll', () async {
    final g = mk(device: 'g1');
    expect(await g.joinOnline('ABCDEF'), isFalse);
    expect(g.status, contains('Kein Raum'));
    expect(g.role, LinkRole.none);

    expect(await g.joinOnline('AB1'), isFalse);
    expect(g.status, contains('6 Zeichen'));

    final (host, _) = await strictHost();
    relay.maxPeers = 1;
    final g1 = mk(device: 'g1');
    expect(await g1.joinOnline(host.code!), isTrue);
    final g2 = mk(device: 'g2');
    expect(await g2.joinOnline(host.code!), isFalse);
    expect(g2.status, contains('voll'));

    final port = relay.port;
    await relay.stop();
    relay = await TestRelay.start(); // für tearDown
    final g3 = mk(device: 'g3');
    expect(await g3.joinOnline(host.code!, serverUrl: 'http://127.0.0.1:$port'), isFalse);
    expect(g3.status, contains('nicht erreichbar'));
    final h2 = mk();
    await expectLater(h2.startOnlineHost(serverUrl: 'http://127.0.0.1:$port'), throwsA(isA<LinkException>()));
    expect(h2.role, LinkRole.none);
  });

  test('App zu alt: Server meldet update → Update-Hinweis, Raum wird nicht geöffnet', () async {
    relay.minProtocol = relayProtocol + 1;
    final host = mk();
    Map<String, dynamic>? info;
    var called = 0;
    host.onUpdateRequired = (i) {
      called++;
      info = i;
    };
    await expectLater(host.startOnlineHost(), throwsA(isA<LinkException>()));
    expect(called, 1);
    expect(info?['apk'], 'apk/Darts_3.1.0.apk');
    expect(host.status, contains('zu alt'));

    final g = mk(device: 'g1');
    var gc = 0;
    g.onUpdateRequired = (_) => gc++;
    expect(await g.joinOnline('ABCDEF'), isFalse);
    expect(gc, 1);
  });

  test('Anzeige-Gerät online: bekommt den Stand, darf nichts eintragen; Turnier „unverändert“ kommt vollständig an', () async {
    final tour = {'id': 't1', 'name': 'Liga', 'big': List.filled(500, 'x')};
    final host = mk();
    host.hostState = () => {'match': null, 'tournament': tour};
    final received = <String>[];
    host.onHostMessage = (m) => received.add('${m['t']}');
    await host.startOnlineHost();
    final g = mk(device: 'tv');
    final got = <Map<String, dynamic>>[];
    g.onState = got.add;
    expect(await g.joinOnline(host.code!, viewer: true), isTrue);
    await _wait(() => got.isNotEmpty);
    expect(host.peerNames.single, contains('Anzeige'));
    expect(host.hasViewer, isTrue);
    g.sendToHost({'t': 'dart', 'mid': 'x', 'd': {'f': 20, 'm': 3}});
    host.broadcastState();
    await _wait(() => got.length >= 2);
    host.broadcastState();
    await _wait(() => got.length >= 3);
    expect(got.last['tsame'], isTrue);
    expect((got.last['tournament'] as Map)['name'], 'Liga');
    expect(received, isEmpty);
  });

  test('Abgleich (sync) läuft online über den Host zu den anderen Gästen', () async {
    final host = mk();
    host.hostState = () => {'match': null};
    final hostSync = <String>[];
    host.onSync = (m, reply, from) {
      hostSync.add('${m['t']}');
      if (m['t'] == 'have') reply({'t': 'syncpkg', 'pkg': <String, dynamic>{}});
    };
    await host.startOnlineHost();
    final g1 = mk(device: 'g1'), g2 = mk(device: 'g2');
    final g1Sync = <String>[], g2Sync = <String>[];
    g1.onSync = (m, _, _) => g1Sync.add('${m['t']}');
    g2.onSync = (m, _, _) => g2Sync.add('${m['t']}');
    var s = 0;
    g1.onState = (_) => s++;
    g2.onState = (_) => s++;
    await g1.joinOnline(host.code!);
    await g2.joinOnline(host.code!);
    await _wait(() => s >= 2 && host.peerCount == 2);
    g1.requestSync(() => {'x': 1});
    await _wait(() => g1Sync.contains('syncpkg'));
    expect(hostSync, contains('have'));
    expect(g1Sync, contains('syncpkg'));
    // syncpkg eines Gasts → der Host bittet die anderen um Abgleich
    g1.sendToHost({'t': 'syncpkg', 'pkg': <String, dynamic>{}});
    await _wait(() => g2Sync.contains('syncreq'));
    expect(g2Sync, contains('syncreq'));
    expect(g1Sync.where((t) => t == 'syncreq'), isEmpty);
  });

  test('Ping wird regelmäßig gesendet', () async {
    final host = mk();
    host.hostState = () => {'match': null};
    await host.startOnlineHost();
    final r = RelayHost(Uri.parse('ws://127.0.0.1:${relay.port}$relayPath'),
        pingEvery: const Duration(milliseconds: 40), idleTimeout: const Duration(seconds: 5));
    r.start();
    expect(await r.first, isNull);
    await _wait(() => relay.received.where((t) => t == 'ping').length >= 2, ms: 1000);
    expect(relay.received.where((t) => t == 'ping').length, greaterThanOrEqualTo(2));
    await r.close();
  });
}

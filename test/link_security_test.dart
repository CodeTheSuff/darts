import 'dart:convert';
import 'dart:io';

import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/net/link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Host, der nicht jedem automatisch vertraut.
Future<Link> _strictHost({required Future<bool> Function(String, String) ask}) async {
  final host = Link.forTest()..trustAll = false;
  host.onJoinRequest = ask;
  host.hostState = () => {'match': null, 'tournament': null};
  await host.startHost(preferredPort: 0);
  return host;
}

Future<void> _wait(bool Function() cond) async {
  for (var i = 0; i < 40 && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });

  test('Raumabfrage verrät den Code nicht', () async {
    final host = await _strictHost(ask: (_, _) async => false);
    final client = HttpClient();
    final res = await (await client.get('127.0.0.1', host.port, '/darts/info')).close();
    final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
    expect(j.containsKey('code'), isFalse);
    expect(j['port'], host.port);
    client.close(force: true);
    await host.stop();
  });

  test('Neues Gerät abgelehnt: bekommt keine Daten und wird getrennt', () async {
    var asked = 0;
    final host = await _strictHost(ask: (_, _) async {
      asked++;
      return false;
    });
    final guest = Link.forTest();
    var states = 0;
    guest.onState = (_) => states++;
    expect(await guest.join('127.0.0.1', host.port, host.code!), isTrue);
    await _wait(() => guest.denied);
    expect(asked, 1);
    expect(guest.denied, isTrue);
    expect(guest.isConnected, isFalse);
    expect(states, 0);
    expect(host.peerCount, 0);
    expect(Store.trustedGuests, isEmpty);
    await guest.stop();
    await host.stop();
  });

  test('Neues Gerät erlaubt: wird gemerkt und beim nächsten Mal nicht mehr gefragt', () async {
    var asked = 0;
    final host = await _strictHost(ask: (_, _) async {
      asked++;
      return true;
    });
    final guest = Link.forTest();
    var states = 0;
    guest.onState = (_) => states++;
    expect(await guest.join('127.0.0.1', host.port, host.code!), isTrue);
    await _wait(() => states > 0);
    expect(asked, 1);
    expect(guest.isConnected, isTrue);
    expect(host.peerCount, 1);
    expect(Store.isTrustedGuest(Store.deviceId), isTrue);
    await guest.stop();
    // Schlüssel wurde ausgetauscht und gemerkt
    final known = Store.knownHosts.single;
    expect(known.key, isNotNull);
    expect(known.key!.length, 64);
    // zweiter Beitritt per Schlüssel: ohne Code und ohne Nachfrage
    final again = Link.forTest();
    var s2 = 0;
    again.onState = (_) => s2++;
    expect(await again.join('127.0.0.1', host.port, '', hostDevice: known.device), isTrue);
    await _wait(() => s2 > 0);
    expect(s2, greaterThan(0));
    expect(asked, 1);
    await again.stop();
    await host.stop();
  });

  test('Nachrichten eines noch nicht erlaubten Geräts werden ignoriert', () async {
    final received = <String>[];
    final host = await _strictHost(ask: (_, _) => Future<bool>.delayed(const Duration(milliseconds: 400), () => false));
    host.onHostMessage = (m) => received.add('${m['t']}');
    final ws = await WebSocket.connect('ws://127.0.0.1:${host.port}/darts?code=${host.code}');
    ws.add(jsonEncode({'t': 'hello', 'device': 'fremd', 'name': 'Fremd'}));
    ws.add(jsonEncode({'t': 'dart', 'mid': 'x', 'd': {'f': 20, 'm': 3}}));
    ws.add(jsonEncode({'t': 'undo', 'mid': 'x'}));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(received, isEmpty);
    await ws.close();
    await host.stop();
  });

  test('Nach 5 falschen Codes wird die Adresse gesperrt', () async {
    final host = await _strictHost(ask: (_, _) async => true);
    final wrong = host.code == '0000' ? '1111' : '0000';
    for (var i = 0; i < Link.maxFails; i++) {
      expect(await Link.forTest().join('127.0.0.1', host.port, wrong), isFalse);
    }
    // jetzt auch mit richtigem Code gesperrt
    expect(await Link.forTest().join('127.0.0.1', host.port, host.code!), isFalse);
    await host.stop();
  });

  test('Unverändertes Turnier wird nicht erneut gesendet, kommt aber vollständig an', () async {
    final tour = {'id': 't1', 'name': 'Liga', 'big': List.filled(2000, 'x')};
    final host = Link.forTest();
    host.hostState = () => {'match': null, 'tournament': tour};
    await host.startHost(preferredPort: 0);
    final guest = Link.forTest();
    final got = <Map<String, dynamic>>[];
    guest.onState = got.add;
    expect(await guest.join('127.0.0.1', host.port, host.code!), isTrue);
    await _wait(() => got.isNotEmpty);
    host.broadcastState();
    await _wait(() => got.length >= 2);
    host.broadcastState();
    await _wait(() => got.length >= 3);
    expect(got.length, greaterThanOrEqualTo(3));
    expect(got.last['tsame'], isTrue);
    expect((got.last['tournament'] as Map)['name'], 'Liga');
    await guest.stop();
    await host.stop();
  });

  test('Falscher Host (anderer Schlüssel) wird erkannt, der Gast trennt sofort', () async {
    final host = await _strictHost(ask: (_, _) async => true);
    final guest = Link.forTest();
    var states = 0;
    guest.onState = (_) => states++;
    expect(await guest.join('127.0.0.1', host.port, host.code!), isTrue);
    await _wait(() => states > 0);
    await guest.stop();
    // Host kennt einen anderen Schlüssel → kann sich nicht ausweisen
    final dev = Store.knownHosts.single.device;
    Store.trustGuest(dev, 'Gerät', List.filled(64, 'f').join());
    final g2 = Link.forTest();
    var s2 = 0;
    g2.onState = (_) => s2++;
    await g2.join('127.0.0.1', host.port, '', hostDevice: dev);
    await _wait(() => g2.denied);
    expect(g2.denied, isTrue);
    expect(g2.status, contains('ausweisen'));
    expect(s2, 0);
    await g2.stop();
    await host.stop();
  });

  test('Schlüssel-Anmeldung ohne bekannten Schlüssel wird abgelehnt', () async {
    final host = await _strictHost(ask: (_, _) async => true);
    final ws = await WebSocket.connect('ws://127.0.0.1:${host.port}/darts?auth=1');
    final got = <String>[];
    ws.listen((m) => got.add('$m'));
    ws.add(jsonEncode({'t': 'hello', 'device': 'x', 'name': 'X', 'auth': true, 'nonce': List.filled(32, 'a').join()}));
    await _wait(() => got.isNotEmpty);
    expect(got.first, contains('denied'));
    await ws.close();
    await host.stop();
  });

  test('Anzeige-Gerät darf nichts eintragen', () async {
    final host = Link.forTest();
    host.hostState = () => {'match': null, 'tournament': null};
    final received = <String>[];
    host.onHostMessage = (m) => received.add('${m['t']}');
    await host.startHost(preferredPort: 0);
    final g = Link.forTest();
    var st = 0;
    g.onState = (_) => st++;
    await g.join('127.0.0.1', host.port, host.code!, viewer: true);
    await _wait(() => st > 0);
    g.sendToHost({'t': 'dart', 'mid': 'x', 'd': {'f': 20, 'm': 3}});
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(received, isEmpty);
    expect(host.peerNames.single, contains('Anzeige'));
    // auf Mitspielen umschalten → darf eintragen
    g.setViewerMode(false);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    g.sendToHost({'t': 'dart', 'mid': 'x', 'd': {'f': 20, 'm': 3}});
    await _wait(() => received.isNotEmpty);
    expect(received, ['dart']);
    await g.stop();
    await host.stop();
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/net/link.dart';
import 'package:darts_counter/net/relay.dart';
import 'package:darts_protocol/darts_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Integration: App-Kopplung (Link + RelayClient) gegen den ECHTEN Vermittlungs-Server aus `server/`.
/// Überspringt sich, wenn kein Dart-SDK gefunden wird.
Future<void> _wait(bool Function() cond, {int ms = 6000}) async {
  for (var i = 0; i < ms ~/ 20 && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

String? _dart() {
  for (final p in [
    'C:/dev/flutter/bin/cache/dart-sdk/bin/dart.exe',
    '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/dart-sdk/bin/dart',
  ]) {
    if (File(p).existsSync()) return p;
  }
  return null;
}

void main() {
  Process? server;
  late String url;
  final log = StringBuffer();
  final links = <Link>[];
  final dart = _dart();

  Link mk({String? device}) {
    final l = Link.forTest()..deviceForTest = device;
    links.add(l);
    return l;
  }

  setUpAll(() async {
    if (dart == null) return;
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    server = await Process.start(
      dart,
      ['run', 'bin/server.dart'],
      workingDirectory: 'server',
      environment: {'PORT': '$port', 'HOST': '127.0.0.1', 'WEB_DIR': 'does-not-exist', 'LOG_LEVEL': 'info'},
    );
    server!.stdout.transform(utf8.decoder).listen(log.write);
    server!.stderr.transform(utf8.decoder).listen(log.write);
    url = 'http://127.0.0.1:$port';
    final client = HttpClient();
    for (var i = 0; i < 150; i++) {
      try {
        final r = await (await client.getUrl(Uri.parse('$url/health'))).close();
        await r.drain<void>();
        if (r.statusCode == 200) break;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    client.close();
  });

  tearDownAll(() async {
    server?.kill();
    await server?.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    RelayClient.retryDelays = const [Duration(milliseconds: 100)];
    if (dart != null) Store.serverUrl = url;
  });

  tearDown(() async {
    for (final l in links) {
      await l.stop();
    }
    links.clear();
  });

  Future<(Link, List<String>)> host({Map<String, dynamic> Function()? state}) async {
    final asked = <String>[];
    final h = mk()..trustAll = false;
    h.onJoinRequest = (dev, name) async {
      asked.add(dev);
      return true;
    };
    h.hostState = state ?? () => {'match': null, 'tournament': null};
    await h.startOnlineHost();
    return (h, asked);
  }

  test('Echter Server: Host + 2 Gäste mit Freigabe, Würfe und Stand fließen', () async {
    var n = 0;
    final (h, asked) = await host(state: () => {'match': {'n': n}, 'tournament': null});
    expect(RoomCode.isValid(h.code!), isTrue);
    final got = <String>[];
    h.onHostMessage = (m) => got.add('${m['t']}:${m['_dev']}');
    final g1 = mk(device: 'g1'), g2 = mk(device: 'g2');
    final s1 = <Map<String, dynamic>>[], s2 = <Map<String, dynamic>>[];
    g1.onState = s1.add;
    g2.onState = s2.add;
    expect(await g1.joinOnline(h.code!), isTrue);
    expect(await g2.joinOnline(RoomCode.pretty(h.code!)), isTrue);
    await _wait(() => s1.isNotEmpty && s2.isNotEmpty);
    expect(asked, ['g1', 'g2']);
    expect(h.peerCount, 2);

    g1.sendToHost({'t': 'dart', 'mid': 'm', 'd': {'f': 20, 'm': 3}});
    g2.sendToHost({'t': 'undo', 'mid': 'm'});
    await _wait(() => got.length >= 2);
    expect(got, containsAll(['dart:g1', 'undo:g2']));

    n = 5;
    h.broadcastState();
    await _wait(() => (s1.last['match'] as Map)['n'] == 5 && (s2.last['match'] as Map)['n'] == 5);
    expect((s2.last['match'] as Map)['n'], 5);
    expect(s1.last['devices'], 3);
  }, skip: dart == null ? 'kein Dart-SDK gefunden' : null);

  test('Echter Server: bekanntes Gerät kommt mit Schlüssel ohne neue Freigabe wieder rein', () async {
    final (h, asked) = await host();
    final g = mk(device: 'g1');
    var s = 0;
    g.onState = (_) => s++;
    expect(await g.joinOnline(h.code!), isTrue);
    await _wait(() => s > 0);
    await g.stop();
    final known = Store.knownHosts.single;
    expect(known.online, isTrue);

    final again = mk(device: 'g1');
    var s2 = 0;
    again.onState = (_) => s2++;
    expect(await again.joinOnline(known.room!, hostDevice: known.device), isTrue);
    await _wait(() => s2 > 0);
    expect(s2, greaterThan(0));
    expect(asked, ['g1']);
  }, skip: dart == null ? 'kein Dart-SDK gefunden' : null);

  test('Echter Server: Host-Neustart holt den Raum zurück, Gast wartet und kommt ohne Freigabe wieder', () async {
    final (h, asked) = await host();
    final code = h.code!;
    final g = mk(device: 'g1');
    var s = 0;
    g.onState = (_) => s++;
    expect(await g.joinOnline(code), isTrue);
    await _wait(() => s > 0);

    await h.stop(); // App beendet – Raum bleibt bestehen
    await _wait(() => g.relayStatus == RelayStatus.hostOffline);
    expect(g.relayStatus, RelayStatus.hostOffline);

    final (h2, asked2) = await host();
    expect(h2.code, code);
    final before = s;
    await _wait(() => s > before && g.isConnected);
    expect(g.isConnected, isTrue);
    expect(h2.peerCount, 1);
    expect(asked, ['g1']);
    expect(asked2, isEmpty); // Schlüssel statt neuer Freigabe
  }, skip: dart == null ? 'kein Dart-SDK gefunden' : null);

  test('Echter Server: Raum schließen trennt den Gast, Code ist danach ungültig', () async {
    final (h, _) = await host();
    final code = h.code!;
    final g = mk(device: 'g1');
    var s = 0;
    g.onState = (_) => s++;
    expect(await g.joinOnline(code), isTrue);
    await _wait(() => s > 0);
    await h.leave();
    await _wait(() => g.relayStatus == RelayStatus.closed);
    expect(g.relayStatus, RelayStatus.closed);
    expect(g.isConnected, isFalse);

    final late = mk(device: 'g2');
    expect(await late.joinOnline(code), isFalse);
  }, skip: dart == null ? 'kein Dart-SDK gefunden' : null);

  test('Echter Server: Logs ohne Gerätenamen, Geräte-IDs oder Raum-Codes', () async {
    final (h, _) = await host();
    final g = mk(device: 'geheimes-geraet-42');
    var s = 0;
    g.onState = (_) => s++;
    expect(await g.joinOnline(h.code!), isTrue);
    await _wait(() => s > 0);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final text = log.toString();
    expect(text, isNot(contains('geheimes-geraet-42')));
    expect(text, isNot(contains(Store.deviceName)));
    expect(text, isNot(contains(h.code!)));
  }, skip: dart == null ? 'kein Dart-SDK gefunden' : null);
}

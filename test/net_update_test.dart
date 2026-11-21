import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/net/server_config.dart';
import 'package:darts_counter/net/update_check.dart';
import 'package:darts_protocol/darts_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'net_test_relay.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });

  group('Server-Adresse', () {
    test('Standard ist der Platzhalter, eigene Adresse überschreibt', () {
      expect(ServerConfig.url, defaultServerUrl);
      expect(ServerConfig.isPlaceholder, isTrue);
      Store.serverUrl = 'http://192.168.0.10:8080/';
      expect(ServerConfig.url, 'http://192.168.0.10:8080');
      expect(ServerConfig.isPlaceholder, isFalse);
      Store.serverUrl = '';
      expect(ServerConfig.url, defaultServerUrl);
    });

    test('http → ws, https → wss, Pfad /ws', () {
      expect(ServerConfig.relayUri('http://192.168.0.10:8080').toString(), 'ws://192.168.0.10:8080/ws');
      expect(ServerConfig.relayUri('https://darts.example.org').toString(), 'wss://darts.example.org/ws');
      expect(ServerConfig.relayUri('https://example.org/darts/').toString(), 'wss://example.org/darts/ws');
    });

    test('Eingabe ohne Schema wird ergänzt', () {
      expect(ServerConfig.normalize('192.168.0.10:8080'), 'http://192.168.0.10:8080');
      expect(ServerConfig.normalize('darts.example.org'), 'https://darts.example.org');
      expect(ServerConfig.normalize('  https://x.de//  '), 'https://x.de');
    });

    test('„Verbindung testen“ fragt /health', () async {
      final relay = await TestRelay.start();
      expect(await ServerConfig.test(relay.url), isNull);
      final port = relay.port;
      await relay.stop();
      expect(await ServerConfig.test('http://127.0.0.1:$port'), contains('nicht erreichbar'));
      expect(await ServerConfig.test(''), isNotNull);
    });
  });

  group('Update', () {
    const info = VersionInfo(
        version: '3.0.1', build: 20, minProtocol: 3, apkUrl: 'apk/Darts_3.0.1.apk', notes: ['Fehler behoben']);

    test('Nur neuere Builds werden angeboten', () {
      expect(UpdateCheck.evaluate(info, installedBuild: 20, web: false), isNull);
      expect(UpdateCheck.evaluate(info, installedBuild: 21, web: false), isNull);
      expect(UpdateCheck.evaluate(info, installedBuild: 19, web: false), isNotNull);
    });

    test('Relativer APK-Link wird mit der Server-Adresse aufgelöst, absoluter bleibt', () {
      final o = UpdateCheck.evaluate(info, installedBuild: 19, web: false, server: 'http://192.168.0.10:8080')!;
      expect(o.apk.toString(), 'http://192.168.0.10:8080/apk/Darts_3.0.1.apk');
      final sub = UpdateCheck.evaluate(info, installedBuild: 19, web: false, server: 'https://x.de/darts/')!;
      expect(sub.apk.toString(), 'https://x.de/darts/apk/Darts_3.0.1.apk');
      const abs = VersionInfo(version: '3.0.1', build: 20, minProtocol: 3, apkUrl: 'https://cdn.x.de/a.apk');
      expect(UpdateCheck.evaluate(abs, installedBuild: 19, web: false, server: 'http://h')!.apk.toString(),
          'https://cdn.x.de/a.apk');
    });

    test('Web: kein Download, nur neu laden', () {
      final o = UpdateCheck.evaluate(info, installedBuild: 19, web: true, server: 'http://h')!;
      expect(o.web, isTrue);
      expect(o.apk, isNull);
    });

    test('Relais-Fehler „update“ wird immer angeboten (auch unvollständig)', () {
      final o = UpdateCheck.fromRelay({'version': '3.1.0', 'apk': 'apk/x.apk', 'build': 'kaputt'},
          web: false, server: 'http://h:1');
      expect(o.required, isTrue);
      expect(o.info.version, '3.1.0');
      expect(o.apk.toString(), 'http://h:1/apk/x.apk');
      expect(UpdateCheck.fromRelay(null, web: false, server: 'http://h').required, isTrue);
    });

    test('Höchstens einmal am Tag prüfen; Platzhalter-Server wird nie abgefragt', () async {
      final relay = await TestRelay.start();
      relay.version = info.toJson();
      final now = DateTime(2026, 11, 21, 12);
      expect(UpdateCheck.due(now), isTrue);
      final o = await UpdateCheck.check(installedBuild: 19, web: false, server: relay.url, now: now);
      expect(o?.info.version, '3.0.1');
      expect(o?.apk.toString(), '${relay.url}/apk/Darts_3.0.1.apk');
      expect(UpdateCheck.due(now.add(const Duration(hours: 5))), isFalse);
      expect(await UpdateCheck.check(installedBuild: 19, web: false, server: relay.url, now: now), isNull);
      expect(await UpdateCheck.check(installedBuild: 19, web: false, server: relay.url, now: now, force: true),
          isNotNull);
      expect(UpdateCheck.due(now.add(const Duration(hours: 25))), isTrue);
      await relay.stop();
      // Standard-Adresse ist der Platzhalter → keine Abfrage
      Store.lastUpdateCheck = 0;
      expect(await UpdateCheck.check(installedBuild: 1, web: false), isNull);
      expect(Store.lastUpdateCheck, 0);
    });
  });
}

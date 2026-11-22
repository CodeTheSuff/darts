import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/net/link.dart';
import 'package:darts_counter/net/server_link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Link> _host({int? compat, int? minCompat}) async {
  final host = Link.forTest()..trustAll = true;
  if (compat != null) host.compat = compat;
  if (minCompat != null) host.minCompat = minCompat;
  host.hostState = () => {'match': null, 'tournament': null};
  await host.startHost(preferredPort: 0);
  return host;
}

Future<void> _wait(bool Function() cond) async {
  for (var i = 0; i < 60 && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });

  group('App-Versionen im Raum', () {
    test('gleiche Version: Kopplung klappt', () async {
      final host = await _host();
      final guest = Link.forTest();
      var states = 0;
      guest.onState = (_) => states++;
      expect(await guest.join('127.0.0.1', host.port, host.code!), isTrue);
      await _wait(() => states > 0);
      expect(guest.isConnected, isTrue);
      expect(guest.versionMismatch, isNull);
      await guest.stop();
      await host.stop();
    });

    test('alte App ohne Angabe (bis 3.0.0) darf mit dem heutigen Mindeststand weiter mitspielen', () async {
      final host = await _host();
      final guest = Link.forTest()..compat = 0;
      var states = 0;
      guest.onState = (_) => states++;
      expect(await guest.join('127.0.0.1', host.port, host.code!), isTrue);
      await _wait(() => states > 0);
      expect(guest.isConnected, isTrue);
      await guest.stop();
      await host.stop();
    });

    test('Gast zu alt: Raum lehnt mit „update“ ab, Gast meldet selfTooOld und bekommt keine Daten', () async {
      final host = await _host(minCompat: linkCompat + 1);
      final guest = Link.forTest();
      VersionMismatch? why;
      var states = 0;
      guest.onVersionMismatch = (w) => why = w;
      guest.onState = (_) => states++;
      expect(await guest.join('127.0.0.1', host.port, host.code!), isTrue);
      await _wait(() => why != null);
      expect(why, VersionMismatch.selfTooOld);
      expect(guest.versionMismatch, VersionMismatch.selfTooOld);
      expect(guest.status, contains('aktualisieren'));
      expect(guest.isConnected, isFalse);
      expect(states, 0);
      expect(host.peerCount, 0);
      await guest.stop();
      await host.stop();
    });

    test('Raum-Gerät zu alt: Gast trennt mit hostTooOld', () async {
      final host = await _host(compat: 0); // alte App ohne Angabe
      final guest = Link.forTest()..minCompat = linkCompat;
      VersionMismatch? why;
      guest.onVersionMismatch = (w) => why = w;
      expect(await guest.join('127.0.0.1', host.port, host.code!), isTrue);
      await _wait(() => why != null);
      expect(why, VersionMismatch.hostTooOld);
      expect(guest.status, contains('Raum-Gerät'));
      await _wait(() => !guest.isConnected);
      expect(guest.isConnected, isFalse);
      await guest.stop();
      await host.stop();
    });

    test('neuer Beitritt setzt einen alten Versionskonflikt zurück', () async {
      final old = await _host(minCompat: linkCompat + 1);
      final guest = Link.forTest();
      expect(await guest.join('127.0.0.1', old.port, old.code!), isTrue);
      await _wait(() => guest.versionMismatch != null);
      await old.stop();
      final ok = await _host();
      expect(await guest.join('127.0.0.1', ok.port, ok.code!), isTrue);
      expect(guest.versionMismatch, isNull);
      await guest.stop();
      await ok.stop();
    });
  });

  group('Link „App mit diesem Server verbinden“', () {
    test('gültige Links', () {
      expect(ServerLink.parse('darts://connect?server=https%3A%2F%2Fdarts.beispiel.de'), 'https://darts.beispiel.de');
      expect(ServerLink.parse('darts://connect?server=https://darts.beispiel.de/'), 'https://darts.beispiel.de');
      expect(ServerLink.parse('darts://connect?server=darts.beispiel.de'), 'https://darts.beispiel.de');
      expect(ServerLink.parse('darts://connect?server=http://192.168.1.20:8080'), 'http://192.168.1.20:8080');
      expect(ServerLink.parse('darts://connect?server=https://x.de/darts'), 'https://x.de/darts');
    });

    test('ungültige oder gefährliche Links werden ignoriert', () {
      expect(ServerLink.parse(null), isNull);
      expect(ServerLink.parse(''), isNull);
      expect(ServerLink.parse('https://darts.beispiel.de'), isNull);
      expect(ServerLink.parse('darts://andere?server=https://x.de'), isNull);
      expect(ServerLink.parse('darts://connect'), isNull);
      expect(ServerLink.parse('darts://connect?server='), isNull);
      expect(ServerLink.parse('darts://connect?server=http://boese.de'), isNull); // ohne https nur lokal
      expect(ServerLink.parse('darts://connect?server=javascript:alert(1)'), isNull);
      expect(ServerLink.parse('darts://connect?server=https://user:pw@x.de'), isNull);
      expect(ServerLink.parse('darts://connect?server=https://x.de/?a=1'), isNull);
      expect(ServerLink.parse('darts://connect?server=https://${'a' * 300}.de'), isNull);
    });

    test('übernimmt den Server erst nach Bestätigung', () async {
      ServerLink.confirm = (_) async => false;
      String? doneWith;
      ServerLink.done = (s, _) => doneWith = s;
      await ServerLink.handle('darts://connect?server=https://darts.beispiel.de');
      expect(Store.serverUrl, isNull);
      expect(doneWith, isNull);
      ServerLink.confirm = null;
      ServerLink.done = null;
    });
  });
}

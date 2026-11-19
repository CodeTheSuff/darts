import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/net/link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });

  test('Raum-Code: zufällig, danach fest, änderbar', () {
    final c = Store.roomCode;
    expect(RegExp(r'^\d{4}$').hasMatch(c), isTrue);
    expect(Store.roomCode, c);
    Store.roomCode = '4711';
    expect(Store.roomCode, '4711');
    Store.roomCode = 'abc';
    expect(Store.roomCode, '4711');
  });

  test('Suchziele im großen Netz (/19) nahe der eigenen Adresse', () {
    final t = Link.targetsFor('10.192.48.220', 19);
    expect(t.length, 8190 - 1); // ganzes /19 ohne Netz-, Broadcast- und eigene Adresse
    expect(t.first, '10.192.48.221');
    expect(t.contains('10.192.48.220'), isFalse);
    expect(t.contains('10.192.51.7'), isTrue); // anderer /24-Bereich, gleiches Netz
    for (final a in t) {
      final p = a.split('.').map(int.parse).toList();
      expect(p[0] == 10 && p[1] == 192 && p[2] >= 32 && p[2] <= 63, isTrue, reason: a);
    }
    expect(t.contains('10.192.32.0'), isFalse);
    expect(t.contains('10.192.63.255'), isFalse);
  });

  test('Tablet 10.192.51.17 findet Handy 10.192.63.187 im selben /19', () {
    expect(Link.targetsFor('10.192.51.17', 19).contains('10.192.63.187'), isTrue);
  });

  test('Suchziele im /24-Netz: alle 253 anderen Adressen', () {
    final t = Link.targetsFor('192.168.0.5', 24);
    expect(t.length, 253);
    expect(t.toSet().length, 253);
  });

  test('Bekannte Geräte merken, aktualisieren, vergessen', () {
    Store.rememberHost(KnownHost(device: 'a', name: 'Handy', address: '10.0.0.2', port: 47123, code: '1234'));
    Store.rememberHost(
        KnownHost(device: 'b', name: 'Tablet', address: '10.0.0.3', port: 47123, code: '5555', viewer: true));
    expect(Store.knownHosts.map((h) => h.device), ['b', 'a']);
    Store.updateHost('a', address: '10.0.0.9', port: 47123, code: '1234');
    expect(Store.knownHosts.firstWhere((h) => h.device == 'a').address, '10.0.0.9');
    expect(Store.knownHosts.first.viewer, isTrue);
    Store.forgetHost('b');
    expect(Store.knownHosts.map((h) => h.device), ['a']);
  });

  test('Nach dem Verbinden ist der Host als bekanntes Gerät gespeichert', () async {
    final host = Link.forTest();
    await host.startHost(preferredPort: 0);
    expect(host.code, Store.roomCode);
    final guest = Link.forTest();
    expect(await guest.join('127.0.0.1', host.port, host.code!, viewer: true), isTrue);
    for (var i = 0; i < 20 && Store.knownHosts.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final k = Store.knownHosts.single;
    expect(k.device, Store.deviceId);
    expect(k.address, '127.0.0.1');
    expect(k.port, host.port);
    expect(k.code, host.code);
    expect(k.viewer, isTrue);
    await guest.stop();
    await host.stop();
  });
}

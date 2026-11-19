import 'dart:async';
import 'dart:convert';

import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/data/sync.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/games/x01.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:darts_counter/net/link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Device {
  Device(this.name);
  final String name;
  Map<String, Object> prefs = {};
  int confirms = 0;

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

GamePlayer gp(String name) {
  final p = Store.ensureProfile(name);
  return GamePlayer(p.id, p.name, 0xFF5AA9FF);
}

void playMatch(String a, String b, {String? matchId}) {
  final ctl = MatchController(
    config: const GameConfig('x01', {'start': 101, 'doubleOut': true, 'legs': 1}),
    players: [gp(a), gp(b)],
    matchId: matchId,
  );
  for (final d in const [Dart(20, 3), Dart(1, 1), Dart(20, 2)]) {
    ctl.throwDart(d);
  }
  ctl.commitStats();
}

/// Ein Abgleich-Durchgang zwischen zwei Geräten (wie über die Kopplung, nur ohne Netz).
Future<void> syncPair(Device x, Device y) async {
  Future<void> push(Device from, Device to) async {
    await to.use();
    final have = jsonDecode(jsonEncode(AutoSync.have())) as Map<String, dynamic>;
    await to.save();
    await from.use();
    final pkg = AutoSync.missingFor(have);
    final wire = pkg == null ? null : jsonEncode(pkg.toJson());
    await from.save();
    if (wire == null) return;
    await to.use();
    await AutoSync.apply(SharePackage.fromJson(jsonDecode(wire) as Map<String, dynamic>), confirm: (i, l) async {
      to.confirms++;
      return true;
    });
    await to.save();
  }

  await push(x, y);
  await push(y, x);
}

Future<Map<String, int>> matchesByName(Device d) async {
  await d.use();
  final out = {
    for (final p in Store.profiles) p.name.toLowerCase(): Store.statsFor(p.id).x01.matches,
  };
  await d.save();
  return out;
}

void main() {
  test('Drei Handys, Abgleich über den Host: alle haben denselben Stand, nichts doppelt', () async {
    final a = Device('A'), b = Device('B'), c = Device('C');
    await a.use();
    playMatch('Simon', 'Max');
    playMatch('Simon', 'Lena');
    await a.save();
    await b.use();
    playMatch('Simon', 'Max');
    await b.save();
    await c.use();
    playMatch('Lena', 'Tom');
    playMatch('Lena', 'Tom');
    playMatch('Lena', 'Tom');
    await c.save();

    // Host A gleicht mit B und C ab, danach noch einmal mit B (bekommt C's Daten über A)
    await syncPair(a, b);
    await syncPair(a, c);
    await syncPair(a, b);

    final expected = {'simon': 3, 'max': 2, 'lena': 4, 'tom': 3};
    expect(await matchesByName(a), expected);
    expect(await matchesByName(b), expected);
    expect(await matchesByName(c), expected);

    for (final d in [a, b, c]) {
      await d.use();
      expect(Store.archive.length, 6, reason: d.name);
      await d.save();
    }

    // Erneuter Abgleich ändert nichts mehr
    await syncPair(a, b);
    await syncPair(a, c);
    expect(await matchesByName(b), expected);

    // Gleichnamige Spieler wurden je Gerät höchstens einmal nachgefragt
    expect(b.confirms, lessThanOrEqualTo(2));
    final before = b.confirms;
    await syncPair(a, b);
    expect(b.confirms, before);
  });

  test('Gekoppeltes Match auf beiden Geräten → nach Abgleich trotzdem nur einmal gezählt', () async {
    final a = Device('A'), b = Device('B');
    await a.use();
    final simon = gp('Simon');
    final max = gp('Max');
    final ctl = MatchController(
      config: const GameConfig('x01', {'start': 101, 'doubleOut': true, 'legs': 1}),
      players: [simon, max],
    );
    for (final d in const [Dart(20, 3), Dart(1, 1), Dart(20, 2)]) {
      ctl.throwDart(d);
    }
    ctl.commitStats();
    await a.save();
    await b.use();
    // Gast speichert das Match mit denselben (fremden) IDs und derselben Match-ID
    final guest = MatchController(config: ctl.config, players: ctl.players, matchId: ctl.matchId);
    for (final d in ctl.darts) {
      guest.throwDart(d);
    }
    guest.commitStats();
    await b.save();
    await syncPair(a, b);
    expect(await matchesByName(a), {'simon': 1, 'max': 1});
    expect(await matchesByName(b), {'simon': 1, 'max': 1});
  });

  test('Match-Archiv: Wiederaufbau ergibt denselben Spielstand', () async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    final ctl = MatchController(
      config: const GameConfig('x01', {'start': 301, 'doubleOut': true, 'legs': 1}),
      players: [gp('Simon'), gp('Max')],
    );
    for (final d in const [Dart(20, 3), Dart(20, 3), Dart(20, 3), Dart(19, 3), Dart(5, 1), Dart(0, 1)]) {
      ctl.throwDart(Dart.thrown(d.field, d.mult));
    }
    final rec = ctl.toRecord(0);
    final e = MatchController.replay(MatchRecord.fromJson(jsonDecode(jsonEncode(rec.toJson())) as Map<String, dynamic>))
        as X01Game;
    expect(e.scores, (ctl.engine as X01Game).scores);
  });

  test('Protokoll: Gast fragt an, Host antwortet mit fehlenden Daten (echte Sockets)', () async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    final host = Link.forTest();
    final guest = Link.forTest();
    final hostGot = <String>[];
    final guestGot = Completer<Map<String, dynamic>>();
    host.onSync = (msg, reply, from) {
      hostGot.add(msg['t'] as String);
      if (msg['t'] == 'have') reply({'t': 'syncpkg', 'pkg': {'x': 1}});
    };
    guest.onSync = (msg, reply, from) {
      if (msg['t'] == 'syncpkg' && !guestGot.isCompleted) guestGot.complete(msg);
    };
    await host.startHost(preferredPort: 0);
    expect(await guest.join('127.0.0.1', host.port, host.code!), isTrue);
    guest.requestSync(() => {'keys': []});
    final m = await guestGot.future.timeout(const Duration(seconds: 3));
    expect(m['pkg'], {'x': 1});
    expect(hostGot, contains('have'));
    await guest.stop();
    await host.stop();
  });
}

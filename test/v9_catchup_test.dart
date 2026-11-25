import 'dart:async';

import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/games/x01.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:darts_counter/net/link.dart';
import 'package:darts_counter/ui/link_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Nachsync (3.2.0): Würfe, die ein Gast eingetragen hat, während der Host weg war,
/// gehen beim Wiederverbinden nicht verloren.

MatchController newMatch({String mid = 'm-sync'}) => MatchController(
      config: const GameConfig('x01', {'start': 501, 'doubleOut': true, 'legs': 1}),
      players: const [GamePlayer('a', 'Anna', 0xFF2196F3), GamePlayer('b', 'Ben', 0xFFE91E63)],
      seed: 7,
      matchId: mid,
    );

List<Map<String, dynamic>> js(List<Dart> ds) => [for (final d in ds) d.toJson()];

Future<void> waitFor(bool Function() cond, {int ms = 5000}) async {
  for (var i = 0; i < ms ~/ 20 && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    Store.deviceName = 'Host';
    Link.searchOnRetry = false;
  });

  group('Host gleicht ab', () {
    late MatchController host;
    late Link guest;
    late StreamController<Map<String, dynamic>> direct;

    setUp(() async {
      LinkCoordinator.init();
      Link.I.trustAll = true;
      await Link.I.startHost(preferredPort: 0);
      host = newMatch();
      LinkCoordinator.gameOpened(host);
      guest = Link.forTest()..deviceForTest = 'handy-3';
      direct = StreamController<Map<String, dynamic>>.broadcast();
      guest.onDirect = direct.add;
      expect(await guest.join('127.0.0.1', Link.I.port, Link.I.code!), isTrue);
      await waitFor(() => guest.isConnected);
    });

    tearDown(() async {
      LinkCoordinator.conflictForTest = null;
      LinkCoordinator.gameClosed(host);
      await guest.stop();
      await Link.I.stop();
      await direct.close();
    });

    Future<Map<String, dynamic>> catchup(List<Dart> darts, {bool dirty = true}) {
      final f = direct.stream.firstWhere((m) => m['kind'] == 'catchupDone').timeout(const Duration(seconds: 3));
      guest.sendToHost({'t': 'catchup', 'mid': host.matchId, 'darts': js(darts), 'dirty': dirty});
      return f;
    }

    test('Gast hat offline weitergezählt → Host übernimmt die zusätzlichen Würfe', () async {
      host.throwDart(const Dart(20, 3));
      final theirs = [const Dart(20, 3), const Dart(20, 1), const Dart(5, 1), const Dart(19, 3)];
      final done = await catchup(theirs);
      expect(done['gone'], isNull);
      expect(host.darts.map((d) => d.code), theirs.map((d) => d.code));
      expect((host.engine as X01Game).scores[0], 501 - 85);
      expect((host.engine as X01Game).scores[1], 501 - 57);
      // Host speichert den übernommenen Stand
      expect((Store.activeMatch!['darts'] as List).length, 4);
    });

    test('Würfe während einer Host-Animation gehen nicht verloren (Gerätetest 3.2.0)', () async {
      host.throwDart(const Dart(20, 3));
      host.inputLocked = true; // z. B. 180-Jubel läuft
      for (final d in const [Dart(19, 3), Dart(19, 1), Dart(19, 3)]) {
        guest.sendToHost({'t': 'dart', 'mid': host.matchId, 'd': d.toJson()});
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(host.darts.length, 1);
      host.inputLocked = false;
      await waitFor(() => host.darts.length == 4);
      expect(host.darts.map((d) => d.code).skip(1), const [Dart(19, 3), Dart(19, 1), Dart(19, 3)].map((d) => d.code));
    });

    test('Host schließt den WLAN-Raum → Gast hört auf, neu zu verbinden', () async {
      await waitFor(() => Link.I.peerCount == 1);
      await Link.I.leave();
      await waitFor(() => guest.status.contains('geschlossen'));
      expect(guest.status, contains('geschlossen'));
      expect(guest.isConnected, isFalse);
    });

    test('Host ist weiter als der Gast → bleibt, Gast holt auf', () async {
      for (final d in const [Dart(20, 3), Dart(20, 1), Dart(1, 1)]) {
        host.throwDart(d);
      }
      await catchup(const [Dart(20, 3)]);
      expect(host.darts.length, 3);
    });

    test('Beide unterschiedlich weitergezählt → Rückfrage am Host; „Gast“ übernimmt dessen Stand', () async {
      host.throwDart(const Dart(20, 3));
      host.throwDart(const Dart(1, 1));
      String? askedFrom;
      LinkCoordinator.conflictForTest = (mine, theirs, from) async {
        askedFrom = from;
        expect(mine.darts.length, 2);
        expect(theirs.darts.length, 3);
        return true;
      };
      final theirs = [const Dart(20, 3), const Dart(19, 3), const Dart(18, 3)];
      await catchup(theirs);
      expect(askedFrom, isNotNull);
      expect(host.darts.map((d) => d.code), theirs.map((d) => d.code));
    });

    test('Beide unterschiedlich → „Diesen behalten“ lässt den Host-Stand', () async {
      host.throwDart(const Dart(20, 3));
      host.throwDart(const Dart(1, 1));
      LinkCoordinator.conflictForTest = (_, _, _) async => false;
      await catchup(const [Dart(20, 3), Dart(19, 3)]);
      expect(host.darts.map((d) => d.code), [const Dart(20, 3).code, const Dart(1, 1).code]);
    });

    test('Unterschied ohne eigene Gast-Eingaben (dirty = false) → keine Rückfrage, Host gilt', () async {
      host.throwDart(const Dart(20, 3));
      var asked = false;
      LinkCoordinator.conflictForTest = (_, _, _) async => asked = true;
      await catchup(const [Dart(19, 1)], dirty: false);
      expect(asked, isFalse);
      expect(host.darts.length, 1);
    });

    test('Host hat das Spiel bewusst beendet → Gast bekommt „gone“', () async {
      LinkCoordinator.gameClosed(host);
      final done = await catchup(const [Dart(20, 3)]);
      expect(done['gone'], isTrue);
      LinkCoordinator.gameOpened(host); // für tearDown
    });
  });

  group('Gast zählt offline weiter', () {
    late Link hostLink;
    late MatchController hostSide;
    final caught = <Map<String, dynamic>>[];

    setUp(() async {
      caught.clear();
      LinkCoordinator.init();
      hostSide = newMatch(mid: 'm-guest');
      hostLink = Link.forTest();
      hostLink.hostState = () => {'match': hostSide.toJson(), 'tournament': null};
      hostLink.onHostMessage = (m) {
        if (m['t'] == 'catchup') caught.add(m);
        if (m['t'] == 'dart' && m['mid'] == hostSide.matchId) {
          hostSide.throwDartExternal(Dart.fromJson(Map<String, dynamic>.from(m['d'] as Map)));
          hostLink.broadcastState();
        }
      };
      await hostLink.startHost(preferredPort: 0);
    });

    tearDown(() async {
      final c = LinkCoordinator.clientMatch;
      if (c != null) LinkCoordinator.gameClosed(c);
      await Link.I.stop();
      await hostLink.stop();
    });

    test('Würfe während des Abbruchs gehen nach dem Wiederverbinden per „catchup“ an den Host', () async {
      expect(await Link.I.join('127.0.0.1', hostLink.port, hostLink.code!), isTrue);
      await waitFor(() => Link.I.isConnected);
      // Gast-Spiel wie vom Stand geöffnet
      final g = MatchController.fromJson(hostSide.toJson())!..remote = true;
      LinkCoordinator.gameOpened(g);
      g.throwDart(const Dart(20, 3));
      await waitFor(() => hostSide.darts.length == 1);
      expect(hostSide.darts.length, 1);
      await waitFor(() => !g.offlineDirty);
      expect(g.offlineDirty, isFalse, reason: 'Host hat den Stand bestätigt');
      expect(g.awaitingCatchup, isFalse);
      caught.clear();

      // Verbindung bricht ab; Gast trägt weiter ein
      await hostLink.dropAllForTest();
      await waitFor(() => !Link.I.isConnected);
      g.throwDart(const Dart(20, 1));
      g.throwDart(const Dart(5, 1));
      expect(g.offlineDirty, isTrue);
      // Zwischengespeichert (übersteht einen Neustart der App)
      final saved = Store.guestMatch!;
      expect(saved['dirty'], isTrue);
      expect((saved['darts'] as List).length, 3);
      expect(MatchController.fromJson(saved)!.darts.length, 3);

      // Wiederverbinden (alle 2 s) → erster Stand → Gast schickt seinen Stand
      await waitFor(() => caught.isNotEmpty, ms: 8000);
      expect(caught, isNotEmpty);
      expect((caught.last['darts'] as List).length, 3);
      expect(caught.last['dirty'], isTrue);
      // Bis zur Antwort bleibt der eigene Stand erhalten (nicht vom Host-Stand überschrieben)
      expect(g.darts.length, 3);
      expect(g.awaitingCatchup, isTrue);
    });

    test('Host ohne offenes Spiel (z. B. nach Neustart) → Gast behält das Spiel und bietet es an', () async {
      hostLink.hostState = () => {'match': null, 'tournament': null};
      expect(await Link.I.join('127.0.0.1', hostLink.port, hostLink.code!), isTrue);
      final g = MatchController.fromJson(hostSide.toJson())!..remote = true;
      g.throwDart(const Dart(20, 3));
      LinkCoordinator.gameOpened(g);
      hostLink.broadcastState();
      await waitFor(() => caught.isNotEmpty);
      expect(caught, isNotEmpty);
      expect(caught.last['match'], isA<Map<dynamic, dynamic>>());
      expect(LinkCoordinator.clientMatch, same(g));
    });

    test('Host hat das Spiel beendet („ended“) → Gast schließt es', () async {
      hostLink.hostState = () => {
            'match': null,
            'tournament': null,
            'ended': [hostSide.matchId],
          };
      expect(await Link.I.join('127.0.0.1', hostLink.port, hostLink.code!), isTrue);
      final g = MatchController.fromJson(hostSide.toJson())!..remote = true;
      LinkCoordinator.gameOpened(g);
      hostLink.broadcastState();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(caught, isEmpty);
    });
  });
}

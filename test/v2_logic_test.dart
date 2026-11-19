import 'dart:math';

import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/data/tournament_store.dart';
import 'package:darts_counter/games/bot.dart';
import 'package:darts_counter/games/catalog.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/games/tournament.dart';
import 'package:darts_counter/games/x01.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const p1 = GamePlayer('a', 'Anna', 0xFF5AA9FF);
const p2 = GamePlayer('b', 'Ben', 0xFFF5C84C);

/// Checkt ein 101-Leg fÃ¼r den aktuellen Spieler: T20, 1, D20.
void checkLeg(GameEngine g) {
  g.apply(const Dart(20, 3));
  g.apply(const Dart(1, 1));
  g.apply(const Dart(20, 2));
}

/// Wirft fÃ¼r den aktuellen Spieler eine Null-Aufnahme.
void miss(GameEngine g) {
  for (var i = 0; i < 3; i++) {
    g.apply(const Dart(0, 1));
  }
}

X01Game sets({int setsN = 2, int legs = 2, int startIndex = 0}) => buildEngine(
    GameConfig('x01', {'start': 101, 'doubleOut': true, 'format': 'sets', 'legs': legs, 'sets': setsN}),
    const [p1, p2],
    startIndex,
    1) as X01Game;

void main() {
  group('X01 Sets', () {
    test('Set wird nach Legs pro Set gewonnen, Legs werden zurÃ¼ckgesetzt', () {
      final g = sets();
      checkLeg(g); // Anna Leg 1
      expect(g.legs, [1, 0]);
      expect(g.cur, 1); // Ben beginnt Leg 2
      miss(g);
      checkLeg(g); // Anna Leg 2 â†’ Set
      expect(g.sets, [1, 0]);
      expect(g.legs, [0, 0]);
      expect(g.legsTotal, [2, 0]);
    });

    test('Anwurf wechselt pro Set', () {
      final g = sets();
      checkLeg(g); // Leg 1: Anna beginnt
      miss(g); // Leg 2: Ben beginnt, wirft Null
      checkLeg(g); // Anna gewinnt Set 1
      // Set 2: Ben beginnt (Set-Starter wechselt)
      expect(g.cur, 1);
    });

    test('Match gewonnen nach First to X Sets', () {
      final g = sets(setsN: 1, legs: 1);
      checkLeg(g);
      expect(g.finished, isTrue);
      expect(g.winner, 0);
      expect(g.results().first.value, '1 Set');
    });

    test('Alte Matches ohne format-Option bleiben im Legs-Modus', () {
      final g = buildEngine(const GameConfig('x01', {'start': 101, 'doubleOut': true, 'legs': 2}), const [p1, p2],
          0, 1) as X01Game;
      expect(g.useSets, isFalse);
      expect(g.setsToWin, isNull);
    });
  });

  group('Bot', () {
    test('Geometrie: Mitte der Felder wird korrekt erkannt', () {
      final rng = Random(1);
      Dart at(Aim a) => dartAt(a.point.x, a.point.y, rng);
      expect(at(const Aim(20, 3)).key, 'T20');
      expect(at(const Aim(16, 2)).key, 'D16');
      expect(at(const Aim(25, 2)).key, '50');
      expect(at(const Aim(19, 1)).key, 'S19');
      expect(dartAt(0, 200, rng).isMiss, isTrue);
      expect(dartAt(0, 10, rng).key, '25');
    });

    test('Zielwahl: Checkout und Stellen', () {
      expect(chooseAim(170, 3, doubleOut: true).toString(), 'T20');
      expect(chooseAim(40, 1, doubleOut: true).toString(), 'D20');
      expect(chooseAim(50, 1, doubleOut: true).toString(), 'Bull');
      // 61 mit einem Dart: kein Finish â†’ auf eine Single stellen, die ein Double lÃ¤sst
      final a = chooseAim(61, 1, doubleOut: true);
      expect(a.mult, 1);
      expect((61 - a.field) <= 40 && (61 - a.field).isEven, isTrue);
      expect(chooseAim(301, 3, doubleOut: true).toString(), 'T20');
    });

    for (final level in BotLevel.values) {
      test('${botProfiles[level]!.name}: Average und Doppelquote im Zielbereich', () {
        final (lo, hi, dlo, dhi) = switch (level) {
          BotLevel.easy => (28.0, 42.0, 6.0, 14.0),
          BotLevel.medium => (48.0, 62.0, 15.0, 26.0),
          BotLevel.hard => (68.0, 82.0, 24.0, 36.0),
          BotLevel.pro => (93.0, 107.0, 33.0, 47.0),
        };
        final rng = Random(level.index + 7);
        final total = X01Stats();
        for (var m = 0; m < 60; m++) {
          final bot = Bot(level, rng: rng); // eigene Tagesform pro Match
          for (var leg = 0; leg < 8; leg++) {
            final g = X01Game([const GamePlayer('bot:x', 'Bot', 0)],
                const GameConfig('x01', {'start': 501, 'doubleOut': true, 'legs': 1}));
            g.begin();
            var guard = 0;
            while (!g.finished && guard++ < 600) {
              if (g.turn.isEmpty) bot.startVisit();
              g.apply(bot.next(g.scores[0], 3 - g.turn.length, doubleOut: true));
            }
            total.merge(g.stats[0]);
          }
        }
        expect(total.average, inInclusiveRange(lo, hi), reason: 'Average ${total.average}');
        expect(total.coRate, inInclusiveRange(dlo, dhi), reason: 'Doppelquote ${total.coRate}');
      });
    }
  });

  group('MatchController', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Store.init();
    });

    test('Bot ist am Zug und Undo nimmt die Bot-Aufnahme mit zurÃ¼ck', () {
      final ctl = MatchController(
        config: const GameConfig('x01', {'start': 501, 'doubleOut': true, 'legs': 1}),
        players: [p1, GamePlayer(botIdFor(BotLevel.medium), 'Bot (Mittel)', 0)],
      );
      expect(ctl.botTurn, isFalse);
      expect(ctl.canUndo, isFalse);
      for (var i = 0; i < 3; i++) {
        ctl.throwDart(const Dart(20, 1));
      }
      expect(ctl.botTurn, isTrue);
      ctl.throwDart(ctl.nextBotDart());
      ctl.throwDart(ctl.nextBotDart());
      expect(ctl.darts.length, 5);
      ctl.undo();
      // Beide Bot-Pfeile und Annas letzter Pfeil sind weg, Anna ist wieder dran.
      expect(ctl.darts.length, 2);
      expect(ctl.botTurn, isFalse);
    });

    test('Kein Undo, wenn nur der Bot geworfen hat', () {
      final ctl = MatchController(
        config: const GameConfig('x01', {'start': 501, 'doubleOut': true, 'legs': 1}),
        players: [p1, GamePlayer(botIdFor(BotLevel.pro), 'Bot (Profi)', 0)],
        startIndex: 1,
      );
      expect(ctl.botTurn, isTrue);
      ctl.throwDart(ctl.nextBotDart());
      expect(ctl.canUndo, isFalse);
    });

    test('Bilanz gegen Bots wird gespeichert, Bot bekommt keine Statistik', () {
      final ctl = MatchController(
        config: const GameConfig('x01', {'start': 101, 'doubleOut': true, 'legs': 1}),
        players: [p1, GamePlayer(botIdFor(BotLevel.hard), 'Bot (Schwer)', 0)],
      );
      ctl.throwDart(const Dart(20, 3));
      ctl.throwDart(const Dart(1, 1));
      ctl.throwDart(const Dart(20, 2));
      expect(ctl.engine.finished, isTrue);
      ctl.commitStats();
      expect(Store.statsFor('a').bots['hard'], [1, 0]);
      expect(Store.statsFor(botIdFor(BotLevel.hard)).x01.matches, 0);
    });

    test('Turnier-Match trÃ¤gt das Ergebnis ins Turnier ein', () {
      MatchController.onTournamentMatchDone = TournamentStore.onMatchDone;
      final t = Tournament(
        id: 't1',
        name: 'Test',
        created: DateTime(2026),
        system: TSystem.ko,
        players: const [TPlayer('a', 'Anna'), TPlayer('b', 'Ben'), TPlayer('c', 'Cleo')],
        start: 101,
        doubleOut: true,
        formats: const {TStage.sf: TFormat(legs: 1), TStage.finale: TFormat(legs: 1)},
      )..build();
      TournamentStore.save(t);
      final m = t.playable.single; // Ben gegen Cleo (Anna hat Freilos)
      final (a, b) = t.participants(m);
      expect({a, b}, {1, 2});
      // Seite B (Cleo) beginnt und gewinnt
      final ctl = TournamentStore.controllerFor(t, m, 1);
      ctl.throwDart(const Dart(20, 3));
      ctl.throwDart(const Dart(1, 1));
      ctl.throwDart(const Dart(20, 2));
      ctl.commitStats();
      final t2 = TournamentStore.byId('t1')!;
      final m2 = t2.matchById(m.id);
      expect(m2.played, isTrue);
      expect(t2.winnerOf(m2), 2);
      expect(m2.legs, [0, 1]);
      expect(m2.avg(1), greaterThan(0));
      expect(Store.statsFor('c').x01.matches, 1);
      // Finale ist jetzt spielbar: Anna gegen Cleo
      final fin = t2.playable.single;
      expect(t2.participants(fin), (0, 2));
    });

    test('Backup: Export und Import stellen Spieler und Statistik wieder her', () async {
      final prof = Store.ensureProfile('Anna');
      final s = Store.statsFor(prof.id)..tournaments = 3;
      Store.saveStats(prof.id, s);
      final json = Store.exportBackup();
      Store.deleteAllPlayers();
      expect(Store.profiles, isEmpty);
      final n = await Store.importBackup(json);
      expect(n, 1);
      expect(Store.statsFor(prof.id).tournaments, 3);
      expect(() => Store.importBackup('{"foo": 1}'), throwsFormatException);
    });
  });
}

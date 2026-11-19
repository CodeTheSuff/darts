import 'package:darts_counter/games/catalog.dart';
import 'package:darts_counter/games/checkout.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/games/minigames.dart';
import 'package:darts_counter/games/training.dart';
import 'package:darts_counter/games/x01.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:flutter_test/flutter_test.dart';

const p1 = GamePlayer('a', 'Anna', 0xFF5AA9FF);
const p2 = GamePlayer('b', 'Ben', 0xFFF5C84C);

Dart s(int n) => Dart(n, 1);
Dart dd(int n) => Dart(n, 2);
Dart t(int n) => Dart(n, 3);

GameEngine x01({int start = 501, bool dOut = true, int legs = 1, List<GamePlayer> players = const [p1, p2], int startIndex = 0}) =>
    buildEngine(GameConfig('x01', {'start': start, 'doubleOut': dOut, 'legs': legs}), players, startIndex, 1);

void main() {
  group('Checkout', () {
    test('170 = T20 T20 Bull', () => expect(findCheckout(170, 3), ['T20', 'T20', 'Bull']));
    test('40 = D20', () => expect(findCheckout(40, 1), ['D20']));
    test('Bogey 169 nicht möglich', () => expect(findCheckout(169, 3), isNull));
    test('Rest 1 nicht möglich', () => expect(findCheckout(1, 3), isNull));
    test('2-Dart-Finish bei 2 Darts übrig', () => expect(findCheckout(100, 2), ['T20', 'D20']));
    test('Single Out: 3 = 3', () => expect(findCheckout(3, 1, doubleOut: false), ['3']));
  });

  group('X01', () {
    test('Aufnahme wird abgezogen, Spieler wechselt', () {
      final g = x01() as X01Game;
      g.apply(t(20));
      g.apply(t(20));
      final ev = g.apply(t(20));
      expect(g.scores[0], 321);
      expect(ev.turnEnded, isTrue);
      expect(ev.celebration, Celebration.max180);
      expect(g.cur, 1);
    });

    test('Bust bei Rest 1 setzt zurück', () {
      final g = x01(start: 41) as X01Game;
      final ev = g.apply(s(20)) ;
      expect(ev.turnEnded, isFalse);
      final ev2 = g.apply(s(20));
      expect(ev2.bust, isTrue);
      expect(g.scores[0], 41);
      expect(g.cur, 1);
    });

    test('Double Out: 0 ohne Double ist Bust', () {
      final g = x01(start: 40) as X01Game;
      final ev = g.apply(s(20));
      expect(ev.bust, isFalse);
      final ev2 = g.apply(s(20));
      expect(ev2.bust, isTrue);
      expect(g.scores[0], 40);
    });

    test('Checkout gewinnt Leg und Match', () {
      final g = x01(start: 40) as X01Game;
      final ev = g.apply(dd(20));
      expect(ev.gameOver, isTrue);
      expect(g.winner, 0);
      expect(g.stats[0].coHits, 1);
    });

    test('Single Out erlaubt Finish mit Single', () {
      final g = x01(start: 20, dOut: false) as X01Game;
      expect(g.apply(s(20)).gameOver, isTrue);
    });

    test('Anwurf wechselt pro Leg', () {
      final g = x01(start: 40, legs: 2) as X01Game;
      g.apply(dd(20)); // Anna gewinnt Leg 1
      expect(g.cur, 1); // Ben beginnt Leg 2
      expect(g.scores, [40, 40]);
    });

    test('Revanche: Startspieler rückt weiter', () {
      final g = x01(startIndex: 1);
      expect(g.cur, 1);
    });

    test('Bull = 50 als Double-Checkout', () {
      final g = x01(start: 50) as X01Game;
      expect(g.apply(dd(25)).gameOver, isTrue);
    });
  });

  group('Training', () {
    test('Around the Clock klassisch: Triple springt 3 Felder', () {
      final g = buildEngine(const GameConfig('atc', {'variant': 'classic'}), [p1], 0, 1) as AroundTheClockGame;
      g.apply(t(1));
      expect(g.progress[0], 3); // nächstes Ziel: 4
    });

    test('Around the Clock: Schnelltasten nur für das Ziel, Treffer werden gezählt', () {
      final g = buildEngine(const GameConfig('atc', {'variant': 'single'}), [p1], 0, 1) as AroundTheClockGame;
      expect(g.input.kind, InputKind.buttons);
      expect(g.input.buttons.single.field, 1);
      g.apply(s(1));
      expect(g.input.buttons.single.field, 2);
      g.apply(const Dart(0, 1));
      expect(g.hits[0], {'S1': 1, 'Miss': 1});
      expect(g.dartCount[0], 2);
    });

    test('Halve It: Double-Runde sperrt auf Double', () {
      final g = buildEngine(const GameConfig('halveit', {}), [p1], 0, 1) as HalveItGame;
      for (var i = 0; i < 6; i++) {
        g.apply(const Dart(0, 1));
      }
      expect(g.step, 'D');
      expect(g.input.lockedMult, 2);
    });

    test('Around the Clock Doubles: Single zählt nicht', () {
      final g = buildEngine(const GameConfig('atc', {'variant': 'doubles'}), [p1], 0, 1) as AroundTheClockGame;
      g.apply(s(1));
      expect(g.progress[0], 0);
      g.apply(dd(1));
      expect(g.progress[0], 1);
    });

    test("Bob's 27: kein Treffer zieht ab", () {
      final g = buildEngine(const GameConfig('bobs27', {}), [p1], 0, 1) as Bobs27Game;
      g.apply(s(1));
      g.apply(s(1));
      g.apply(s(1));
      expect(g.scores[0], 25);
      g.apply(dd(2));
      g.apply(dd(2));
      g.apply(s(2));
      expect(g.scores[0], 33);
    });

    test('Halve It: ohne Treffer halbiert', () {
      final g = buildEngine(const GameConfig('halveit', {}), [p1], 0, 1) as HalveItGame;
      g.apply(t(15));
      g.apply(s(15));
      g.apply(s(1));
      expect(g.scores[0], 60);
      g.apply(s(1));
      g.apply(s(1));
      g.apply(s(1)); // Runde 16 verfehlt
      expect(g.scores[0], 30);
      expect(g.step, 'D');
    });

    test('Scoring endet nach gewählter Dart-Anzahl', () {
      final g = buildEngine(const GameConfig('scoring', {'darts': 4, 'target': 20}), [p1], 0, 1) as ScoringGame;
      for (var i = 0; i < 3; i++) {
        g.apply(t(20));
      }
      expect(g.finished, isFalse);
      final ev = g.apply(t(20));
      expect(ev.gameOver, isTrue);
      expect(g.points[0], 240);
    });

    test('121: Erfolg erhöht das Ziel', () {
      final g = buildEngine(const GameConfig('121', {'rounds': 5}), [p1], 0, 1) as CheckoutChallengeGame;
      g.apply(t(20));
      g.apply(t(17)); // 121 - 60 - 51 = 10
      final ev = g.apply(dd(5));
      expect(ev.turnEnded, isTrue);
      expect(g.ownTarget[0], 122);
    });

    test('Checkout-Training: 9 Darts ohne Finish = gescheitert', () {
      final g = buildEngine(const GameConfig('checkout', {'range': '41-100', 'rounds': 5}), [p1, p2], 0, 1)
          as CheckoutChallengeGame;
      for (var i = 0; i < 8; i++) {
        expect(g.apply(const Dart(0, 1)).turnEnded, isFalse);
      }
      expect(g.apply(const Dart(0, 1)).turnEnded, isTrue);
      expect(g.cur, 1);
      expect(g.target, g.roundTargets[0]); // gleiche Zahl für alle
    });
  });

  group('Minispiele', () {
    test('Cricket: Triple schließt, weitere Treffer punkten', () {
      final g = buildEngine(const GameConfig('cricket', {'rounds': 20}), [p1, p2], 0, 1) as CricketGame;
      g.apply(t(20));
      g.apply(t(20));
      expect(g.points[0], 60);
    });

    test('Shanghai: S+D+T gewinnt sofort', () {
      final g = buildEngine(const GameConfig('shanghai', {'rounds': 7}), [p1, p2], 0, 1) as ShanghaiGame;
      g.apply(s(1));
      g.apply(dd(1));
      final ev = g.apply(t(1));
      expect(ev.gameOver, isTrue);
      expect(g.shanghaiWinner, 0);
    });

    test('Killer: eigenes Double macht zum Killer', () {
      final g = buildEngine(const GameConfig('killer', {'lives': 3}), [p1, p2], 0, 1) as KillerGame;
      g.apply(dd(g.numbers[0]));
      expect(g.killer[0], isTrue);
      g.apply(dd(g.numbers[1]));
      expect(g.lives[1], 2);
    });
  });
}

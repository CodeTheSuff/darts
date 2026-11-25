import 'package:darts_counter/games/catalog.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/games/minigames.dart';
import 'package:darts_counter/games/training.dart';
import 'package:darts_counter/games/x01.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:flutter_test/flutter_test.dart';

const p1 = GamePlayer('a', 'Anna', 0xFF5AA9FF);
const p2 = GamePlayer('b', 'Ben', 0xFFF5C84C);

GameEngine build(String mode, Map<String, dynamic> opts, {List<GamePlayer> players = const [p1, p2]}) =>
    buildEngine(GameConfig(mode, {...modeById(mode).defaults, ...opts}), players, 0, 1);

void miss(GameEngine g, [int k = 3]) {
  for (var i = 0; i < k; i++) {
    g.apply(const Dart(0, 1));
  }
}

void main() {
  test('Letzte: Darts einzeln plus Summe', () {
    final g = build('x01', {}) as X01Game;
    g.apply(const Dart(20, 3));
    g.apply(const Dart(20, 1));
    g.apply(const Dart(5, 1));
    expect(g.lastLine(0), 'T20 · 20 · 5 = 85');
    expect(g.lastLine(1), '–');
  });

  group('Cricket', () {
    test('Reihenfolge 15 … 20, Bull', () {
      expect(CricketGame.numbers, [15, 16, 17, 18, 19, 20, 25]);
    });
    test('Offen: keine Rundengrenze', () {
      final g = build('cricket', {'rounds': 0}) as CricketGame;
      for (var r = 0; r < 40; r++) {
        miss(g, 6);
      }
      expect(g.finished, isFalse);
      expect(g.subtitle, contains('offen'));
      final limited = build('cricket', {'rounds': 15});
      for (var r = 0; r < 15; r++) {
        miss(limited, 6);
      }
      expect(limited.finished, isTrue);
    });
  });

  group('Killer', () {
    test('Single mit Multiplikator', () {
      final g = build('killer', {'field': 'single', 'lives': 5}) as KillerGame;
      final own = g.numbers[0], other = g.numbers[1];
      expect(g.input.kind, InputKind.full);
      g.apply(Dart(own, 1)); // Killer
      expect(g.killer[0], isTrue);
      g.apply(Dart(other, 3)); // −3
      expect(g.lives[1], 2);
      g.apply(Dart(other, 2)); // −2 → raus
      expect(g.lives[1], 0);
      expect(g.finished, isTrue);
    });
    test('Triple: nur Triple zählt', () {
      final g = build('killer', {'field': 'triple'}) as KillerGame;
      final own = g.numbers[0];
      g.apply(Dart(own, 2));
      expect(g.killer[0], isFalse);
      g.apply(Dart(own, 3));
      expect(g.killer[0], isTrue);
      expect(g.input.buttons.first.mult, 3);
    });
    test('Ohne Einstellung wie bisher Double', () {
      final g = buildEngine(GameConfig('killer', {'lives': 3}), const [p1, p2], 0, 1) as KillerGame;
      g.apply(Dart(g.numbers[0], 1));
      expect(g.killer[0], isFalse);
      g.apply(Dart(g.numbers[0], 2));
      expect(g.killer[0], isTrue);
    });
  });

  test("Bob's 27 mit Minuspunkten spielt bis zum Ende", () {
    final classic = build('bobs27', {}, players: const [p1]) as Bobs27Game;
    miss(classic, 3 * 5);
    expect(classic.finished, isTrue);
    final neg = build('bobs27', {'negative': true}, players: const [p1]) as Bobs27Game;
    miss(neg, 3 * 20);
    expect(neg.finished, isFalse);
    expect(neg.scores[0], lessThan(0));
    miss(neg, 3);
    expect(neg.finished, isTrue);
  });

  test('Halve It: Startpunkte, Standard 40', () {
    expect(modeById('halveit').defaults['startPoints'], 40);
    final g = build('halveit', {'startPoints': 100}, players: const [p1]) as HalveItGame;
    expect(g.scores[0], 100);
    miss(g);
    expect(g.scores[0], 50);
    final old = buildEngine(GameConfig('halveit', {}), const [p1], 0, 1) as HalveItGame;
    expect(old.scores[0], 0);
  });

  group('Bis zum Finish', () {
    test('Catch 40: ab dem 7. Dart 0 Punkte, aber weiter bis zum Check', () {
      final g = build('catch40', {'untilFinish': true}, players: const [p1]) as CheckoutChallengeGame;
      expect(g.target, 61);
      miss(g, 9);
      expect(g.stage, 1);
      expect(g.rest, 61);
      g.apply(const Dart(11, 1));
      g.apply(const Dart(25, 2)); // 61 in 11 Darts
      expect(g.stage, 2);
      expect(g.score[0], 0);
      expect(g.dartsPerTarget[0], [11]);
      // 62 in 2 Darts → 3 Punkte
      g.apply(const Dart(12, 1));
      g.apply(const Dart(25, 2));
      expect(g.score[0], 3);
    });
    test('Begrenzt wie bisher', () {
      final g = build('catch40', {}, players: const [p1]) as CheckoutChallengeGame;
      miss(g, 6);
      expect(g.stage, 2);
    });
    test('Checkout-Training: Stellen-Vorschlag, wenn kein Finish mehr geht', () {
      final g = build('checkout', {'untilFinish': true}, players: const [p1]) as CheckoutChallengeGame;
      // Rest auf 47 bringen ist zufällig – direkt prüfen mit gesetztem Rest.
      g.rests[0] = 47;
      miss(g, 2);
      g.rests[0] = 47;
      final h = g.hint!;
      expect(h.label, 'Stellen');
      expect(h.text, contains('Rest'));
    });
  });
}

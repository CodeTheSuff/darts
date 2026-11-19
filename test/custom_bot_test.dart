import 'dart:math';

import 'package:darts_counter/games/bot.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/games/x01.dart';
import 'package:darts_counter/models/player.dart';
import 'package:flutter_test/flutter_test.dart';

X01Stats simulate(String id, int seed, {int matches = 80}) {
  final rng = Random(seed);
  final total = X01Stats();
  for (var m = 0; m < matches; m++) {
    final bot = Bot.forId(id, rng: rng); // eigene Tagesform pro Match
    for (var leg = 0; leg < 8; leg++) {
      final g = X01Game([const GamePlayer('bot:x', 'Bot', 0)],
          const GameConfig('x01', {'start': 501, 'doubleOut': true, 'legs': 1}));
      g.begin();
      var guard = 0;
      while (!g.finished && guard++ < 900) {
        if (g.turn.isEmpty) bot.startVisit();
        g.apply(bot.next(g.scores[0], 3 - g.turn.length, doubleOut: true));
      }
      total.merge(g.stats[0]);
    }
  }
  return total;
}

void main() {
  test('ID eigener Bots', () {
    expect(customBotId(65, 25), 'bot:c:65:25');
    expect(customBotOf('bot:c:65:25'), (avg: 65, dbl: 25));
    expect(customBotOf('bot:pro'), isNull);
    expect(isBotId(customBotId(40, 10)), isTrue);
    expect(botLevelOf(customBotId(40, 10)), isNull);
  });

  for (final (avg, dbl) in [(25, 8), (40, 15), (55, 30), (65, 25), (80, 35), (95, 45), (105, 40), (60, 50), (90, 15)]) {
    test('Eigener Bot Ø $avg / $dbl % trifft die Werte', () {
      final s = simulate(customBotId(avg, dbl), avg * 31 + dbl);
      expect(s.average, closeTo(avg, max(4.0, avg * 0.06)), reason: 'Average ${s.average}');
      expect(s.coRate, closeTo(dbl.toDouble(), max(4.0, dbl * 0.15)), reason: 'Doppelquote ${s.coRate}');
    });
  }
}

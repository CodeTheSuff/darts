// ignore_for_file: avoid_print
// Kalibrierung der Bot-Streuung: dart run tool/calibrate_bot.dart
import 'dart:math';

import 'package:darts_counter/games/bot.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/games/x01.dart';
import 'package:darts_counter/models/player.dart';

({double avg, double dbl}) simulate(double sScore, double sDouble, {int legs = 1500, int seed = 1}) {
  final rng = Random(seed);
  final st = X01Stats();
  for (var l = 0; l < legs; l++) {
    final g = X01Game([const GamePlayer('b', 'Bot', 0)], const GameConfig('x01', {'start': 501, 'doubleOut': true, 'legs': 1}));
    g.begin();
    var guard = 0;
    while (!g.finished && guard++ < 400) {
      final rest = g.scores[g.cur];
      final left = 3 - g.turn.length;
      final aim = chooseAim(rest, left, doubleOut: true);
      final sigma = aim.isDouble ? sDouble : sScore;
      final p = aim.point;
      double gs() {
        final u1 = rng.nextDouble().clamp(1e-12, 1.0);
        return sqrt(-2 * log(u1)) * cos(2 * pi * rng.nextDouble());
      }
      g.apply(dartAt(p.x + gs() * sigma, p.y + gs() * sigma, rng));
    }
    st.merge(g.stats[0]);
  }
  return (avg: st.average, dbl: st.coRate);
}

void main(List<String> args) {
  if (args.isNotEmpty && args.first == 'levels') {
    for (final p in botProfiles.values) {
      final r = simulate(p.sigmaScore, p.sigmaDouble);
      print('${p.name}: avg ${r.avg.toStringAsFixed(1)}  dbl ${r.dbl.toStringAsFixed(1)} %');
    }
    return;
  }
  for (final s in [6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 13.0, 15.0, 19.0, 22.0, 26.0]) {
    final r = simulate(s, 10, legs: 500);
    print('score sigma $s: avg ${r.avg.toStringAsFixed(1)}');
  }
  for (final d in [6.0, 8.0, 10.0, 12.0, 15.0, 20.0, 26.0, 32.0]) {
    final r = simulate(10, d, legs: 500);
    print('double sigma $d: dbl ${r.dbl.toStringAsFixed(1)}');
  }
}

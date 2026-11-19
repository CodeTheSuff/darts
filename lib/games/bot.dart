import 'dart:math';

import '../models/dart.dart';
import 'checkout.dart';

/// Spielstärke eines Bots.
enum BotLevel { easy, medium, hard, pro }

class BotProfile {
  const BotProfile(this.level, this.name, this.avgLabel, this.dblLabel, this.sigmaScore, this.sigmaDouble);
  final BotLevel level;
  final String name;
  final String avgLabel;
  final String dblLabel;

  /// Streuung in mm (Standardabweichung je Achse) beim Scoren bzw. auf Doubles.
  final double sigmaScore;
  final double sigmaDouble;
}

/// Kalibriert per Simulation (siehe test/bot_test.dart): Average und
/// Doppelquote liegen in den angegebenen Bereichen.
const botProfiles = {
  BotLevel.easy: BotProfile(BotLevel.easy, 'Leicht', 'Ø 30–40', '≈ 10 %', 22, 25),
  BotLevel.medium: BotProfile(BotLevel.medium, 'Mittel', 'Ø 50–60', '≈ 20 %', 14, 14),
  BotLevel.hard: BotProfile(BotLevel.hard, 'Schwer', 'Ø 70–80', '≈ 30 %', 9.5, 10),
  BotLevel.pro: BotProfile(BotLevel.pro, 'Profi', 'Ø 95–105', '≈ 40 %', 5.6, 7.3),
};

const botIdPrefix = 'bot:';

bool isBotId(String profileId) => profileId.startsWith(botIdPrefix);

BotLevel? botLevelOf(String profileId) {
  if (!isBotId(profileId)) return null;
  final key = profileId.substring(botIdPrefix.length);
  return BotLevel.values.where((l) => l.name == key).firstOrNull;
}

/// Eigener Bot: Ziel-Average und Doppelquote (%), kodiert in der ID `bot:c:<avg>:<dbl>`.
String customBotId(int avg, int dbl) => '${botIdPrefix}c:$avg:$dbl';

({int avg, int dbl})? customBotOf(String profileId) {
  final m = RegExp(r'^bot:c:(\d+):(\d+)$').firstMatch(profileId);
  if (m == null) return null;
  return (avg: int.parse(m.group(1)!), dbl: int.parse(m.group(2)!));
}

String customBotName(int avg, int dbl) => 'Bot (Ø $avg · $dbl %)';

/// Grenzen für eigene Bots.
const customAvgMin = 20, customAvgMax = 110, customDblMin = 5, customDblMax = 60;

// Kalibrierung per Simulation (501 Double-Out, je Punkt 2000–3000 Legs).
const _coSigma = [2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 12.0, 14.0, 16.0, 18.0, 20.0, 23.0, 26.0, 30.0, 35.0, 40.0, 48.0, 55.0, 65.0];
const _coRate = [95.8, 89.3, 82.8, 69.6, 57.9, 48.7, 42.2, 37.4, 33.9, 30.3, 25.4, 20.7, 17.3, 14.7, 12.5, 10.2, 8.4, 6.5, 4.9, 3.9, 2.7, 2.1, 1.6];
const _avgS = [3.0, 4.0, 5.0, 6.0, 7.5, 9.0, 11.0, 14.0, 18.0, 22.0, 28.0, 34.0, 45.0, 60.0];
const _avgD = [3.0, 5.0, 7.0, 10.0, 14.0, 20.0, 28.0, 40.0, 55.0];
// Average je Streuung beim Scoren (Zeilen) und auf Doubles (Spalten).
const _avgGrid = [
  [137.6, 131.5, 124.0, 114.5, 102.5, 82.2, 60.6, 41.0, 26.1],
  [128.3, 121.9, 115.2, 107.1, 95.1, 78.4, 58.5, 40.4, 25.2],
  [118.5, 112.7, 107.3, 99.1, 89.7, 75.2, 57.8, 39.7, 24.5],
  [109.6, 105.3, 100.1, 92.5, 84.9, 72.1, 55.0, 38.5, 24.4],
  [98.5, 95.3, 91.5, 85.8, 78.4, 67.2, 52.8, 37.4, 23.9],
  [88.7, 85.8, 82.8, 78.8, 71.4, 61.4, 49.0, 35.3, 22.5],
  [78.3, 76.5, 73.3, 69.7, 65.3, 56.4, 45.6, 33.1, 22.3],
  [65.7, 64.2, 62.6, 59.6, 56.7, 49.9, 41.3, 30.8, 20.8],
  [54.9, 53.8, 52.3, 50.5, 47.8, 42.7, 35.8, 28.2, 19.7],
  [48.2, 47.1, 46.0, 44.5, 42.5, 38.6, 32.8, 25.6, 19.0],
  [42.5, 41.6, 40.7, 39.4, 37.4, 34.0, 29.6, 23.5, 17.7],
  [39.0, 38.4, 37.6, 36.6, 34.4, 31.6, 27.7, 22.2, 16.6],
  [35.2, 34.7, 33.9, 32.8, 31.3, 28.8, 25.4, 20.6, 16.0],
  [31.2, 30.5, 29.9, 28.7, 27.5, 25.5, 22.8, 18.5, 14.6],
];

/// Position von [v] in der aufsteigenden Liste [xs] als (Index, Anteil), begrenzt auf die Ränder.
(int, double) _locate(List<double> xs, double v) {
  if (v <= xs.first) return (0, 0);
  if (v >= xs.last) return (xs.length - 2, 1);
  var i = 0;
  while (xs[i + 1] < v) {
    i++;
  }
  return (i, (v - xs[i]) / (xs[i + 1] - xs[i]));
}

/// Erwarteter Average bei Streuung [ss] (Scoren) und [sd] (Doubles).
double expectedAverage(double ss, double sd) {
  final (i, fi) = _locate(_avgS, ss);
  final (j, fj) = _locate(_avgD, sd);
  double row(int r) => _avgGrid[r][j] * (1 - fj) + _avgGrid[r][j + 1] * fj;
  return row(i) * (1 - fi) + row(i + 1) * fi;
}

/// Streuung auf Doubles für eine Doppelquote in Prozent.
double sigmaForDoubleRate(int dbl) {
  final d = dbl.toDouble();
  if (d >= _coRate.first) return _coSigma.first;
  for (var i = 0; i < _coRate.length - 1; i++) {
    if (d >= _coRate[i + 1]) {
      final f = (_coRate[i] - d) / (_coRate[i] - _coRate[i + 1]);
      return _coSigma[i] + (_coSigma[i + 1] - _coSigma[i]) * f;
    }
  }
  return _coSigma.last;
}

/// Streuung beim Scoren, damit bei Double-Streuung [sd] der Average [avg] herauskommt.
/// Nicht erreichbare Kombinationen werden so gut wie möglich angenähert.
double sigmaForAverage(int avg, double sd) {
  var lo = _avgS.first, hi = _avgS.last;
  for (var k = 0; k < 40; k++) {
    final mid = (lo + hi) / 2;
    if (expectedAverage(mid, sd) > avg) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}

/// Ist die Kombination realistisch erreichbar (±3 Punkte)?
bool customBotReachable(int avg, int dbl) {
  final sd = sigmaForDoubleRate(dbl);
  return (expectedAverage(sigmaForAverage(avg, sd), sd) - avg).abs() <= 3;
}

String botIdFor(BotLevel l) => '$botIdPrefix${l.name}';
String botNameFor(BotLevel l) => 'Bot (${botProfiles[l]!.name})';

// ------------------------------------------------------------- Geometrie

/// Reihenfolge der Segmente im Uhrzeigersinn, oben beginnend.
const boardOrder = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5];

// Radien in mm (Turnierscheibe).
const _rBull = 6.35;
const _rOuterBull = 15.9;
const _rTripleIn = 99.0;
const _rTripleOut = 107.0;
const _rDoubleIn = 162.0;
const _rDoubleOut = 170.0;

/// Ein Zielfeld des Bots.
class Aim {
  const Aim(this.field, this.mult);
  final int field;
  final int mult;

  /// Zielpunkt in mm (x nach rechts, y nach oben).
  ({double x, double y}) get point {
    if (field == 25) return (x: 0, y: 0);
    final k = boardOrder.indexOf(field);
    final ang = k * pi / 10; // im Uhrzeigersinn ab oben
    final r = switch (mult) {
      3 => (_rTripleIn + _rTripleOut) / 2,
      2 => (_rDoubleIn + _rDoubleOut) / 2,
      _ => 60.0, // dickes inneres Single
    };
    return (x: r * sin(ang), y: r * cos(ang));
  }

  bool get isDouble => mult == 2;

  @override
  String toString() => field == 25 ? (mult == 2 ? 'Bull' : '25') : '${mult == 3 ? 'T' : mult == 2 ? 'D' : ''}$field';
}

/// Wertet einen Punkt (mm) aus und erzeugt den passenden Pfeil inkl. Lage
/// für die Darstellung auf der Scheibe.
Dart dartAt(double x, double y, Random rng) {
  final r = sqrt(x * x + y * y);
  var deg = atan2(x, y) * 180 / pi; // 0 = oben, im Uhrzeigersinn
  if (deg < 0) deg += 360;
  final tilt = 16 + rng.nextDouble() * 22;
  if (r > _rDoubleOut) {
    return Dart(0, 1, jitterA: (deg / 180) - 1, jitterR: ((r - _rDoubleOut) / 30).clamp(0.0, 1.0), tilt: tilt);
  }
  if (r <= _rOuterBull) {
    final inBull = r <= _rBull;
    return Dart(25, inBull ? 2 : 1,
        jitterA: deg / 180 - 1,
        jitterR: inBull ? r / _rBull : (r - _rBull) / (_rOuterBull - _rBull),
        tilt: tilt);
  }
  final k = ((deg + 9) ~/ 18) % 20;
  final field = boardOrder[k];
  var off = deg - k * 18;
  if (off > 180) off -= 360;
  final ja = (off / 9).clamp(-1.0, 1.0);
  if (r >= _rDoubleIn) {
    return Dart(field, 2, jitterA: ja, jitterR: (r - _rDoubleIn) / (_rDoubleOut - _rDoubleIn), tilt: tilt);
  }
  if (r >= _rTripleIn && r <= _rTripleOut) {
    return Dart(field, 3, jitterA: ja, jitterR: (r - _rTripleIn) / (_rTripleOut - _rTripleIn), tilt: tilt);
  }
  final inner = r < _rTripleIn;
  final jr = inner
      ? (r - _rOuterBull) / (_rTripleIn - _rOuterBull)
      : (r - _rTripleOut) / (_rDoubleIn - _rTripleOut);
  return Dart(field, 1, jitterA: ja, jitterR: jr.clamp(0.0, 1.0), tilt: tilt, inner: inner);
}

// ------------------------------------------------------------- Strategie

Aim _parse(String label) {
  if (label == 'Bull') return const Aim(25, 2);
  if (label == '25') return const Aim(25, 1);
  if (label.startsWith('T')) return Aim(int.parse(label.substring(1)), 3);
  if (label.startsWith('D')) return Aim(int.parse(label.substring(1)), 2);
  return Aim(int.parse(label), 1);
}

/// Beliebte Rest-Doubles, beste zuerst.
const _preferredLeaves = [32, 40, 16, 36, 24, 20, 8, 12, 28, 18, 10, 4, 2];

/// Wählt das Ziel für den nächsten Pfeil – wie ein echter Spieler.
Aim chooseAim(int rest, int dartsLeft, {required bool doubleOut}) {
  final route = findCheckout(rest, dartsLeft, doubleOut: doubleOut);
  if (route != null) return _parse(route.first);
  if (!doubleOut) return const Aim(20, 3);
  if (rest > 100) {
    // Unbequeme Reste vermeiden: bei 160+ lieber auf die 19 ausweichen,
    // wenn 60 einen Bogey-Rest hinterlässt.
    if (bogeyNumbers.contains(rest - 60) && !bogeyNumbers.contains(rest - 57)) return const Aim(19, 3);
    return const Aim(20, 3);
  }
  // Stellen: einen Wurf so platzieren, dass ein gutes Double übrig bleibt.
  for (final leave in _preferredLeaves) {
    final v = rest - leave;
    if (v >= 1 && v <= 20) return Aim(v, 1);
    if (v == 25) return const Aim(25, 1);
  }
  for (final leave in _preferredLeaves) {
    final v = rest - leave;
    if (v > 0 && v % 3 == 0 && v ~/ 3 <= 20) return Aim(v ~/ 3, 3);
  }
  if (rest > 60) return const Aim(20, 3);
  // Ungerader kleiner Rest: auf eine Single, die eine gerade Zahl übrig lässt.
  return Aim(rest > 21 ? 19 : (rest - 2).clamp(1, 20), 1);
}

// ------------------------------------------------------------- Bot

/// Ein Bot mit Tagesform. Jede Aufnahme schwankt leicht.
class Bot {
  Bot(BotLevel level, {Random? rng})
      : this.custom(botProfiles[level]!.sigmaScore, botProfiles[level]!.sigmaDouble, rng: rng);

  /// Bot mit frei gewählter Streuung (mm) beim Scoren und auf Doubles.
  Bot.custom(this.sigmaScore, this.sigmaDouble, {Random? rng, bool noForm = false}) : rng = rng ?? Random() {
    // Tagesform: etwa ±10 % beim Average.
    form = noForm ? 1 : 1 + (this.rng.nextDouble() * 2 - 1) * 0.11;
    _newVisit();
  }

  /// Bot passend zur Spieler-ID (Stufe oder eigener Bot).
  factory Bot.forId(String profileId, {Random? rng}) {
    final c = customBotOf(profileId);
    if (c != null) {
      final sd = sigmaForDoubleRate(c.dbl);
      return Bot.custom(sigmaForAverage(c.avg, sd), sd, rng: rng);
    }
    return Bot(botLevelOf(profileId) ?? BotLevel.medium, rng: rng);
  }

  final double sigmaScore;
  final double sigmaDouble;
  final Random rng;
  late double form;
  double _visit = 1;

  double _gauss() {
    // Box-Muller
    final u1 = rng.nextDouble().clamp(1e-12, 1.0);
    final u2 = rng.nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }

  void _newVisit() => _visit = exp(_gauss() * 0.07);

  /// Zu Beginn jeder Aufnahme aufrufen.
  void startVisit() => _newVisit();

  /// Wirft einen Pfeil auf [aim].
  Dart throwAt(Aim aim) {
    final base = aim.isDouble || (aim.field == 25 && aim.mult == 2) ? sigmaDouble : sigmaScore;
    final sigma = base * form * _visit;
    final p = aim.point;
    return dartAt(p.x + _gauss() * sigma, p.y + _gauss() * sigma, rng);
  }

  /// Nächster Pfeil im X01 bei Rest [rest].
  Dart next(int rest, int dartsLeft, {required bool doubleOut}) =>
      throwAt(chooseAim(rest, dartsLeft, doubleOut: doubleOut));
}

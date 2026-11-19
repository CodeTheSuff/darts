/// Berechnet Checkout-Wege (max. 3 Darts).
library;

import 'checkout_table.dart';

class _Seg {
  final String label;
  final int value;
  const _Seg(this.label, this.value);
}

final List<_Seg> _setupDefault = [
  for (var i = 20; i >= 1; i--) _Seg('T$i', i * 3),
  for (var i = 20; i >= 1; i--) _Seg('$i', i),
  const _Seg('25', 25),
  const _Seg('Bull', 50),
];

const _doubleOrder = [20, 16, 18, 12, 10, 8, 19, 17, 15, 14, 13, 11, 9, 7, 6, 5, 4, 3, 2, 1];

final List<_Seg> _doubles = [
  for (final n in _doubleOrder) _Seg('D$n', n * 2),
  const _Seg('Bull', 50),
];

/// Single Out: natürliche Reihenfolge – erst Singles, dann Bull, Doubles, Triples.
final List<_Seg> _any = [
  for (var i = 20; i >= 1; i--) _Seg('$i', i),
  const _Seg('25', 25),
  ..._doubles,
  for (var i = 20; i >= 1; i--) _Seg('T$i', i * 3),
];

/// Single Out ohne Doubles (für Spieler, die am Double festhängen).
final List<_Seg> _noDouble = [
  for (var i = 20; i >= 1; i--) _Seg('$i', i),
  const _Seg('25', 25),
  for (var i = 20; i >= 1; i--) _Seg('T$i', i * 3),
];

/// Beliebte Rest-Doubles für den Stellwurf, beste zuerst (D16, D20, D8 …).
const preferredLeaves = [32, 40, 16, 36, 24, 20, 8, 12, 28, 18, 10, 4, 2];

String _doubleName(int leave) => leave == 50 ? 'Bull' : 'D${leave ~/ 2}';

/// Stellwurf, wenn mit den restlichen Darts kein Finish mehr geht (nur Double Out):
/// ein Wurf, der einen guten Rest übrig lässt – z. B. 47 → „15“ (Rest 32, D16).
({String aim, int leave, String text})? setupShot(int rest) {
  if (rest < 3) return null;
  // 1. Ein Single auf ein beliebtes Double
  for (final leave in preferredLeaves) {
    final v = rest - leave;
    if (v >= 1 && v <= 20) return (aim: '$v', leave: leave, text: '$v · Rest $leave (${_doubleName(leave)})');
  }
  // 1b. Die 25
  for (final leave in preferredLeaves) {
    if (rest - leave == 25) return (aim: '25', leave: leave, text: '25 · Rest $leave (${_doubleName(leave)})');
  }
  // 2. Ein Triple auf ein beliebtes Double
  for (final leave in preferredLeaves) {
    final v = rest - leave;
    if (v > 0 && v % 3 == 0 && v ~/ 3 <= 20) {
      return (aim: 'T${v ~/ 3}', leave: leave, text: 'T${v ~/ 3} · Rest $leave (${_doubleName(leave)})');
    }
  }
  // 3. Höhere Reste: T20 bzw. T19, ohne auf einer Bogey-Zahl zu landen
  for (final (aim, v) in const [('T20', 60), ('T19', 57), ('T18', 54)]) {
    final leave = rest - v;
    if (leave >= 2 && !bogeyNumbers.contains(leave) && leave <= 170) {
      return (aim: aim, leave: leave, text: '$aim · Rest $leave');
    }
  }
  return null;
}

/// Unmögliche Checkouts (Double Out) zwischen 2 und 170.
const bogeyNumbers = {159, 162, 163, 165, 166, 168, 169};

/// Liefert einen sinnvollen Checkout-Weg oder `null`.
List<String>? findCheckout(int rest, int dartsLeft, {bool doubleOut = true, bool avoidDoubles = false}) {
  // Double Out: zuerst der übliche Weg aus der Standardtabelle, sofern er mit den übrigen Darts passt.
  if (doubleOut) {
    final std = standardCheckouts[rest];
    if (std != null && std.length <= dartsLeft) return List.of(std);
  }
  if (!doubleOut && avoidDoubles) {
    final r = _route(rest, dartsLeft, _noDouble, 180, 1, setup: _noDouble);
    if (r != null) return r;
  }
  return _route(rest, dartsLeft, doubleOut ? _doubles : _any, doubleOut ? 170 : 180, doubleOut ? 2 : 1);
}

List<String>? _route(int rest, int dartsLeft, List<_Seg> finals, int max, int min, {List<_Seg>? setup}) {
  final segs = setup ?? _setupDefault;
  if (dartsLeft <= 0) return null;
  if (rest > max || rest < min) return null;

  for (final f in finals) {
    if (f.value == rest) return [f.label];
  }
  if (dartsLeft < 2) return null;

  List<String>? best;
  var bestCost = 1 << 30;
  for (var d = 0; d < finals.length; d++) {
    for (var a = 0; a < segs.length; a++) {
      if (segs[a].value + finals[d].value == rest) {
        final cost = d * 4 + a;
        if (cost < bestCost) {
          bestCost = cost;
          best = [segs[a].label, finals[d].label];
        }
      }
    }
  }
  if (best != null) return best;
  if (dartsLeft < 3) return null;

  for (var d = 0; d < finals.length; d++) {
    final need = rest - finals[d].value;
    if (need < 2) continue;
    for (var a = 0; a < segs.length; a++) {
      final rem = need - segs[a].value;
      if (rem < 1) continue;
      for (var b = a; b < segs.length; b++) {
        if (segs[b].value == rem) {
          final cost = d * 4 + a + b;
          if (cost < bestCost) {
            bestCost = cost;
            best = [segs[a].label, segs[b].label, finals[d].label];
          }
        }
      }
    }
  }
  return best;
}

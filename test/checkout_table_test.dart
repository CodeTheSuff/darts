import 'package:darts_counter/games/checkout.dart';
import 'package:darts_counter/games/checkout_table.dart';
import 'package:flutter_test/flutter_test.dart';

int _value(String l) {
  if (l == 'Bull') return 50;
  if (l == '25') return 25;
  if (l.startsWith('T')) return 3 * int.parse(l.substring(1));
  if (l.startsWith('D')) return 2 * int.parse(l.substring(1));
  return int.parse(l);
}

bool _isDouble(String l) => l == 'Bull' || l.startsWith('D');

bool _valid(String l) {
  if (l == 'Bull' || l == '25') return true;
  final n = int.tryParse(l.replaceFirst(RegExp('^[TD]'), ''));
  return n != null && n >= 1 && n <= 20;
}

void main() {
  test('Standardtabelle: jede Zahl von 2 bis 170 außer den Bogey-Zahlen, jeder Weg stimmt', () {
    for (var r = 2; r <= 170; r++) {
      final route = standardCheckouts[r];
      if (bogeyNumbers.contains(r)) {
        expect(route, isNull, reason: '$r ist nicht checkbar');
        continue;
      }
      expect(route, isNotNull, reason: 'Weg für $r fehlt');
      expect(route!.length, inInclusiveRange(1, 3), reason: '$r');
      expect(route.every(_valid), isTrue, reason: '$r: $route');
      expect(route.map(_value).reduce((a, b) => a + b), r, reason: '$r: $route');
      expect(_isDouble(route.last), isTrue, reason: '$r endet nicht auf Double: $route');
    }
  });

  test('Bekannte TV-Wege werden vorgeschlagen', () {
    expect(findCheckout(170, 3), ['T20', 'T20', 'Bull']);
    expect(findCheckout(121, 3), ['T20', 'T11', 'D14']);
    expect(findCheckout(100, 3), ['T20', 'D20']);
    expect(findCheckout(82, 3), ['Bull', 'D16']);
    expect(findCheckout(32, 1), ['D16']);
  });

  test('Mit weniger Darts greift die Berechnung, wenn der Tabellenweg zu lang ist', () {
    expect(findCheckout(120, 2), isNull); // nicht mit 2 Darts möglich
    final r = findCheckout(41, 1);
    expect(r, isNull);
    final two = findCheckout(121, 2);
    expect(two, isNull);
    final t = findCheckout(99, 2);
    expect(t, isNull);
    final ok = findCheckout(110, 2);
    expect(ok, ['T20', 'Bull']);
    expect(findCheckout(57, 1), isNull);
    expect(findCheckout(57, 2), ['17', 'D20']);
  });
}

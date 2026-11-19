import 'package:darts_counter/games/checkout.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/games/x01.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Stellwurf bevorzugt Singles auf beliebte Doubles', () {
    expect(setupShot(47)!.text, '15 · Rest 32 (D16)');
    expect(setupShot(48)!.aim, '16'); // 48 → 32
    expect(setupShot(41)!.text, '9 · Rest 32 (D16)');
    expect(setupShot(65)!.text, '25 · Rest 40 (D20)'); // wie in der Standardtabelle
    expect(setupShot(3)!.text, '1 · Rest 2 (D1)');
    expect(setupShot(57)!.text, '17 · Rest 40 (D20)');
    expect(setupShot(68)!.text, 'T12 · Rest 32 (D16)');
    expect(setupShot(99)!.text, 'T20 · Rest 39'); // hohe Reste: T20, solange kein Bogey bleibt
    expect(setupShot(222), isNull);
  });

  test('X01 zeigt den Stell-Tipp, wenn mit den restlichen Darts kein Finish geht', () {
    final g = X01Game([const GamePlayer('a', 'A', 0)], const GameConfig('x01', {'start': 501, 'doubleOut': true, 'legs': 1}))
      ..begin();
    // 501 → 47: 3 Aufnahmen
    for (final d in const [Dart(20, 3), Dart(20, 3), Dart(20, 3), Dart(20, 3), Dart(20, 3), Dart(20, 3), Dart(19, 3), Dart(20, 1), Dart(17, 1)]) {
      g.apply(d);
    }
    expect(g.scores[0], 47);
    // 3 Darts übrig: 47 ist checkbar (15 D16) → Checkout
    expect(g.hint!.label, 'Checkout');
    g.apply(const Dart(0, 1));
    g.apply(const Dart(0, 1));
    // 1 Dart übrig, 47 nicht mit einem Dart checkbar → Stellen
    expect(g.hint!.label, 'Stellen');
    expect(g.hint!.text, '15 · Rest 32 (D16)');
  });
}

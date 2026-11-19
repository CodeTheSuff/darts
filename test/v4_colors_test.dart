import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/games/catalog.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/models/player.dart';
import 'package:darts_counter/ui/keypad.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const blue = Color(0xFF5AA9FF);
const yellow = Color(0xFFF5C84C);
const pA = GamePlayer('a', 'Anna', 0xFF5AA9FF);
const pB = GamePlayer('b', 'Ben', 0xFFF5C84C);

Key3 keyFor(WidgetTester t, String semantics) =>
    t.widget<Key3>(find.byWidgetPredicate((w) => w is Key3 && w.semantics == semantics));

Future<void> pumpKeypad(WidgetTester t, InputSpec spec, {Color color = blue}) async {
  await t.pumpWidget(MaterialApp(
    theme: buildTheme(C.p),
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: Keypad(spec: spec, color: color, onDart: (_, _) {}, onUndo: () {}, canUndo: false),
      ),
    ),
  ));
}

InputSpec inputOf(String mode, Map<String, dynamic> opts, {List<GamePlayer> players = const [pA, pB]}) =>
    buildEngine(GameConfig(mode, {...modeById(mode).defaults, ...opts}), players, 0, 1).input;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });

  for (final p in palettes) {
    test('${p.name}: Triple ist orange, Miss rot, beide verschieden von Double', () {
      expect(p.trp.r, greaterThan(p.trp.b)); // warm
      expect(p.trp.g, greaterThan(0.3)); // orange statt rot
      expect(p.miss.r, greaterThan(0.85));
      expect(p.miss.g, lessThan(0.45));
      expect(p.trp, isNot(p.miss));
      expect(p.trp, isNot(p.dbl));
    });
  }

  testWidgets('Normale Tastatur: Miss rot, Triple-Schalter orange', (t) async {
    await pumpKeypad(t, const InputSpec.full());
    final miss = keyFor(t, 'Miss');
    expect(miss.borderColor!.withValues(alpha: 1), C.miss);
    final triple = keyFor(t, 'Triple');
    expect(triple.borderColor!.withValues(alpha: 1), C.trp);
  });

  testWidgets('Around the Clock Doubles/Triples: Treffer-Taste in Spielerfarbe', (t) async {
    for (final v in ['doubles', 'triples', 'single']) {
      await pumpKeypad(t, inputOf('atc', {'variant': v}));
      final hit = t.widget<Key3>(
          find.byWidgetPredicate((w) => w is Key3 && (w.semantics ?? '').contains('Getroffen')));
      expect(hit.borderColor!.withValues(alpha: 1), blue, reason: v);
      expect(keyFor(t, 'Miss').borderColor!.withValues(alpha: 1), C.miss);
    }
  });

  testWidgets('Klassisch/Shanghai: S, D, T in Spielerfarbe, kräftiger je Multiplikator', (t) async {
    for (final mode in ['atc', 'shanghai']) {
      await pumpKeypad(t, inputOf(mode, {}), color: yellow);
      final keys = t
          .widgetList<Key3>(find.byWidgetPredicate((w) => w is Key3 && (w.semantics ?? '').contains('Single') ||
              w is Key3 && (w.semantics ?? '').contains('Double') ||
              w is Key3 && (w.semantics ?? '').contains('Triple')))
          .toList();
      expect(keys.length, 3, reason: mode);
      final alphas = [for (final k in keys) k.borderColor!.a];
      for (final k in keys) {
        expect(k.borderColor!.withValues(alpha: 1), yellow, reason: mode);
      }
      expect(alphas[0] < alphas[1] && alphas[1] < alphas[2], isTrue, reason: '$mode $alphas');
    }
  });

  testWidgets("Bob's 27: Treffer-Taste in Spielerfarbe", (t) async {
    await pumpKeypad(t, inputOf('bobs27', {}));
    final hit = t.widget<Key3>(find.byWidgetPredicate((w) => w is Key3 && (w.semantics ?? '').contains('Treffer')));
    expect(hit.borderColor!.withValues(alpha: 1), blue);
  });

  testWidgets('Killer: Double-Tasten in der Farbe des Ziel-Spielers', (t) async {
    final spec = buildEngine(GameConfig('killer', modeById('killer').defaults), const [pA, pB], 0, 1).input;
    expect(spec.buttons.map((b) => b.color).toSet(), {pA.color, pB.color});
    await pumpKeypad(t, spec);
    final benKey =
        t.widget<Key3>(find.byWidgetPredicate((w) => w is Key3 && (w.semantics ?? '').endsWith('Ben')));
    expect(benKey.borderColor!.withValues(alpha: 1), yellow);
  });
}

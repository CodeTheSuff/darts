import 'dart:io';

import 'package:darts_counter/data/callouts.dart';
import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/games/catalog.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:darts_counter/ui/celebration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const t20 = Dart(20, 3), miss = Dart(0, 1), bull = Dart(25, 2);

MatchController _ctl({int start = 501, String mode = 'x01', int players = 2}) => MatchController(
      config: GameConfig(mode, {'start': start, 'doubleOut': true, 'legs': 1}),
      players: [for (var i = 0; i < players; i++) GamePlayer('p$i', 'P$i', i)],
    );

/// Sounds für jeden Pfeil einer Aufnahme (gesammelt).
List<String> _sounds(MatchController c, List<Dart> darts) => [
      for (final d in darts) ...Callouts.soundsFor(c.throwDart(d), c.engine),
    ];

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'sound': true});
    await Store.init();
  });

  test('Für jeden Wert 80–180 gibt es eine Datei, dazu bullseye, 1 und you_win', () {
    for (var v = Callouts.minScore; v <= Callouts.maxScore; v++) {
      expect(File('assets/callouts/$v.wav').existsSync(), isTrue, reason: '$v.wav fehlt');
    }
    for (final n in ['bullseye', '1', 'you_win']) {
      expect(File('assets/callouts/$n.wav').existsSync(), isTrue, reason: '$n.wav fehlt');
    }
  });

  test('Aufnahmesumme 80–180: Sound nach dem dritten Pfeil, darunter keiner', () {
    final c = _ctl();
    expect(_sounds(c, const [t20, t20, t20]), ['180']);
    expect(_sounds(c, const [Dart(20, 1), Dart(20, 1), Dart(20, 1)]), isEmpty); // 60
    expect(_sounds(c, const [t20, Dart(20, 1), Dart(5, 1)]), ['85']);
  });

  test('Bullseye sofort beim Pfeil, die 25 nicht', () {
    final c = _ctl();
    expect(Callouts.soundsFor(c.throwDart(bull), c.engine), ['bullseye']);
    expect(Callouts.soundsFor(c.throwDart(const Dart(25, 1)), c.engine), isEmpty);
    // dritter Pfeil: Summe 50+25+60 = 135
    expect(Callouts.soundsFor(c.throwDart(t20), c.engine), ['135']);
  });

  test('Alle drei Pfeile in der 1 (egal ob Single, Double, Triple) → „1“', () {
    final c = _ctl();
    expect(_sounds(c, const [Dart(1, 1), Dart(1, 2), Dart(1, 3)]), ['1']);
    expect(_sounds(c, const [Dart(1, 1), Dart(1, 1), Dart(20, 1)]), isEmpty);
  });

  test('Dreimal die 1 in Trainings und Minispielen: keine Ansage', () {
    for (final mode in ['cricket', 'shanghai', 'atc', 'halveit']) {
      final c = MatchController(
        config: GameConfig(mode, Map.of(modeById(mode).defaults)),
        players: const [GamePlayer('p0', 'P0', 0), GamePlayer('p1', 'P1', 1)],
      );
      final out = _sounds(c, const [Dart(1, 1), Dart(1, 1), Dart(1, 1)]);
      expect(out.contains('1'), isFalse, reason: mode);
    }
  });

  test('Überworfen: kein Zahlen-Sound', () {
    final c = _ctl(start: 101);
    expect(_sounds(c, const [t20, t20]), isEmpty); // 120 > 101 → überworfen
  });

  test('Checkout mit Zahl und am Match-Ende „You win“', () {
    final c = _ctl(start: 121);
    expect(_sounds(c, const [t20, Dart(11, 3), Dart(14, 2)]), ['121', 'you_win']);
    final small = _ctl(start: 40);
    expect(_sounds(small, const [Dart(20, 2)]), ['you_win']);
  });

  test('Schalter aus: keine Ansagen; alte Jubel-Töne nur dann', () {
    Store.announce = true;
    expect(celebrationSound(CelebrationKind.max180), isNull);
    expect(celebrationSound(CelebrationKind.match), isNull);
    expect(celebrationSound(CelebrationKind.legWon), 'leg');
    Store.announce = false;
    expect(Callouts.active, isFalse);
    expect(celebrationSound(CelebrationKind.max180), 'max180');
  });

  test('Abspielen in der richtigen Reihenfolge (Anzeige)', () async {
    final played = <String>[];
    Callouts.player = (n) async => played.add(n);
    Callouts.isDisplay = true;
    final c = _ctl(start: 170);
    for (final d in const [t20, t20, bull]) {
      Callouts.onThrow(c.throwDart(d), c.engine);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(played, ['bullseye', '170', 'you_win']);
    Callouts.isDisplay = false;
  });
}

import 'package:darts_counter/data/match_controller.dart';
import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/games/bot.dart';
import 'package:darts_counter/games/engine.dart';
import 'package:darts_counter/games/tournament.dart';
import 'package:darts_counter/models/dart.dart';
import 'package:darts_counter/models/player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Tournament _t() => Tournament(
      id: 't1',
      name: 'Liga',
      created: DateTime(2026),
      system: TSystem.league,
      players: const [TPlayer('a', 'Anna'), TPlayer('b', 'Ben'), TPlayer('c', 'Cleo')],
      start: 501,
      doubleOut: true,
      formats: const {TStage.group: TFormat(legs: 1)},
    )..build();

MatchController _vsBot() => MatchController(
      config: const GameConfig('x01', {'start': 501, 'doubleOut': true, 'legs': 1}),
      players: [const GamePlayer('h', 'Simon', 0), GamePlayer(botIdFor(BotLevel.easy), 'Bot', 1)],
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });

  test('Fremde Darts: ungültige Werte, Bot-Zug und gesperrte Eingabe werden ignoriert', () {
    expect(MatchController.isValidDart(const Dart(99, 3)), isFalse);
    expect(MatchController.isValidDart(const Dart(25, 3)), isFalse);
    expect(MatchController.isValidDart(const Dart(0, 2)), isFalse);
    expect(MatchController.isValidDart(const Dart(20, 3)), isTrue);
    expect(MatchController.isValidDart(Dart.singleOutOn), isTrue);
    final c = _vsBot();
    c.throwDartExternal(const Dart(99, 3));
    expect(c.darts, isEmpty);
    c.inputLocked = true;
    c.throwDartExternal(const Dart(20, 1));
    expect(c.darts, isEmpty);
    c.inputLocked = false;
    for (var i = 0; i < 3; i++) {
      c.throwDartExternal(const Dart(20, 1));
    }
    expect(c.botTurn, isTrue);
    c.throwDartExternal(const Dart(20, 3)); // Bot ist dran → nicht annehmen
    expect(c.darts.length, 3);
  });

  test('Rückgängig-Prüfung wird zwischengespeichert und bleibt korrekt', () {
    final c = _vsBot();
    expect(c.canUndo, isFalse);
    c.throwDart(const Dart(20, 1));
    expect(c.canUndo, isTrue);
    expect(c.canUndo, isTrue);
    c.undo();
    expect(c.canUndo, isFalse);
  });

  test('Turnier-Abgleich: verschiedene Matches und Korrekturen werden zusammengeführt', () {
    final a = _t();
    final b = Tournament.fromJson(a.toJson());
    final m1 = a.matches[0], m2 = a.matches[1];
    // A trägt Match 1 ein, B trägt Match 2 ein (gleiche Anzahl gespielter Matches)
    a.record(m1.id, winnerSide: 0, legs: [1, 0]);
    b.record(m2.id, winnerSide: 1, legs: [0, 1]);
    expect(a.playedCount, b.playedCount);
    expect(a.revision == b.revision, isFalse);
    expect(a.mergeFrom(b), isTrue);
    expect(b.mergeFrom(a), isTrue);
    expect(a.playedCount, 2);
    expect(b.matchById(m1.id).winnerSide, 0);
    expect(a.matchById(m2.id).winnerSide, 1);
    // spätere Korrektur auf A (gleiche Anzahl gespielter Matches)
    a.record(m1.id, winnerSide: 1, legs: [0, 1]);
    a.matchById(m1.id).at = DateTime.now().millisecondsSinceEpoch + 1000;
    expect(b.mergeFrom(a), isTrue);
    expect(b.matchById(m1.id).winnerSide, 1);
    // nichts Neues → keine Änderung, gleiche Kennung
    expect(b.mergeFrom(a), isFalse);
    expect(a.revision, b.revision);
  });
}

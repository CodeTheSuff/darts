import '../models/player.dart';
import 'engine.dart';
import 'minigames.dart';
import 'training.dart';
import 'x01.dart';

enum ModeCategory { game, training, mini }

class OptionChoice {
  const OptionChoice(this.value, this.label);
  final Object value;
  final String label;
}

/// Eine Einstellung im Setup: entweder Auswahl ([choices]) oder Zahl ([min]..[max]).
class OptionDef {
  const OptionDef.choice(this.key, this.label, this.choices, this.defaultValue)
      : min = 0,
        max = 0,
        step = 1,
        presets = const [];

  const OptionDef.number(this.key, this.label, this.defaultValue,
      {required this.min, required this.max, this.step = 1, this.presets = const []})
      : choices = const [];

  final String key;
  final String label;
  final List<OptionChoice> choices;
  final Object defaultValue;
  final int min;
  final int max;
  final int step;
  final List<int> presets;

  bool get isNumber => choices.isEmpty;
}

typedef EngineFactory = GameEngine Function(
    List<GamePlayer> players, GameConfig config, int startIndex, int seed);

class ModeDef {
  const ModeDef({
    required this.id,
    required this.name,
    required this.category,
    required this.short,
    required this.rules,
    required this.options,
    required this.create,
    this.minPlayers = 1,
    this.metricLabel,
    this.lowerIsBetter = false,
  });

  final String id;
  final String name;
  final ModeCategory category;
  final String short;
  final String rules;
  final List<OptionDef> options;
  final EngineFactory create;
  final int minPlayers;

  /// Beschriftung der Bestleistung in der Statistik (null = keine).
  final String? metricLabel;
  final bool lowerIsBetter;

  Map<String, dynamic> get defaults => {for (final o in options) o.key: o.defaultValue};
}

const _rounds = [
  OptionChoice(5, '5'),
  OptionChoice(10, '10'),
  OptionChoice(15, '15'),
  OptionChoice(20, '20'),
];

/// Checkout-Training/Catch 40: Darts begrenzt (9 bzw. 6) oder werfen, bis gecheckt ist.
const _untilFinish = OptionDef.choice(
    'untilFinish', 'Darts', [OptionChoice(false, 'Begrenzt'), OptionChoice(true, 'Bis zum Finish')], false);

final List<ModeDef> modes = [
  ModeDef(
    id: 'x01',
    name: 'X01',
    category: ModeCategory.game,
    short: '301 · 501 · 701 – das klassische Match',
    rules:
        'Jeder startet mit der gewählten Punktzahl und zählt herunter. Wer genau auf 0 kommt '
        '(bei Double Out mit einem Double), gewinnt das Leg. Zu viel geworfen oder Rest 1 = Bust. '
        'Im Sets-Modus gewinnt ein Set, wer zuerst die eingestellten Legs holt.',
    options: const [
      OptionDef.choice('start', 'Startpunkte',
          [OptionChoice(301, '301'), OptionChoice(501, '501'), OptionChoice(701, '701')], 501),
      OptionDef.choice('doubleOut', 'Check-Out',
          [OptionChoice(true, 'Double Out'), OptionChoice(false, 'Single Out')], true),
      OptionDef.choice('format', 'Modus',
          [OptionChoice('legs', 'Legs'), OptionChoice('sets', 'Sets')], 'legs'),
      OptionDef.number('sets', 'First to … Sets', 3, min: 1, max: 7),
      OptionDef.number('legs', 'First to … Legs', 3, min: 1, max: 9),
    ],
    create: (p, c, s, seed) => X01Game(p, c, startIndex: s, seed: seed),
  ),
  ModeDef(
    id: 'atc',
    name: 'Around the Clock',
    category: ModeCategory.training,
    short: '1 bis 20 und Bull der Reihe nach treffen',
    rules: 'Triff die Zahlen 1–20 nacheinander und zum Schluss das Bull. Wer zuerst rum ist, gewinnt. '
        'Klassisch: Double springt 2, Triple 3 Felder weiter.',
    options: const [
      OptionDef.choice(
          'variant',
          'Variante',
          [
            OptionChoice('classic', 'Klassisch'),
            OptionChoice('single', 'Ohne Sprünge'),
            OptionChoice('doubles', 'Doubles'),
            OptionChoice('triples', 'Triples'),
          ],
          'classic'),
    ],
    create: (p, c, s, seed) => AroundTheClockGame(p, c, startIndex: s, seed: seed),
    metricLabel: 'Wenigste Darts',
    lowerIsBetter: true,
  ),
  ModeDef(
    id: 'bobs27',
    name: "Bob's 27",
    category: ModeCategory.training,
    short: 'Doubles-Training von D1 bis Bull',
    rules: 'Start mit 27 Punkten. Pro Runde 3 Darts auf D1, D2 … D20 und Bull. Jeder Treffer gibt den '
        'Wert des Doubles, ohne Treffer wird er abgezogen. Klassisch bist du bei 0 oder weniger raus; '
        'mit „Minuspunkte“ spielen alle bis zum Bull weiter.',
    options: const [
      OptionDef.choice('negative', 'Regel',
          [OptionChoice(false, 'Klassisch'), OptionChoice(true, 'Minuspunkte')], false),
    ],
    create: (p, c, s, seed) => Bobs27Game(p, c, startIndex: s, seed: seed),
    metricLabel: 'Höchste Punktzahl',
  ),
  ModeDef(
    id: 'checkout',
    name: 'Checkout-Training',
    category: ModeCategory.training,
    short: 'Zufällige Finishes mit 9 Darts',
    rules: 'Jede Runde gibt es eine Zufallszahl – für alle Spieler dieselbe. Du hast 9 Darts '
        '(3 Aufnahmen), um mit Double Out auszuchecken. Geworfen wird abwechselnd mit je 3 Darts. '
        'Wer fertig ist, setzt aus, bis alle durch sind – oder ihr überspringt den Rest der Runde. '
        'Mit „Bis zum Finish“ wirfst du so lange, bis du gecheckt hast; als Treffer zählt es nur innerhalb von 9 Darts.',
    options: const [
      OptionDef.choice(
          'range',
          'Bereich',
          [
            OptionChoice('41-100', '41–100'),
            OptionChoice('61-120', '61–120'),
            OptionChoice('101-170', '101–170'),
            OptionChoice('41-170', '41–170'),
          ],
          '41-170'),
      OptionDef.choice('rounds', 'Runden', _rounds, 10),
      _untilFinish,
    ],
    create: (p, c, s, seed) =>
        CheckoutChallengeGame(p, c, startIndex: s, seed: seed, kind: 'training'),
    metricLabel: 'Meiste Checks',
  ),
  ModeDef(
    id: '121',
    name: '121',
    category: ModeCategory.training,
    short: 'Finish unter Druck – geschafft heißt +1',
    rules: 'Checke 121 mit 9 Darts aus. Klappt es, geht es mit 122 weiter, sonst zurück auf 121. '
        'Geworfen wird abwechselnd mit je 3 Darts, jeder hat sein eigenes Ziel.',
    options: const [
      OptionDef.choice('rounds', 'Runden', _rounds, 10),
    ],
    create: (p, c, s, seed) => CheckoutChallengeGame(p, c, startIndex: s, seed: seed, kind: '121'),
    metricLabel: 'Höchstes Ziel geschafft',
  ),
  ModeDef(
    id: 'scoring',
    name: 'Scoring',
    category: ModeCategory.training,
    short: 'Beliebig viele Darts auf die Triple-20',
    rules: 'Wirf die gewählte Anzahl Darts auf dein Ziel. Am Ende zählen Punkte, Average und '
        'Triple-Quote.',
    options: const [
      OptionDef.number('darts', 'Anzahl Darts', 99,
          min: 3, max: 9999, step: 3, presets: [30, 60, 99, 150, 300, 501]),
      OptionDef.choice('target', 'Ziel',
          [OptionChoice(20, 'T20'), OptionChoice(19, 'T19'), OptionChoice(0, 'Frei')], 20),
    ],
    create: (p, c, s, seed) => ScoringGame(p, c, startIndex: s, seed: seed),
    metricLabel: 'Bester Average',
  ),
  ModeDef(
    id: 'halveit',
    name: 'Halve It',
    category: ModeCategory.training,
    short: '15 · 16 · D · 17 · 18 · T · 19 · 20 · Bull',
    rules: 'Neun Runden mit festen Zielen. Treffer zählen mit vollem Wert. Wer in einer Runde gar '
        'nichts trifft, halbiert seinen Punktestand. Gestartet wird mit 0, 40 oder 100 Punkten.',
    options: const [
      OptionDef.choice('startPoints', 'Startpunkte',
          [OptionChoice(0, '0'), OptionChoice(40, '40'), OptionChoice(100, '100')], 40),
    ],
    create: (p, c, s, seed) => HalveItGame(p, c, startIndex: s, seed: seed),
    metricLabel: 'Höchste Punktzahl',
  ),
  ModeDef(
    id: 'cricket',
    name: 'Cricket',
    category: ModeCategory.mini,
    short: '15–20 und Bull schließen, dann punkten',
    rules: 'Jede Zahl 15–20 und Bull dreimal treffen, um sie zu schließen (Double = 2, Triple = 3). '
        'Weitere Treffer auf geschlossene Zahlen bringen Punkte, solange ein Gegner sie noch offen hat. '
        'Gewonnen hat, wer alles geschlossen hat und mindestens gleich viele Punkte hat. '
        'Bei „Offen“ gibt es keine Rundengrenze – gespielt wird, bis einer fertig ist.',
    options: const [
      OptionDef.choice(
          'rounds',
          'Max. Runden',
          [OptionChoice(15, '15'), OptionChoice(20, '20'), OptionChoice(30, '30'), OptionChoice(0, 'Offen')],
          20),
    ],
    create: (p, c, s, seed) => CricketGame(p, c, startIndex: s, seed: seed),
  ),
  ModeDef(
    id: 'killer',
    name: 'Killer',
    category: ModeCategory.mini,
    short: 'Werde Killer und schalte die anderen aus',
    rules: 'Jeder bekommt eine eigene Zahl. Triff dein eigenes Double, um Killer zu werden. Danach '
        'kostet jeder Treffer auf das Double eines Gegners ihn ein Leben. Achtung: Das eigene Double '
        'kostet dich als Killer selbst ein Leben. Der Letzte gewinnt. '
        'Statt Double kann auch Single (jeder Treffer auf die Zahl: S = 1, D = 2, T = 3 Leben) '
        'oder Triple gewählt werden.',
    options: const [
      OptionDef.choice('lives', 'Leben',
          [OptionChoice(3, '3'), OptionChoice(5, '5')], 3),
      OptionDef.choice('field', 'Zielfeld',
          [OptionChoice('double', 'Double'), OptionChoice('single', 'Single'), OptionChoice('triple', 'Triple')],
          'double'),
    ],
    minPlayers: 2,
    create: (p, c, s, seed) => KillerGame(p, c, startIndex: s, seed: seed),
  ),
  ModeDef(
    id: 'shanghai',
    name: 'Shanghai',
    category: ModeCategory.mini,
    short: 'Runde für Runde auf 1, 2, 3 …',
    rules: 'In Runde 1 zählt nur die 1, in Runde 2 nur die 2 usw. Single, Double und Triple der '
        'Zielzahl in einer Aufnahme ist ein Shanghai – Sofortsieg!',
    options: const [
      OptionDef.choice(
          'rounds', 'Runden', [OptionChoice(7, '7'), OptionChoice(10, '10'), OptionChoice(20, '20')], 7),
    ],
    create: (p, c, s, seed) => ShanghaiGame(p, c, startIndex: s, seed: seed),
    metricLabel: 'Höchste Punktzahl',
  ),
  ModeDef(
    id: 'highscore',
    name: 'High Score',
    category: ModeCategory.mini,
    short: 'Die meisten Punkte nach X Runden',
    rules: 'Ganz einfach: Wer nach der gewählten Anzahl Runden die meisten Punkte hat, gewinnt.',
    options: const [
      OptionDef.choice('rounds', 'Runden', _rounds, 10),
    ],
    create: (p, c, s, seed) => HighScoreGame(p, c, startIndex: s, seed: seed),
    metricLabel: 'Höchste Punktzahl',
  ),
  ModeDef(
    id: 'catch40',
    name: 'Catch 40',
    category: ModeCategory.mini,
    short: 'Finishes von 61 aufwärts mit 6 Darts',
    rules: 'Ziele 61, 62, 63 … mit je 6 Darts. Check in 2 Darts = 3 Punkte, in 3 Darts = 2 Punkte, '
        'in 4–6 Darts = 1 Punkt. Geworfen wird abwechselnd mit je 3 Darts. Wer fertig ist, setzt aus, '
        'bis alle durch sind – oder ihr überspringt den Rest der Runde. Mit „Bis zum Finish“ wirfst du '
        'weiter, bis du gecheckt hast (ab dem 7. Dart 0 Punkte).',
    options: const [
      OptionDef.choice('rounds', 'Ziele',
          [OptionChoice(10, '10'), OptionChoice(20, '20'), OptionChoice(40, '40')], 10),
      _untilFinish,
    ],
    create: (p, c, s, seed) =>
        CheckoutChallengeGame(p, c, startIndex: s, seed: seed, kind: 'catch40'),
    metricLabel: 'Höchste Punktzahl',
  ),
];

ModeDef modeById(String id) => modes.firstWhere((m) => m.id == id);

GameEngine buildEngine(GameConfig config, List<GamePlayer> players, int startIndex, int seed) {
  final e = modeById(config.modeId).create(players, config, startIndex, seed);
  e.begin();
  return e;
}

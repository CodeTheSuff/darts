// Inhalt des großen Tutorials.
//
// WICHTIG: Bei jeder neuen oder geänderten Funktion der App hier (und im kurzen
// Rundgang in home_screen.dart) mit anpassen, damit beide Einführungen aktuell bleiben.
// Trainings- und Minispiel-Kapitel lesen Namen und Regeln direkt aus dem Katalog.
import 'package:material_ui/material_ui.dart';

import '../../data/analytics.dart';
import '../../data/callouts.dart';
import '../../data/match_controller.dart';
import '../../data/match_report.dart';
import '../../games/catalog.dart';
import '../../games/engine.dart';
import '../../games/tournament.dart';
import '../../models/dart.dart';
import '../../models/player.dart';
import '../dartboard.dart';
import '../hit_boards.dart';
import '../home_screen.dart' show modeIcon;
import '../link_screen.dart';
import '../logo.dart';
import '../match_share.dart';
import '../settings_screen.dart';
import '../setup_screen.dart';
import '../stats_screen.dart';
import '../stats_table.dart';
import '../theme.dart';
import '../tournament_screens.dart';
import 'tutorial_widgets.dart';

/// Eine Seite: App-Ausschnitt oben, Titel und Text darunter.
class TutPage {
  const TutPage(this.title, this.text, this.visual);
  final String title;
  final String text;
  final Widget Function(BuildContext context) visual;
}

/// Ein Kapitel mit Seiten und optional „Jetzt ausprobieren“.
class TutChapter {
  const TutChapter({
    required this.id,
    required this.title,
    required this.icon,
    required this.summary,
    required this.pages,
    this.tryLabel,
    this.tryIt,
  });
  final String id;
  final String title;
  final IconData icon;
  final String summary;
  final List<TutPage> pages;
  final String? tryLabel;
  final Widget Function()? tryIt;
}

// ---------------------------------------------------------------- Beispieldaten

const _simon = GamePlayer('t-a', 'Simon', 0xFF5AA9FF);
const _max = GamePlayer('t-b', 'Max', 0xFFF5C84C);
Color get _cA => const Color(0xFF5AA9FF);
Color get _cB => const Color(0xFFF5C84C);

/// Ein kurzes 301-Match: Simon checkt 40 nach 7 Darts.
MatchController _sampleMatch() {
  final c = MatchController(
    config: const GameConfig('x01', {'start': 301, 'doubleOut': true, 'legs': 1}),
    players: const [_simon, _max],
  );
  for (final d in const [
    Dart(20, 3), Dart(19, 1), Dart(5, 1), //
    Dart(1, 1), Dart(20, 1), Dart(0, 1),
    Dart(20, 3), Dart(20, 3), Dart(19, 3),
    Dart(20, 1), Dart(20, 1), Dart(0, 1),
    Dart(20, 2),
  ]) {
    c.throwDart(d);
  }
  return c;
}

MatchReport _sampleReport(MatchController c) => MatchReport.build(
    config: c.config, players: c.players, startIndex: c.startIndex, seed: c.seed, darts: c.darts)!;

Tournament _sampleTournament() {
  final t = Tournament(
    id: 'tut',
    name: 'Darts-Abend',
    created: DateTime(2026, 11, 20),
    system: TSystem.ko,
    players: [for (final n in ['Simon', 'Max', 'Lena', 'Tom', 'Jana', 'Paul', 'Andi', 'Matze']) TPlayer(n, n)],
    start: 501,
    doubleOut: true,
    formats: const {},
  )..build();
  for (var i = 0; i < 5; i++) {
    t.record(t.playable.first.id, winnerSide: i % 3 == 0 ? 1 : 0, legs: i.isEven ? [3, 1] : [2, 3], points: [400, 350], darts: [18, 18]);
  }
  return t;
}

Widget _text(String s, {double size = 14, Color? color, FontWeight w = FontWeight.w700}) =>
    Text(s, style: TextStyle(fontSize: size, color: color ?? C.text, fontWeight: w));

// ---------------------------------------------------------------- Ausschnitte

Widget _home(String spot) => TutFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const DartsLogo(size: 30),
            const SizedBox(width: 8),
            _text('Darts', size: 20, w: FontWeight.w800),
            const Expanded(child: SizedBox()),
            Spot(on: spot == 'link', radius: 99, child: Icon(Icons.wifi_tethering_rounded, color: C.text)),
            const SizedBox(width: 12),
            Spot(on: spot == 'stats', radius: 99, child: Icon(Icons.insights_rounded, color: C.text)),
            const SizedBox(width: 12),
            Spot(on: spot == 'settings', radius: 99, child: Icon(Icons.settings_rounded, color: C.text)),
          ]),
          const SizedBox(height: 12),
          MockCard(
            spot: spot == 'x01',
            tint: C.accent,
            child: Row(children: [
              Icon(Icons.adjust_rounded, color: C.accent, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _text('X01', size: 18, w: FontWeight.w800),
                  Text('301 · 501 · 701 – das klassische Match', style: TextStyle(color: C.muted, fontSize: 12)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          MockCard(
            spot: spot == 'tour',
            tint: C.gold,
            child: Row(children: [
              Icon(Icons.emoji_events_rounded, color: C.gold, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _text('Turnier', size: 18, w: FontWeight.w800),
                  Text('K.o., Doppel-K.o., Gruppen oder Liga', style: TextStyle(color: C.muted, fontSize: 12)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          MockCard(
            spot: spot == 'resume',
            tint: C.dbl,
            child: Row(children: [
              Icon(Icons.play_arrow_rounded, color: C.dbl, size: 30),
              const SizedBox(width: 10),
              Expanded(child: _text('Match fortsetzen', size: 15)),
            ]),
          ),
          const SizedBox(height: 16),
          Spot(
            on: spot == 'tabs',
            child: Container(
              height: 56,
              decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                for (final (i, x) in [
                  (Icons.adjust_rounded, 'Spiel'),
                  (Icons.fitness_center_rounded, 'Training'),
                  (Icons.celebration_rounded, 'Minispiele'),
                ].indexed)
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(x.$1, color: i == 0 ? C.accent : C.muted),
                      Text(x.$2, style: TextStyle(fontSize: 11, color: i == 0 ? C.accent : C.muted)),
                    ]),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );

Widget _setup(String spot) => TutFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _text('X01', size: 18, w: FontWeight.w800),
          const SizedBox(height: 8),
          Text('MATCH', style: TextStyle(color: C.muted, fontSize: 11, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Spot(
            on: spot == 'options',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 6, children: [const MockChip('301'), const MockChip('501', on: true), const MockChip('701')]),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [const MockChip('Double Out', on: true), const MockChip('Single Out')]),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [const MockChip('Legs', on: true), const MockChip('Sets'), const MockChip('First to 3')]),
            ]),
          ),
          const SizedBox(height: 12),
          Text('SPIELER  2 / 8', style: TextStyle(color: C.muted, fontSize: 11, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final (n, c) in [('Simon', _cA), ('Max', _cB)])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: MockCard(
                spot: spot == 'players' && n == 'Max',
                child: Row(children: [
                  CircleAvatar(radius: 8, backgroundColor: c),
                  const SizedBox(width: 8),
                  Expanded(child: _text(n, size: 15)),
                  Spot(
                    on: spot == 'colors' && n == 'Simon',
                    radius: 99,
                    child: Row(children: [
                      for (final col in [_cA, _cB, const Color(0xFFB48CFF), const Color(0xFFFF6FA8)])
                        Padding(
                          padding: const EdgeInsets.all(2),
                          child: CircleAvatar(radius: 7, backgroundColor: col),
                        ),
                    ]),
                  ),
                ]),
              ),
            ),
          Row(children: [
            Expanded(child: Spot(on: spot == 'add', child: MockCard(child: Center(child: _text('+ Spieler hinzufügen', size: 13))))),
            const SizedBox(width: 6),
            Spot(on: spot == 'bot', child: MockCard(child: _text('+ Bot', size: 13))),
          ]),
          const SizedBox(height: 8),
          Spot(
            on: spot == 'saved',
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final n in ['Lena', 'Tom', 'Jana', 'Paul']) MockChip(n),
            ]),
          ),
          const SizedBox(height: 16),
          Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: C.accentGradient, borderRadius: BorderRadius.circular(14)),
            child: Text('Match starten', style: TextStyle(color: C.onAccent, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

Widget _keypad(String spot, {List<String>? checkout}) {
  final m = spot == 'double' ? 2 : spot == 'triple' ? 3 : 1;
  final tone = m == 2 ? C.dbl : m == 3 ? C.trp : null;
  final pre = m == 2 ? 'D' : m == 3 ? 'T' : null;
  Color seg(String s) => s == 'Bull' || s.startsWith('D') ? C.dbl : s.startsWith('T') ? C.trp : C.text;
  Widget side(MockKey k) => Row(children: [k]);
  return TutFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MockPlayer('Simon', '121', _cA, active: true, sub: 'Ø 60,0 · Letzte 60', spot: spot == 'score'),
        const SizedBox(height: 6),
        Row(children: [
          MockKey('T20', spot: spot == 'turn', height: 32),
          MockKey('–', spot: spot == 'turn', height: 32),
          MockKey('–', spot: spot == 'turn', height: 32),
        ]),
        Spot(
          on: spot == 'checkout',
          radius: 10,
          child: Container(
            height: 32,
            margin: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: C.line),
            ),
            child: checkout == null
                ? Center(
                    child: Text('Noch kein Finish möglich',
                        style: TextStyle(color: C.muted, fontSize: 12, fontWeight: FontWeight.w700)))
                : Row(children: [
                    for (var i = 0; i < checkout.length; i++) ...[
                      if (i > 0) Container(width: 1, height: 18, color: C.line),
                      Expanded(
                        child: Center(
                          child: Text(checkout[i],
                              style: TextStyle(color: seg(checkout[i]), fontSize: 14, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ]),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Column(children: [
                for (var r = 0; r < 5; r++)
                  Row(children: [
                    for (var c = 1; c <= 4; c++)
                      MockKey(
                        '${r * 4 + c}',
                        prefix: pre,
                        tone: tone,
                        spot: spot == 'numbers' && r * 4 + c == 20,
                        height: 30,
                      ),
                  ]),
              ]),
            ),
            Expanded(
              child: Column(children: [
                side(MockKey('‹', light: true, height: 65, fontSize: 34, spot: spot == 'undo')),
                side(MockKey('0', tone: C.miss, height: 30, dim: m > 1, spot: spot == 'undo')),
                side(MockKey('25', tone: C.dbl, height: 30, dim: m > 1, spot: spot == 'bull')),
                side(MockKey('50', tone: C.trp, height: 30, dim: m > 1, spot: spot == 'bull')),
              ]),
            ),
          ],
        ),
        Row(children: [
          MockKey('Double', tone: C.dbl, spot: spot == 'double', filled: spot == 'double', height: 34),
          MockKey('Triple', tone: C.trp, spot: spot == 'triple', filled: spot == 'triple', height: 34),
        ]),
      ],
    ),
  );
}

Widget _bullOff() => TutFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _text('Ausbullen', size: 20, w: FontWeight.w800),
          Text('Tippe die Spieler nach Nähe zum Bull an – jetzt Platz 2.', style: TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 10),
          MockCard(tint: _cB, child: Row(children: [_text('1.', color: _cB), const SizedBox(width: 8), _text('Max')])),
          const SizedBox(height: 6),
          MockCard(spot: true, child: Row(children: [CircleAvatar(radius: 7, backgroundColor: _cA), const SizedBox(width: 8), _text('Simon als Nächster')])),
          const SizedBox(height: 6),
          MockCard(child: Row(children: [const CircleAvatar(radius: 7, backgroundColor: Color(0xFFB48CFF)), const SizedBox(width: 8), _text('Lena als Nächste')])),
          const SizedBox(height: 16),
          Center(child: Text('Auslosen', style: TextStyle(color: C.accent, fontWeight: FontWeight.w800))),
        ],
      ),
    );

Widget _statsTable() {
  final c = _sampleMatch();
  final r = _sampleReport(c);
  return TutFrame(
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(child: Text('LEG 1 BEENDET', style: TextStyle(color: _cA, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2))),
      Center(child: _text('Simon checkt 40 mit 7 Darts', size: 16, w: FontWeight.w800)),
      const SizedBox(height: 8),
      StatsTable(players: c.players, rows: legRows(r.legs.first)),
    ]),
  );
}

Widget _hitBoards() {
  final c = _sampleMatch();
  return TutFrame(
    width: 520,
    child: HitBoards(players: c.players, hits: c.engine.hits),
  );
}

Widget _share(int? player) {
  final c = _sampleMatch();
  return TutFrame(
    width: 360,
    height: 640,
    child: MatchShareCard(engine: c.engine, rows: matchRows(_sampleReport(c)), date: DateTime(2026, 11, 20), player: player),
  );
}

Widget _modeCard(ModeDef m) => TutFrame(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MockCard(
          tint: C.accent,
          child: Row(children: [
            Icon(modeIcon(m.id), color: C.accent, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _text(m.name, size: 20, w: FontWeight.w800),
                Text(m.short, style: TextStyle(color: C.muted, fontSize: 12)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        if (m.options.isNotEmpty) ...[
          Text('EINSTELLBAR', style: TextStyle(color: C.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final o in m.options) MockChip(o.label)]),
          const SizedBox(height: 10),
        ],
        if (m.metricLabel != null)
          MockHint('BESTLEISTUNG', m.metricLabel!, tone: C.gold),
        const SizedBox(height: 16),
        Center(child: Dartboard(size: 120, color: C.accent)),
      ]),
    );

Widget _tournamentSystems(String spot) => TutFrame(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final s in TSystem.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: MockCard(
              spot: spot == s.name,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _text(s.label, size: 15, w: FontWeight.w800),
                Text(s.description, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 11)),
              ]),
            ),
          ),
      ]),
    );

Widget _bracket() => TutFrame(width: 520, height: 360, child: BracketView(t: _sampleTournament(), onTap: (_) {}, fill: true));

Widget _matchList() => TutFrame(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: _text('Darts-Abend', size: 18, w: FontWeight.w800)),
          const MockChip('Scheibe 2', on: true, spot: true),
        ]),
        const SizedBox(height: 8),
        Text('JETZT SPIELBAR', style: TextStyle(color: C.muted, fontSize: 11, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        MockCard(
          tint: C.accent,
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_text('Lena'), _text('Paul')])),
            Icon(Icons.sports_score_rounded, color: C.accent),
          ]),
        ),
        const SizedBox(height: 6),
        MockCard(
          spot: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _text('Max'),
            _text('Tom'),
            Row(children: [
              Icon(Icons.radio_button_checked_rounded, size: 14, color: C.dbl),
              const SizedBox(width: 6),
              Text('Läuft auf Scheibe 1', style: TextStyle(color: C.dbl, fontSize: 12, fontWeight: FontWeight.w800)),
            ]),
          ]),
        ),
      ]),
    );

Widget _link(String spot) => TutFrame(
      width: 440,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _text('Handys koppeln', size: 18, w: FontWeight.w800),
        const SizedBox(height: 10),
        MockCard(
          spot: spot == 'host',
          tint: C.accent,
          child: Row(children: [
            Icon(Icons.wifi_tethering_rounded, color: C.accent),
            const SizedBox(width: 8),
            Expanded(child: _text('Raum öffnen')),
            Text('Code 4711', style: TextStyle(color: C.muted, fontWeight: FontWeight.w800)),
          ]),
        ),
        const SizedBox(height: 10),
        Text('RÄUME IN DER NÄHE', style: TextStyle(color: C.muted, fontSize: 11, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        MockCard(
          spot: spot == 'join',
          child: Row(children: [
            Icon(Icons.phone_android_rounded, color: C.text),
            const SizedBox(width: 8),
            Expanded(child: _text('Simons S24')),
            Spot(on: spot == 'viewer', radius: 99, child: const MockChip('Als Anzeige')),
            const SizedBox(width: 6),
            const MockChip('Mitspielen', on: true),
          ]),
        ),
        const SizedBox(height: 10),
        MockSetting(Icons.sync_rounded, 'Automatisch abgleichen', 'Spieler und Statistiken zwischen den Handys', toggle: true, spot: spot == 'sync'),
      ]),
    );

Widget _online(String spot) => TutFrame(
      width: 440,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _text('Geräte koppeln', size: 18, w: FontWeight.w800),
        const SizedBox(height: 10),
        Spot(
          on: spot == 'mode',
          child: Row(children: [
            const Expanded(child: MockChip('Online', on: true)),
            const SizedBox(width: 6),
            const Expanded(child: MockChip('Im WLAN')),
          ]),
        ),
        const SizedBox(height: 10),
        MockCard(
          spot: spot == 'host',
          tint: C.dbl,
          child: Column(children: [
            Text('ONLINE-RAUM', style: TextStyle(color: C.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
            const SizedBox(height: 4),
            Text('K7M 2QX',
                style: TextStyle(fontFamily: numFont, fontSize: 40, fontWeight: FontWeight.w800, color: C.text, letterSpacing: 4)),
            const SizedBox(height: 4),
            const MockChip('Code teilen'),
          ]),
        ),
        const SizedBox(height: 10),
        Text('RAUM BEITRETEN', style: TextStyle(color: C.muted, fontSize: 11, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        MockCard(
          spot: spot == 'join',
          child: Row(children: [
            Expanded(child: _text('K7M 2QX', size: 16)),
            const MockChip('Mitspielen', on: true),
            const SizedBox(width: 6),
            const MockChip('Nur anzeigen'),
          ]),
        ),
        const SizedBox(height: 10),
        MockSetting(Icons.tune_rounded, 'Erweitert', 'Server-Adresse · Verbindung testen · Nach Updates suchen',
            spot: spot == 'server'),
      ]),
    );

Widget _web(String spot) => TutFrame(
      width: 440,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MockCard(
          spot: spot == 'browser',
          child: Row(children: [
            Icon(Icons.public_rounded, color: C.accent),
            const SizedBox(width: 8),
            Expanded(child: _text('https://darts.…', size: 13)),
            Icon(Icons.ios_share_rounded, color: spot == 'home' ? C.accent : C.muted, size: 20),
          ]),
        ),
        const SizedBox(height: 10),
        MockCard(
          spot: spot == 'home',
          tint: C.accent,
          child: Row(children: [
            Icon(Icons.add_to_home_screen_rounded, color: C.accent),
            const SizedBox(width: 8),
            Expanded(child: _text('Zum Home-Bildschirm hinzufügen', size: 13)),
          ]),
        ),
        const SizedBox(height: 10),
        MockSetting(Icons.volume_up_rounded, 'Ton', 'Nach dem ersten Tippen – Lautlos-Schalter beachten', toggle: true,
            spot: spot == 'sound'),
        const SizedBox(height: 6),
        MockSetting(Icons.save_alt_rounded, 'Backup exportieren', 'Zuletzt gesichert: heute', spot: spot == 'backup'),
        const SizedBox(height: 6),
        MockSetting(Icons.system_update_rounded, 'Neue Version 3.0.1', 'Herunterladen bzw. neu laden', spot: spot == 'update'),
      ]),
    );

Widget _display() => TutFrame(
      width: 760,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const MockChip('Alle', on: true, spot: true),
          const SizedBox(width: 6),
          const MockChip('Scheibe 1'),
          const SizedBox(width: 6),
          const MockChip('Scheibe 2'),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 210,
          child: Row(children: [
            for (final (b, a, sa, bName, sb) in [(1, 'Simon', '301', 'Max', '422'), (2, 'Lena', '475', 'Tom', '451')]) ...[
              if (b == 2) const SizedBox(width: 10),
              Expanded(
                child: MockCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('SCHEIBE $b', style: TextStyle(color: C.accent, fontSize: 11, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    MockPlayer(a, sa, _cA, active: b == 1),
                    const SizedBox(height: 6),
                    MockPlayer(bName, sb, _cB, active: b == 2),
                  ]),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );

Widget _callouts() => TutFrame(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Icon(Icons.record_voice_over_rounded, size: 56, color: C.accent)),
        const SizedBox(height: 10),
        Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
          MockChip('${Callouts.minScore}–${Callouts.maxScore}', on: true),
          const MockChip('Bullseye', on: true),
          const MockChip('„1“', on: true),
          const MockChip('You win', on: true),
        ]),
        const SizedBox(height: 14),
        const MockSetting(Icons.record_voice_over_rounded, 'Ansagen (Sounds)', 'Bei verbundener Anzeige spielt nur die Anzeige', toggle: true),
        const MockSetting(Icons.celebration_rounded, 'Jubel-Animationen', '180, Ton+, Leg- und Match-Gewinn', toggle: true),
      ]),
    );

Widget _statsScreen(String spot) => TutFrame(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _text('Statistik', size: 18, w: FontWeight.w800),
        const SizedBox(height: 8),
        Spot(
          on: spot == 'period',
          child: Wrap(spacing: 6, children: [
            for (final (i, p) in Period.values.indexed) MockChip(p.label, on: i == 0),
          ]),
        ),
        const SizedBox(height: 10),
        for (final (id, icon, title, sub) in [
          ('players', Icons.person_rounded, 'Spieler', 'Average, Verlauf, Bestwerte je Spieler'),
          ('compare', Icons.compare_arrows_rounded, 'Direktvergleich', 'Zwei Spieler gegeneinander'),
          ('doubles', Icons.track_changes_rounded, 'Doppel-Analyse', 'Welche Doubles wie oft getroffen'),
          ('awards', Icons.military_tech_rounded, 'Erfolge', 'Abzeichen für besondere Leistungen'),
          ('history', Icons.history_rounded, 'Match-Historie', 'Alle Spiele mit Ergebnis'),
        ])
          MockSetting(icon, title, sub, spot: spot == id),
      ]),
    );

Widget _settings(List<(IconData, String, String, bool?)> rows, {String? spot}) => TutFrame(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final r in rows) MockSetting(r.$1, r.$2, r.$3, toggle: r.$4, spot: spot == r.$2),
      ]),
    );

Widget _palettes() => TutFrame(
      height: 300,
      child: GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final p in palettes)
            Container(
              decoration: BoxDecoration(
                color: p.bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.accent.withValues(alpha: 0.6)),
              ),
              padding: const EdgeInsets.all(8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  CircleAvatar(radius: 6, backgroundColor: p.accent),
                  const SizedBox(width: 4),
                  CircleAvatar(radius: 6, backgroundColor: p.dbl),
                  const SizedBox(width: 4),
                  CircleAvatar(radius: 6, backgroundColor: p.trp),
                ]),
                const SizedBox(height: 16),
                Text(p.name, style: TextStyle(color: p.text, fontWeight: FontWeight.w800)),
              ]),
            ),
          Container(
            decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
            alignment: Alignment.center,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.brightness_auto_rounded, color: C.accent),
              _text('Automatisch', size: 12),
            ]),
          ),
        ],
      ),
    );

// ---------------------------------------------------------------- Kapitel

List<TutChapter> buildTutorial() {
  final training = modes.where((m) => m.category == ModeCategory.training).toList();
  final mini = modes.where((m) => m.category == ModeCategory.mini).toList();
  return [
    TutChapter(
      id: 'start',
      title: 'Erste Schritte',
      icon: Icons.rocket_launch_rounded,
      summary: 'Startseite, Spieler anlegen, Farben',
      pages: [
        TutPage('Die Startseite',
            'Oben findest du Koppeln, Statistik und Einstellungen. Darunter startest du X01 oder ein Turnier.',
            (_) => _home('x01')),
        TutPage('Drei Bereiche',
            'Unten wechselst du zwischen „Spiel“ (X01 und Turnier), „Training“ und „Minispiele“.',
            (_) => _home('tabs')),
        TutPage('Unterbrochenes Match',
            'Verlässt du ein laufendes Spiel, merkt sich die App den Stand. Mit „Match fortsetzen“ geht es genau dort weiter.',
            (_) => _home('resume')),
        TutPage('Spieler anlegen',
            'Gib einen Namen ein und tippe „Spieler hinzufügen“. Bis zu 8 Spieler pro Spiel. Wer schon mal gespielt hat, erscheint unten als gespeicherter Spieler – einfach antippen.',
            (_) => _setup('add')),
        TutPage('Farben',
            'Jeder Spieler hat eine Farbe. Tippst du eine Farbe an, die ein anderer schon hat, tauschen die beiden.',
            (_) => _setup('colors')),
        TutPage('Gespeicherte Spieler',
            'Alle Spieler mit ihren Statistiken bleiben gespeichert. Antippen fügt sie dem Spiel hinzu.',
            (_) => _setup('saved')),
      ],
      tryLabel: 'X01 öffnen',
      tryIt: () => SetupScreen(mode: modeById('x01')),
    ),
    TutChapter(
      id: 'x01',
      title: 'X01 spielen',
      icon: Icons.adjust_rounded,
      summary: 'Startpunkte, Out-Regel, Legs & Sets, Ausbullen, Bots',
      pages: [
        TutPage('Match einstellen',
            'Ganz oben wählst du 301, 501 oder 701, Double Out oder Single Out und wie viele Legs (oder Sets) zum Sieg nötig sind. In allen Modi stehen die Regeln oben, darunter die Spieler.',
            (_) => _setup('options')),
        TutPage('Gegen einen Bot',
            'Spielst du allein, kannst du einen Bot hinzufügen – vom Anfänger bis zum Profi oder mit eigenem Average. Das Tempo stellst du in den Einstellungen ein.',
            (_) => _setup('bot')),
        TutPage('Ausbullen',
            'Bei mehreren Spielern wird zuerst ausgebullt: Tippe die Spieler in der Reihenfolge an, wie nah sie am Bull sind. So steht die ganze Wurfreihenfolge fest. Oder lass die App auslosen.',
            (_) => _bullOff()),
        TutPage('Weiterspielen um Plätze',
            'Bei drei oder mehr Spielern fragt die App nach dem Sieger, ob die anderen um Platz 2, 3 … weiterspielen wollen.',
            (_) => const TutFrame(
                child: MockDialog('Andi gewinnt!',
                    'Weiterspielen um Platz 2? Die übrigen Spieler spielen das Leg mit ihren Restpunkten zu Ende.',
                    ['Beenden', 'Weiterspielen'], icon: Icons.emoji_events_rounded))),
      ],
      tryLabel: 'X01 öffnen',
      tryIt: () => SetupScreen(mode: modeById('x01')),
    ),
    TutChapter(
      id: 'input',
      title: 'Punkte eintragen',
      icon: Icons.dialpad_rounded,
      summary: 'Tastenblock, Double/Triple, Bull, Zurück, Checkout',
      pages: [
        TutPage('Jeder Pfeil einzeln',
            'Tippe für jeden Pfeil das getroffene Feld. Oben siehst du die Restpunkte, rechts daneben deinen Average im laufenden Leg und die letzte Aufnahme, darunter die drei Pfeile der aktuellen Aufnahme. Den Average über das ganze Spiel zeigt die Zusammenfassung am Ende.',
            (_) => _keypad('numbers')),
        TutPage('Double und Triple',
            'Erst „Double“ oder „Triple“ unten antippen, dann die Zahl – die Tasten zeigen dann D bzw. T, 0, 25 und 50 sind solange gesperrt. Nach dem Pfeil springt der Tastenblock automatisch zurück auf Single, nochmal Antippen hebt die Auswahl auf.',
            (_) => _keypad('double')),
        TutPage('Bull',
            'Rechts unten: 25 (grün) für das einfache Bull, 50 (orange) für das Bullseye.',
            (_) => _keypad('bull')),
        TutPage('Daneben und Rückgängig',
            'Die rote 0 für einen Pfeil außerhalb der Punkte. Die Zurück-Taste ‹ oben rechts nimmt den letzten Pfeil zurück – beliebig oft. Trainings mit großen Treffer-Tasten haben stattdessen „Miss“.',
            (_) => _keypad('undo')),
        TutPage('Checkout-Vorschlag',
            'Ist ein Finish möglich, zeigt das Feld unter den Pfeilen den besten Weg – ein Bereich pro Dart: Double grün, Triple orange, Single weiß. Geht es gerade nicht, schlägt die App vor, worauf du dir einen guten Rest stellst.',
            (_) => _keypad('checkout', checkout: const ['T20', 'T11', 'D14'])),
        TutPage('Single Out als Notlösung',
            'Hängt jemand im Double fest, bietet die App an, das Leg mit Single Out zu beenden. Abschaltbar in den Einstellungen.',
            (_) => const TutFrame(
                child: MockDialog('Single Out?', 'Max hängt auf 1 fest. Dieses Leg mit Single Out beenden?',
                    ['Nein', 'Single Out'], icon: Icons.swap_horiz_rounded))),
      ],
      tryLabel: 'X01 öffnen',
      tryIt: () => SetupScreen(mode: modeById('x01')),
    ),
    TutChapter(
      id: 'gamestats',
      title: 'Statistik im Spiel',
      icon: Icons.query_stats_rounded,
      summary: 'Leg-Statistik, Trefferbild, Matchstatistik, Teilen',
      pages: [
        TutPage('Nach jedem Leg',
            'Ist ein Leg vorbei, siehst du Average, First 9, Darts, Finish, Checkout-Quote und mehr – der bessere Wert ist hervorgehoben. „Weiter“ startet das nächste Leg.',
            (_) => _statsTable()),
        TutPage('Trefferbild',
            'Für jeden Spieler eine Dartscheibe: Getroffene Felder sind eingefärbt, die Zahl zeigt, wie oft. Nach jedem Leg, am Ende des Matches und nach Training und Minispielen.',
            (_) => _hitBoards()),
        TutPage('Matchstatistik',
            'Am Ende des Matches: Vergleich aller Spieler, alle Legs im Überblick und das Trefferbild des ganzen Matches. Danach folgt die Ergebnisseite.',
            (_) => _statsTable()),
        TutPage('Ergebnis teilen',
            'Auf der Ergebnisseite oben rechts: ein Bild mit Logo, Ergebnis, Statistik und Trefferbild – für einen Spieler oder alle. Perfekt für WhatsApp.',
            (_) => _share(0)),
      ],
    ),
    TutChapter(
      id: 'training',
      title: 'Training',
      icon: Icons.fitness_center_rounded,
      summary: training.map((m) => m.name).join(', '),
      pages: [
        TutPage('Allein oder zu mehreren',
            'Alle Trainingsmodi gehen allein oder mit mehreren Spielern (dann wird ausgebullt). Am Ende gibt es Statistik und Trefferbild, Bestleistungen landen in der Statistik.',
            (_) => _home('tabs')),
        for (final m in training) TutPage(m.name, m.rules, (_) => _modeCard(m)),
      ],
      tryLabel: 'Training öffnen',
      tryIt: () => SetupScreen(mode: training.first),
    ),
    TutChapter(
      id: 'mini',
      title: 'Minispiele',
      icon: Icons.celebration_rounded,
      summary: mini.map((m) => m.name).join(', '),
      pages: [
        TutPage('Für die Runde mit Freunden',
            'Minispiele bringen Abwechslung. Bei mehreren Spielern wird zuerst ausgebullt, am Ende gibt es eine Statistik passend zum Spiel.',
            (_) => _home('tabs')),
        for (final m in mini) TutPage(m.name, m.rules, (_) => _modeCard(m)),
      ],
      tryLabel: 'Cricket öffnen',
      tryIt: () => SetupScreen(mode: mini.first),
    ),
    TutChapter(
      id: 'tournament',
      title: 'Turnier',
      icon: Icons.emoji_events_rounded,
      summary: 'K.o., Doppel-K.o., Gruppen, Liga – auch auf mehreren Scheiben',
      pages: [
        TutPage('Vier Turniersysteme',
            'Für 3 bis 32 Spieler. Das System wählst du beim Anlegen, dazu Startpunkte, Out-Regel und Legs je Runde.',
            (_) => _tournamentSystems('')),
        TutPage('Anlegen und Setzen',
            'Spieler auswählen, dann nach Average setzen oder zufällig auslosen. Bei Gruppen schlägt die App Gruppenzahl und Aufsteiger vor.',
            (_) => _tournamentSystems('groups')),
        TutPage('Spiele starten',
            'Unter „Jetzt spielbar“ tippst du ein Spiel an, bullst aus und spielst. Das Ergebnis wird automatisch eingetragen.',
            (_) => _matchList()),
        TutPage('Baum und Tabelle',
            'Der Turnierbaum zeigt, wer weiter ist. Bei Liga und Gruppen gibt es die Tabelle. Am Ende kommt das Siegerpodest – auch zum Teilen.',
            (_) => _bracket()),
        TutPage('Mehrere Scheiben',
            'Mit gekoppelten Handys spielt jedes Handy sein eigenes Turnierspiel. Oben steht deine Scheiben-Nummer (antippen zum Ändern). Läuft ein Spiel woanders, ist es gesperrt; das Turnier-Handy kann es bei Bedarf freigeben.',
            (_) => _matchList()),
      ],
      tryLabel: 'Turnier öffnen',
      tryIt: () => const TournamentHubScreen(),
    ),
    TutChapter(
      id: 'link',
      title: 'Koppeln & Anzeige',
      icon: Icons.wifi_tethering_rounded,
      summary: 'Online oder im WLAN, Raum-Code, Tablet als Anzeige, Abgleich',
      pages: [
        TutPage('Online oder im WLAN',
            'Oben wählst du „Online“ oder „Im WLAN“. Online läuft über das Internet – auch von verschiedenen Orten und zusammen mit iPhones im Browser. Im WLAN geht es ohne Internet, alle Geräte müssen im selben Netz sein.',
            (_) => _online('mode')),
        TutPage('Online-Raum öffnen',
            'Ein Gerät öffnet einen Online-Raum und bekommt einen 6-stelligen Code wie „K7M 2QX“. Sag ihn an oder schick ihn mit „Code teilen“. Der Code bleibt gleich, solange der Raum benutzt wird.',
            (_) => _online('host')),
        TutPage('Mit Code beitreten',
            'Auf den anderen Geräten den Code eingeben und „Mitspielen“ oder „Nur anzeigen“ wählen. Ein neues Gerät musst du beim ersten Mal auf dem Raum-Gerät erlauben – danach erkennen sich die Geräte von selbst.',
            (_) => _online('join')),
        TutPage('Server und Updates',
            'Am einfachsten öffnest du auf dem Handy die Seite „/app“ des Servers (z. B. https://darts.…/app) und tippst „App mit diesem Server verbinden“ – dann ist alles eingetragen. Unter „Erweitert“ stehen die Server-Adresse, „Verbindung testen“ und „Nach Updates suchen“. Gibt es eine neue Version, bietet die App den Download direkt an. Hat ein Gerät im Raum eine zu alte App, sagt Darts Bescheid, wo aktualisiert werden muss.',
            (_) => _online('server')),
        TutPage('Raum im WLAN',
            'Ohne Internet: Ein Handy öffnet unter „Im WLAN“ einen Raum. Alle Geräte müssen im selben WLAN sein. Beim ersten Mal bestätigst du ein neues Gerät.',
            (_) => _link('host')),
        TutPage('Im WLAN verbinden',
            'Die anderen Geräte finden den Raum automatisch unter „Räume in der Nähe“. Mit „Mitspielen“ trägt das Gerät mit ein und sieht dasselbe Spiel.',
            (_) => _link('join')),
        TutPage('Tablet als Anzeige',
            'Mit „Als Anzeige“ wird ein Gerät zur Punktetafel an der Wand: großer Spielstand, Jubel, Ansagen, Leg- und Matchstatistik und im Turnier die Turnier-Übersicht.',
            (_) => _link('viewer')),
        TutPage('Mehrere Spiele auf der Anzeige',
            'Laufen mehrere Scheiben, wählst du oben „Alle“ (geteilter Bildschirm) oder eine einzelne Scheibe.',
            (_) => _display()),
        TutPage('Daten abgleichen',
            'Gekoppelte Handys gleichen Spieler und Statistiken automatisch ab – nichts wird doppelt gezählt.',
            (_) => _link('sync')),
        TutPage('Nach einem Absturz',
            'Stürzt die App ab oder wird sie geschlossen, öffnet sie beim nächsten Start (innerhalb von 30 Minuten) den Raum und das laufende Spiel wieder, und die anderen Geräte verbinden sich neu. Online wartet der Raum sogar bis zu 24 Stunden.',
            (_) => _link('host')),
      ],
      tryLabel: 'Koppeln öffnen',
      tryIt: () => const LinkScreen(),
    ),
    TutChapter(
      id: 'web',
      title: 'Im Browser & auf dem iPhone',
      icon: Icons.public_rounded,
      summary: 'Web-App öffnen, Home-Bildschirm, Ton, Backup, Updates',
      pages: [
        TutPage('Darts im Browser',
            'Darts gibt es auch als Web-App – für iPhone, iPad und jeden Browser. Einfach die Adresse des Darts-Servers öffnen. Alles funktioniert wie in der App, und online spielen iPhones und Android-Handys zusammen.',
            (_) => _web('browser')),
        TutPage('Zum Home-Bildschirm',
            'Auf dem iPhone in Safari auf das Teilen-Symbol tippen und „Zum Home-Bildschirm“ wählen. Dann startet Darts wie eine App im Vollbild. Wichtig: Ohne das löscht Safari Spieler und Statistiken, wenn du die Seite ein paar Tage nicht öffnest.',
            (_) => _web('home')),
        TutPage('Ton auf dem iPhone',
            'Ansagen und Töne starten nach dem ersten Tippen. Steht das iPhone auf lautlos, bleibt auch Darts still.',
            (_) => _web('sound')),
        TutPage('Daten sichern',
            'Im Browser liegen die Daten nur in diesem Browser. Sichere sie ab und zu über Einstellungen → „Backup exportieren“ – die App erinnert dich daran.',
            (_) => _web('backup')),
        TutPage('Updates',
            'Die App prüft einmal am Tag, ob es eine neue Version gibt. Auf Android lädst du sie direkt herunter, im Browser reicht „Neu laden“.',
            (_) => _web('update')),
      ],
      tryLabel: 'Koppeln öffnen',
      tryIt: () => const LinkScreen(),
    ),
    TutChapter(
      id: 'sound',
      title: 'Ansagen & Jubel',
      icon: Icons.record_voice_over_rounded,
      summary: 'Ansagen, Animationen, Ton und Vibration',
      pages: [
        TutPage('Ansagen',
            'Nach jeder Aufnahme von ${Callouts.minScore} bis ${Callouts.maxScore} wird die Punktzahl angesagt, auch beim Checkout. Dazu „Bullseye“ bei jedem Bull 50, „1“ wenn im X01-Match oder Turnier alle drei Pfeile in der 1 landen, und „You win“ am Ende.',
            (_) => _callouts()),
        TutPage('Jubel-Animationen',
            'Bei Ton+, 140+, 180, hohen Finishes und Siegen gibt es eine Animation – bei 180 mit Feuerwerk.',
            (_) => _callouts()),
      ],
      tryLabel: 'Einstellungen öffnen',
      tryIt: () => const SettingsScreen(),
    ),
    TutChapter(
      id: 'stats',
      title: 'Statistik & Verlauf',
      icon: Icons.insights_rounded,
      summary: 'Spieler, Zeiträume, Vergleich, Doubles, Erfolge',
      pages: [
        TutPage('Zeitraum',
            'Oben wählst du, welcher Zeitraum zählt: gesamt, 30 Tage, 7 Tage oder heute.',
            (_) => _statsScreen('period')),
        TutPage('Spieler',
            'Für jeden Spieler: Average, Verlauf, Bestwerte und die Ergebnisse aller Modi. Wer zuletzt gespielt hat, steht oben.',
            (_) => _statsScreen('players')),
        TutPage('Direktvergleich',
            'Zwei Spieler gegeneinander: Bilanz, Averages und gemeinsame Spiele.',
            (_) => _statsScreen('compare')),
        TutPage('Doppel-Analyse',
            'Auf welche Doubles du wie oft wirfst und wie oft du triffst.',
            (_) => _statsScreen('doubles')),
        TutPage('Erfolge',
            'Abzeichen für besondere Leistungen, z. B. die erste 180 oder ein hohes Finish.',
            (_) => _statsScreen('awards')),
      ],
      tryLabel: 'Statistik öffnen',
      tryIt: () => const StatsScreen(),
    ),
    TutChapter(
      id: 'settings',
      title: 'Einstellungen',
      icon: Icons.settings_rounded,
      summary: 'Jede Option erklärt',
      pages: [
        TutPage('Ton & Feedback',
            '„Ton“ schaltet alle Geräusche, darunter regelst du die Lautstärke. „Vibration“ gibt ein kurzes Feedback beim Tippen. „Jubel-Animationen“ schaltet die Animationen bei 180, Ton+ und Siegen.',
            (_) => _settings(const [
                  (Icons.volume_up_rounded, 'Ton', 'Soundeffekte bei Würfen und Erfolgen', true),
                  (Icons.vibration_rounded, 'Vibration', 'Kurzes Feedback beim Tippen', true),
                  (Icons.celebration_rounded, 'Jubel-Animationen', '180, Ton+, Leg- und Match-Gewinn', true),
                ])),
        TutPage('Spiel',
            '„Checkout-Hilfe“ zeigt im X01 den Finish-Weg. „Single Out anbieten“ hilft, wenn jemand im Double festhängt. „Ansagen (Sounds)“ schaltet die Ansagen. „Bot-Tempo“ bestimmt, wie schnell Bots werfen.',
            (_) => _settings(const [
                  (Icons.flag_rounded, 'Checkout-Hilfe', 'Finish-Vorschlag im X01 anzeigen', true),
                  (Icons.swap_horiz_rounded, 'Single Out anbieten', 'Wenn jemand im Double festhängt', true),
                  (Icons.record_voice_over_rounded, 'Ansagen (Sounds)', '80–180, Bullseye, „1“ und „You win“', true),
                  (Icons.speed_rounded, 'Bot-Tempo', 'Langsam · Normal · Schnell', null),
                ])),
        TutPage('Design',
            'Wähle ein Farbschema oder „Automatisch“: tagsüber hell, abends ein dunkles Design deiner Wahl. Dazu die Schriftgröße (Normal/Groß).',
            (_) => _palettes()),
        TutPage('Farbschwäche',
            'Der Modus für Farbschwäche nutzt andere Farben und zusätzliche Symbole für Double, Triple und Miss.',
            (_) => _settings(const [
                  (Icons.visibility_rounded, 'Modus für Farbschwäche', 'Andere Farben und Symbole für Double, Triple und Miss', false),
                  (Icons.format_size_rounded, 'Schriftgröße', 'Normal · Groß', null),
                ])),
        TutPage('Daten',
            '„Automatisch abgleichen“ teilt Spieler und Statistiken mit gekoppelten Handys. Außerdem: Raum-Code ändern, Spieler an ein anderes Handy senden, Daten importieren, Backup exportieren, Statistiken zurücksetzen oder alle Spieler löschen.',
            (_) => _settings(const [
                  (Icons.sync_rounded, 'Automatisch abgleichen', 'Mit gekoppelten Handys', true),
                  (Icons.pin_rounded, 'Raum-Code', 'Code zum Koppeln ändern', null),
                  (Icons.group_rounded, 'Spieler teilen', 'Statistiken an ein anderes Handy senden', null),
                  (Icons.ios_share_rounded, 'Backup exportieren', 'Komplette Sicherung als Datei', null),
                  (Icons.file_open_rounded, 'Daten importieren', 'Spielerdaten oder Backup öffnen', null),
                ])),
        TutPage('App',
            'Hier startest du den kurzen Rundgang oder dieses Tutorial erneut, siehst, was neu ist, und findest Version und Lizenzen.',
            (_) => _settings(const [
                  (Icons.menu_book_rounded, 'Tutorial', 'Alle Funktionen ausführlich erklärt', null),
                  (Icons.school_rounded, 'Einführung erneut zeigen', 'Kurzer Rundgang über die Startseite', null),
                  (Icons.new_releases_rounded, 'Was ist neu', 'Neuerungen dieser Version', null),
                  (Icons.info_outline_rounded, 'Über die App', 'Version, Lizenzen', null),
                ], spot: 'Tutorial')),
      ],
      tryLabel: 'Einstellungen öffnen',
      tryIt: () => const SettingsScreen(),
    ),
  ];
}

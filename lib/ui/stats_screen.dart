import 'package:material_ui/material_ui.dart';

import '../data/analytics.dart';
import '../data/storage.dart';
import '../games/bot.dart';
import '../games/catalog.dart';
import '../games/engine.dart';
import '../games/x01.dart';
import '../models/player.dart';
import 'chart.dart';
import 'dartboard.dart';
import 'theme.dart';

String _d(DateTime t) => '${t.day}.${t.month}.${t.year}';

Widget _title(String t) => SectionTitle(t);

Widget _grid(List<(String, String)> items) => GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.0,
      children: [
        for (final (label, value) in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: TextStyle(color: C.muted, fontSize: 12)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w800, fontFamily: numFont, fontFeatures: tabular)),
                ),
              ],
            ),
          ),
      ],
    );

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(16)),
        child: Text(text, style: TextStyle(color: C.muted)),
      );
}

/// Kachel mit Pfeil, die einen Unterbildschirm öffnet.
Widget _navCard(BuildContext context, IconData icon, String title, String sub, Widget page, {Color? tint}) =>
    GlowCard(
      tint: tint,
      strength: 0.06,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)),
      child: Row(
        children: [
          Icon(icon, color: tint ?? C.accent, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text(sub, style: TextStyle(color: C.muted, fontSize: 13)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: C.muted),
        ],
      ),
    );

// =================================================================== Übersicht

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  @override
  Widget build(BuildContext context) {
    final profiles = Store.profiles;
    return Scaffold(
      appBar: AppBar(title: const Text('Statistik')),
      body: profiles.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('Noch keine Spieler. Starte ein Spiel – die Profile werden automatisch angelegt.',
                    textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (profiles.length >= 2)
                  _navCard(context, Icons.compare_arrows_rounded, 'Direktvergleich', 'Zwei Spieler gegeneinander',
                      HeadToHeadScreen(a: profiles[0].id, b: profiles[1].id)),
                const SizedBox(height: 4),
                for (var i = 0; i < profiles.length; i++) _tile(profiles[i], C.players[i % 4]),
              ],
            ),
    );
  }

  Widget _tile(Profile p, Color col) {
    final s = Store.statsFor(p.id);
    final played = s.modes.values.fold(0, (a, m) => a + m.played);
    final ach = Analytics.achievements(p.id).where((a) => a.done).length;
    return GlowCard(
      tint: col,
      strength: 0.06,
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerStatsScreen(profile: p, color: col)));
        if (mounted) setState(() {});
      },
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: col,
            child: Text(p.name.characters.first.toUpperCase(),
                style: const TextStyle(color: C.ink, fontWeight: FontWeight.w800, fontSize: 18)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                Text('$played Spiele · X01-Ø ${fmt1(s.x01.average)} · $ach Erfolge',
                    style: TextStyle(color: C.muted, fontSize: 13)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: C.muted),
        ],
      ),
    );
  }
}

// =================================================================== Spieler

class PlayerStatsScreen extends StatefulWidget {
  const PlayerStatsScreen({super.key, required this.profile, required this.color});
  final Profile profile;
  final Color color;

  @override
  State<PlayerStatsScreen> createState() => _PlayerStatsScreenState();
}

class _PlayerStatsScreenState extends State<PlayerStatsScreen> {
  Period _period = Period.all;
  int _metric = 0; // 0 Average, 1 Checkout, 2 First 9

  Profile get profile => widget.profile;
  Color get color => widget.color;

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: Text('${profile.name} löschen?'),
        content: const Text('Profil und alle Statistiken werden entfernt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: C.danger),
              child: const Text('Löschen')),
        ],
      ),
    );
    if (ok == true) {
      Store.deleteProfile(profile.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Analytics.statsFor(profile.id, _period);
    final x = s.x01;
    final hits = Map.of(x.hits)..remove('Miss');
    final top = hits.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final totalHits = x.hits.values.fold(0, (a, b) => a + b);
    final tl = Analytics.timeline(profile.id, _period);
    final values = [
      for (final p in tl)
        switch (_metric) {
          1 => p.checkout,
          2 => p.first9,
          _ => p.average,
        }
    ];
    final history = Analytics.history(profile.id, p: _period);
    final ach = Analytics.achievements(profile.id);
    final doubles = Analytics.doubles(profile.id, _period).where((d) => d.attempts > 0).toList()
      ..sort((a, b) => b.attempts.compareTo(a.attempts));

    return Scaffold(
      appBar: AppBar(
        title: Text(profile.name),
        actions: [
          IconButton(tooltip: 'Spieler löschen', icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<Period>(
              showSelectedIcon: false,
              segments: [for (final p in Period.values) ButtonSegment(value: p, label: Text(p.label))],
              selected: {_period},
              onSelectionChanged: (v) => setState(() => _period = v.first),
              style: segStyle(),
            ),
          ),
          if (_period != Period.all)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text('Werte aus der Zeit vor dem Update zählen nur zu „Gesamt“.',
                  style: TextStyle(color: C.muted, fontSize: 12)),
            ),
          const SizedBox(height: 8),
          _title('X01'),
          if (x.matches == 0 && x.darts == 0)
            const _Empty('Keine X01-Matches im Zeitraum.')
          else
            _grid([
              ('3-Dart-Ø', fmt1(x.average)),
              ('First 9 Ø', fmt1(x.first9)),
              ('Checkout-Quote', '${fmt1(x.coRate)} %'),
              ('Höchstes Finish', x.highestFinish == 0 ? '–' : '${x.highestFinish}'),
              ('100+', '${x.c100}'),
              ('140+', '${x.c140}'),
              ('180', '${x.c180}'),
              ('Höchste Aufnahme', '${x.highestTurn}'),
              ('Matches', '${x.matchesWon} / ${x.matches}'),
              ('Legs', '${x.legsWon} / ${x.legsPlayed}'),
              ('Bestes Leg', x.bestLeg == 0 ? '–' : '${x.bestLeg} Darts'),
              ('Darts gesamt', '${x.darts}'),
            ]),
          const SizedBox(height: 14),
          _title('Verlauf'),
          GlowCard(
            tint: color,
            strength: 0.05,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Average')),
                      ButtonSegment(value: 1, label: Text('Checkout %')),
                      ButtonSegment(value: 2, label: Text('First 9')),
                    ],
                    selected: {_metric},
                    onSelectionChanged: (v) => setState(() => _metric = v.first),
                    style: segStyle(),
                  ),
                ),
                const SizedBox(height: 12),
                LineChart(
                  values: values,
                  color: color,
                  firstLabel: tl.isEmpty ? null : _d(tl.first.t),
                  lastLabel: tl.isEmpty ? null : _d(tl.last.t),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _navCard(
            context,
            Icons.history_rounded,
            'Match-Historie',
            history.isEmpty ? 'Noch keine Matches im Zeitraum' : '${history.length} Matches · zuletzt ${_d(history.first.date)}',
            HistoryScreen(pid: profile.id, name: profile.name),
          ),
          _navCard(
            context,
            Icons.adjust_rounded,
            'Doppel-Analyse',
            doubles.isEmpty
                ? 'Noch keine Würfe auf ein Double'
                : 'Am häufigsten: ${doubles.take(3).map((d) => '${d.label} ${d.rate.round()} %').join(' · ')}',
            DoublesScreen(pid: profile.id, name: profile.name, color: color),
            tint: C.dbl,
          ),
          _navCard(
            context,
            Icons.military_tech_rounded,
            'Erfolge',
            '${ach.where((a) => a.done).length} von ${ach.length} freigeschaltet',
            AchievementsScreen(pid: profile.id, name: profile.name),
            tint: C.gold,
          ),
          if (hits.isNotEmpty) ...[
            const SizedBox(height: 14),
            _title('Trefferverteilung'),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(18)),
              child: Column(
                children: [
                  Dartboard(size: 300, heat: x.hits, color: color, showCounts: true),
                  const SizedBox(height: 12),
                  for (final e in top.take(6))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          SizedBox(width: 44, child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700))),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: e.value / top.first.value,
                                minHeight: 8,
                                color: color,
                                backgroundColor: C.surface3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 52,
                            child: Text('${(e.value / totalHits * 100).toStringAsFixed(1)} %',
                                textAlign: TextAlign.right, style: TextStyle(color: C.muted, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (s.bots.isNotEmpty) ...[
            const SizedBox(height: 14),
            _title('Gegen Bots'),
            for (final l in BotLevel.values)
              if (s.bots[l.name] != null) _botRow(botNameFor(l), s.bots[l.name]!),
            if (s.bots['custom'] != null) _botRow('Eigene Bots', s.bots['custom']!),
          ],
          if (s.tournaments > 0) ...[
            const SizedBox(height: 14),
            _title('Turniere'),
            _grid([
              ('Gespielt', '${s.tournaments}'),
              ('Turniersiege', '${s.tournamentWins}'),
              ('Podestplätze', '${s.podiums}'),
              ('Siegquote', '${(s.tournamentWins / s.tournaments * 100).round()} %'),
            ]),
          ],
          const SizedBox(height: 14),
          _title('Training & Minispiele'),
          ..._modes(s),
        ],
      ),
    );
  }

  List<Widget> _modes(PlayerStats s) {
    final rows = <Widget>[];
    for (final m in modes.where((m) => m.id != 'x01')) {
      final ms = s.modes[m.id];
      if (ms == null || ms.played == 0) continue;
      rows.add(Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  Text('${ms.played} gespielt · ${ms.wins} Siege', style: TextStyle(color: C.muted, fontSize: 12)),
                ],
              ),
            ),
            if (m.metricLabel != null && ms.best != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(ms.best is double ? fmt1(ms.best!.toDouble()) : '${ms.best}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  Text(m.metricLabel!, style: TextStyle(color: C.muted, fontSize: 11)),
                ],
              ),
          ],
        ),
      ));
    }
    return rows.isEmpty ? [const _Empty('Keine Trainings- oder Minispiele im Zeitraum.')] : rows;
  }

  Widget _botRow(String label, List<int> rec) {
    final total = rec[0] + rec[1];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(Icons.smart_toy_rounded, color: C.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : rec[0] / total,
                    minHeight: 7,
                    color: C.dbl,
                    backgroundColor: C.danger.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Text('${rec[0]} : ${rec[1]}', style: const TextStyle(fontFamily: numFont, fontSize: 22, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

// =================================================================== Historie

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.pid, required this.name});
  final String pid;
  final String name;

  @override
  Widget build(BuildContext context) {
    final list = Analytics.history(pid);
    return Scaffold(
      appBar: AppBar(title: Text('Historie · $name')),
      body: list.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('Noch keine Matches gespeichert. Matches ab Version 2.0 erscheinen hier.',
                    textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [for (final m in list) _row(context, m)],
            ),
    );
  }

  Widget _row(BuildContext context, MatchSummary m) {
    final e = m.engine;
    final res = m.results;
    final others = [for (var i = 0; i < e.n; i++) if (i != m.me) e.players[i].name];
    final mine = res.firstWhere((r) => r.playerIndex == m.me);
    final col = m.won ? C.dbl : (e.n > 1 ? C.danger : C.accent);
    return GlowCard(
      tint: col,
      strength: 0.05,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      margin: const EdgeInsets.only(bottom: 8),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MatchDetailScreen(summary: m))),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 44,
            decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(others.isEmpty ? e.title : 'gegen ${others.join(', ')}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text('${modeById(m.record.mode).name} · ${e.title} · ${_d(m.date)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(mine.value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              if (e is X01Game) Text('Ø ${fmt1(m.myAverage)}', style: TextStyle(color: C.muted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

class MatchDetailScreen extends StatelessWidget {
  const MatchDetailScreen({super.key, required this.summary});
  final MatchSummary summary;

  @override
  Widget build(BuildContext context) {
    final e = summary.engine;
    final res = summary.results;
    final legs = Analytics.legs(summary.record);
    return Scaffold(
      appBar: AppBar(title: Text(_d(summary.date))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text('${modeById(summary.record.mode).name} · ${e.title}', style: TextStyle(color: C.muted)),
          const SizedBox(height: 8),
          for (final r in res)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: C.surface,
                borderRadius: BorderRadius.circular(16),
                border: r.rank == 1 && e.n > 1 ? Border.all(color: Color(e.players[r.playerIndex].color)) : null,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: Text('${r.rank}.', style: TextStyle(fontWeight: FontWeight.w800, color: C.muted2)),
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: Color(e.players[r.playerIndex].color), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.players[r.playerIndex].name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (r.detail.isNotEmpty) Text(r.detail, style: TextStyle(fontSize: 12, color: C.muted)),
                      ],
                    ),
                  ),
                  Text(r.value, style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          if (legs.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final l in legs) _leg(e, l),
          ],
        ],
      ),
    );
  }

  Widget _leg(GameEngine e, LegDetail l) {
    final wc = l.winner == null ? C.muted : Color(e.players[l.winner!].color);
    return GlowCard(
      tint: wc,
      strength: 0.05,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('LEG ${l.number}',
                  style: TextStyle(color: C.muted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1)),
              const Spacer(),
              if (l.visits.any((v) => v.singleOut))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('SINGLE OUT',
                      style: TextStyle(color: C.gold, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
                ),
              if (l.winner != null)
                Text('${e.players[l.winner!].name} · ${l.dartsOfWinner} Darts',
                    style: TextStyle(color: wc, fontWeight: FontWeight.w800, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          for (final v in l.visits)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: Color(e.players[v.player].color), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 72,
                    child: Text(e.players[v.player].name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: C.muted2)),
                  ),
                  Expanded(
                    child: Text(v.darts.map((d) => d.label).join('  '),
                        style: TextStyle(fontSize: 13, color: C.muted, fontFeatures: tabular)),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      v.bust ? 'Bust' : '${v.score}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontFamily: numFont,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: v.bust ? C.danger : (v.checkout ? C.dbl : C.text),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(v.checkout ? 'Check' : '${v.rest}',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 13, color: v.checkout ? C.dbl : C.muted, fontFeatures: tabular)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// =================================================================== Direktvergleich

class HeadToHeadScreen extends StatefulWidget {
  const HeadToHeadScreen({super.key, required this.a, required this.b});
  final String a;
  final String b;

  @override
  State<HeadToHeadScreen> createState() => _HeadToHeadScreenState();
}

class _HeadToHeadScreenState extends State<HeadToHeadScreen> {
  late String _a = widget.a;
  late String _b = widget.b;

  Widget _picker(String value, ValueChanged<String> onChanged, Color col) {
    final profiles = Store.profiles;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: C.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: col.withValues(alpha: 0.6)),
        ),
        child: DropdownButton<String>(
          value: profiles.any((p) => p.id == value) ? value : profiles.first.id,
          isExpanded: true,
          underline: const SizedBox(),
          dropdownColor: C.surface2,
          items: [
            for (final p in profiles)
              DropdownMenuItem(value: p.id, child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800))),
          ],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = Analytics.headToHead(_a, _b);
    final ca = C.players[0];
    final cb = C.players[1];
    Widget row(String label, String l, String r, {bool? leftBetter}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Expanded(
                child: Text(l,
                    style: TextStyle(
                        fontFamily: numFont,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: leftBetter == true ? ca : C.text)),
              ),
              Text(label, style: TextStyle(color: C.muted, fontSize: 13)),
              Expanded(
                child: Text(r,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontFamily: numFont,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: leftBetter == false ? cb : C.text)),
              ),
            ],
          ),
        );
    bool? better(num a, num b) => a == b ? null : a > b;
    final xa = h.avg[0];
    final xb = h.avg[1];
    return Scaffold(
      appBar: AppBar(title: const Text('Direktvergleich')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Row(
            children: [
              _picker(_a, (v) => setState(() => _a = v), ca),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('vs', style: TextStyle(color: C.muted, fontWeight: FontWeight.w800)),
              ),
              _picker(_b, (v) => setState(() => _b = v), cb),
            ],
          ),
          const SizedBox(height: 12),
          if (_a == _b)
            const _Empty('Wähle zwei verschiedene Spieler.')
          else if (h.matches == 0)
            const _Empty('Die beiden haben noch kein X01-Match gegeneinander gespielt (ab Version 2.0 gespeichert).')
          else ...[
            GlowCard(
              strength: 0.06,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${h.wins[0]}',
                          style: TextStyle(fontFamily: numFont, fontSize: 56, fontWeight: FontWeight.w800, color: ca)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(':', style: TextStyle(fontSize: 40, color: C.muted)),
                      ),
                      Text('${h.wins[1]}',
                          style: TextStyle(fontFamily: numFont, fontSize: 56, fontWeight: FontWeight.w800, color: cb)),
                    ],
                  ),
                  Text('${h.matches} Matches · Siege', style: TextStyle(color: C.muted)),
                  const Divider(height: 24),
                  row('Legs', '${h.legs[0]}', '${h.legs[1]}', leftBetter: better(h.legs[0], h.legs[1])),
                  row('3-Dart-Ø', fmt1(xa.average), fmt1(xb.average), leftBetter: better(xa.average, xb.average)),
                  row('First 9 Ø', fmt1(xa.first9), fmt1(xb.first9), leftBetter: better(xa.first9, xb.first9)),
                  row('Checkout', '${fmt1(xa.coRate)} %', '${fmt1(xb.coRate)} %',
                      leftBetter: better(xa.coRate, xb.coRate)),
                  row('Höchste Aufnahme', '${xa.highestTurn}', '${xb.highestTurn}',
                      leftBetter: better(xa.highestTurn, xb.highestTurn)),
                  row('Höchstes Finish', '${xa.highestFinish}', '${xb.highestFinish}',
                      leftBetter: better(xa.highestFinish, xb.highestFinish)),
                  row('180er', '${xa.c180}', '${xb.c180}', leftBetter: better(xa.c180, xb.c180)),
                ],
              ),
            ),
            const SectionTitle('Letzte Duelle'),
            for (final m in h.list.take(10))
              GlowCard(
                strength: 0.03,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MatchDetailScreen(summary: m))),
                child: Row(
                  children: [
                    Expanded(child: Text(_d(m.date), style: TextStyle(color: C.muted))),
                    Text(m.engine.title, style: TextStyle(color: C.muted, fontSize: 12)),
                    const SizedBox(width: 12),
                    Text(m.won ? 'Sieg' : 'Niederlage',
                        style: TextStyle(fontWeight: FontWeight.w800, color: m.won ? ca : cb)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// =================================================================== Doppel-Analyse

class DoublesScreen extends StatefulWidget {
  const DoublesScreen({super.key, required this.pid, required this.name, required this.color});
  final String pid;
  final String name;
  final Color color;

  @override
  State<DoublesScreen> createState() => _DoublesScreenState();
}

class _DoublesScreenState extends State<DoublesScreen> {
  Period _period = Period.all;

  @override
  Widget build(BuildContext context) {
    final rates = Analytics.doubles(widget.pid, _period);
    final used = rates.where((r) => r.attempts > 0).toList()..sort((a, b) => b.attempts.compareTo(a.attempts));
    final heat = {
      for (final r in rates)
        if (r.attempts > 0) (r.label == 'Bull' ? '50' : r.label): r.rate.round().clamp(1, 100),
    };
    final total = rates.fold(0, (a, r) => a + r.attempts);
    final hits = rates.fold(0, (a, r) => a + r.hits);
    return Scaffold(
      appBar: AppBar(title: Text('Doppel · ${widget.name}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<Period>(
              showSelectedIcon: false,
              segments: [for (final p in Period.values) ButtonSegment(value: p, label: Text(p.label))],
              selected: {_period},
              onSelectionChanged: (v) => setState(() => _period = v.first),
              style: segStyle(),
            ),
          ),
          const SizedBox(height: 10),
          if (used.isEmpty)
            const _Empty('Noch keine Würfe auf ein Double im Zeitraum (ab Version 2.0 gespeichert).')
          else ...[
            GlowCard(
              strength: 0.05,
              child: Column(
                children: [
                  Text('${total == 0 ? '0' : fmt1(hits / total * 100)} %',
                      style: const TextStyle(fontFamily: numFont, fontSize: 44, fontWeight: FontWeight.w800)),
                  Text('$hits Treffer bei $total Darts aufs Double', style: TextStyle(color: C.muted)),
                  const SizedBox(height: 12),
                  Dartboard(size: 300, heat: heat, color: widget.color, showCounts: true),
                  const SizedBox(height: 6),
                  Text('Zahlen = Trefferquote in %', style: TextStyle(color: C.muted, fontSize: 12)),
                ],
              ),
            ),
            const SectionTitle('Je Double'),
            for (final r in used)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 48, child: Text(r.label, style: const TextStyle(fontWeight: FontWeight.w800))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: r.rate / 100,
                          minHeight: 10,
                          color: Color.lerp(C.danger, C.dbl, (r.rate / 50).clamp(0, 1)),
                          backgroundColor: C.surface3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 92,
                      child: Text('${r.rate.round()} % · ${r.hits}/${r.attempts}',
                          textAlign: TextAlign.right, style: TextStyle(color: C.muted, fontSize: 12)),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// =================================================================== Erfolge

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key, required this.pid, required this.name});
  final String pid;
  final String name;

  @override
  Widget build(BuildContext context) {
    final list = Analytics.achievements(pid);
    final done = list.where((a) => a.done).length;
    return Scaffold(
      appBar: AppBar(title: Text('Erfolge · $name')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          GlowCard(
            tint: C.gold,
            strength: 0.10,
            child: Row(
              children: [
                Icon(Icons.military_tech_rounded, color: C.gold, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$done von ${list.length}',
                          style: const TextStyle(fontFamily: numFont, fontSize: 30, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: done / list.length,
                          minHeight: 8,
                          color: C.gold,
                          backgroundColor: C.surface3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.25,
            children: [for (final a in list) _badge(a)],
          ),
        ],
      ),
    );
  }

  Widget _badge(Achievement a) {
    final col = a.done ? C.gold : C.muted;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: a.done ? C.cardGradient(C.gold, 0.16) : null,
        color: a.done ? null : C.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: a.done ? C.gold.withValues(alpha: 0.6) : C.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(a.done ? Icons.emoji_events_rounded : Icons.lock_outline_rounded, color: col, size: 26),
          const Spacer(),
          Text(a.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: a.done ? C.text : C.muted2)),
          Text(a.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 12)),
          if (!a.done && a.goal != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (a.progress ?? 0) / a.goal!,
                minHeight: 5,
                color: C.accent,
                backgroundColor: C.surface3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

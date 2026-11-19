import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../data/sound.dart';
import '../data/storage.dart';
import '../data/tournament_store.dart';
import '../games/engine.dart';
import '../games/tournament.dart';
import '../models/player.dart';
import 'bull_off.dart';
import 'celebration.dart';
import 'game_screen.dart';
import 'link_coordinator.dart';
import 'share_card.dart';
import 'theme.dart';

const _gold = Color(0xFFFFC94A);
const _silver = Color(0xFFC9D1DA);
const _bronze = Color(0xFFD98C4A);

Color medalColor(int rank) => switch (rank) {
  1 => _gold,
  2 => _silver,
  3 => _bronze,
  _ => C.muted,
};

String _dateLabel(DateTime d) => '${d.day}.${d.month}.${d.year}';

// =================================================================== Assistent

class TournamentSetupScreen extends StatefulWidget {
  const TournamentSetupScreen({super.key});

  @override
  State<TournamentSetupScreen> createState() => _TournamentSetupScreenState();
}

class _TournamentSetupScreenState extends State<TournamentSetupScreen> {
  int _step = 0;
  final _name = TextEditingController(text: 'Turnier ${_dateLabel(DateTime.now())}');
  final _newPlayer = TextEditingController();
  final List<TPlayer> _players = [];
  TSystem _system = TSystem.ko;
  bool _homeAway = false;
  int _groups = 2;
  int _advance = 2;
  int _start = 501;
  bool _doubleOut = true;
  final Map<TStage, TFormat> _formats = {
    TStage.group: const TFormat(legs: 2),
    TStage.early: const TFormat(legs: 2),
    TStage.qf: const TFormat(legs: 3),
    TStage.sf: const TFormat(legs: 3),
    TStage.finale: const TFormat(legs: 4),
  };
  bool _seeded = false;

  static const _titles = ['Spieler', 'Modus', 'Setzliste', 'Format'];

  @override
  void dispose() {
    _name.dispose();
    _newPlayer.dispose();
    super.dispose();
  }

  void _snack(String t) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(t)));

  void _addName(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return;
    if (_players.length >= 32) return _snack('Maximal 32 Spieler.');
    if (_players.any((p) => p.name.toLowerCase() == name.toLowerCase())) return _snack('$name ist schon dabei.');
    final prof = Store.ensureProfile(name);
    setState(() {
      _players.add(TPlayer(prof.id, prof.name));
      _seeded = false;
    });
    _newPlayer.clear();
  }

  void _toggleProfile(String id, String name) {
    setState(() {
      final i = _players.indexWhere((p) => p.profileId == id);
      if (i >= 0) {
        _players.removeAt(i);
      } else if (_players.length < 32) {
        _players.add(TPlayer(id, name));
      }
      _seeded = false;
    });
  }

  void _applyGroupSuggestion() {
    final (g, a) = suggestGroups(_players.length);
    _groups = g;
    _advance = a;
  }

  int get _maxGroups => max(2, _players.length ~/ 2);
  int get _minGroupSize => _players.length ~/ _groups;

  bool _validateStep() {
    switch (_step) {
      case 0:
        if (_players.length < 3) {
          _snack('Ein Turnier braucht mindestens 3 Spieler.');
          return false;
        }
        return true;
      case 1:
        if (_system == TSystem.groups && _players.length < 4) {
          _snack('Für Gruppen braucht es mindestens 4 Spieler.');
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  void _next() {
    if (!_validateStep()) return;
    Haptics.selection();
    setState(() {
      if (_step == 0 && _system == TSystem.groups) _applyGroupSuggestion();
      if (_step == 1 && !_seeded) {
        final seeded = TournamentStore.seedByAverage(_players);
        _players
          ..clear()
          ..addAll(seeded);
        _seeded = true;
      }
      _step++;
    });
  }

  void _create() {
    final t = Tournament(
      id: TournamentStore.newId(),
      name: _name.text.trim().isEmpty ? 'Turnier' : _name.text.trim(),
      created: DateTime.now(),
      system: _system,
      players: List.of(_players),
      start: _start,
      doubleOut: _doubleOut,
      formats: {for (final s in _stages) s: _formats[s]!},
      homeAway: _homeAway,
      groupCount: _groups,
      advance: _advance,
    )..build();
    TournamentStore.save(t);
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => TournamentScreen(id: t.id)));
  }

  List<TStage> get _stages => Tournament.stagesFor(_system, _players.length, groupCount: _groups, advance: _advance);

  @override
  Widget build(BuildContext context) {
    final last = _step == _titles.length - 1;
    return Scaffold(
      appBar: AppBar(title: const Text('Neues Turnier')),
      body: SafeArea(
        child: Column(
          children: [
            _stepper(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: KeyedSubtree(key: ValueKey(_step), child: _content()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Row(
                children: [
                  if (_step > 0) ...[
                    SizedBox(
                      height: 56,
                      width: 110,
                      child: Key3(
                        semantics: 'Zurück',
                        onTap: () => setState(() => _step--),
                        color: C.surface2,
                        borderColor: C.line,
                        radius: 18,
                        child: const Text('Zurück', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: PrimaryButton(
                      label: last ? 'Turnier starten' : 'Weiter',
                      icon: last ? Icons.emoji_events_rounded : Icons.arrow_forward_rounded,
                      onTap: last ? _create : _next,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepper() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Row(
      children: [
        for (var i = 0; i < _titles.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: i <= _step ? C.accentGradient : null,
                    color: i <= _step ? null : C.surface3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _titles[i],
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: i == _step ? C.text : C.muted),
                ),
              ],
            ),
          ),
          if (i < _titles.length - 1) const SizedBox(width: 6),
        ],
      ],
    ),
  );

  Widget _content() => switch (_step) {
    0 => _playersStep(),
    1 => _systemStep(),
    2 => _seedStep(),
    _ => _formatStep(),
  };

  // ---------------------------------------------------------------- 1 Spieler

  Widget _playersStep() {
    final saved = Store.profiles;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        GlowCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          strength: 0.05,
          child: TextField(
            controller: _name,
            maxLength: 30,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              labelText: 'Name des Turniers',
              counterText: '',
              border: InputBorder.none,
              labelStyle: TextStyle(color: C.muted),
            ),
          ),
        ),
        SectionTitle('Teilnehmer', trailing: '${_players.length} / 32'),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newPlayer,
                maxLength: 14,
                textCapitalization: TextCapitalization.words,
                onSubmitted: _addName,
                decoration: InputDecoration(
                  hintText: 'Neuen Spieler eingeben',
                  counterText: '',
                  filled: true,
                  fillColor: C.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Spieler hinzufügen',
              onPressed: () => _addName(_newPlayer.text),
              icon: const Icon(Icons.add_rounded),
              style: IconButton.styleFrom(
                backgroundColor: C.accent,
                foregroundColor: C.onAccent,
                minimumSize: const Size(52, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
        if (saved.isNotEmpty) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text('Gespeicherte Spieler antippen', style: TextStyle(color: C.muted, fontSize: 13)),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in saved)
                FilterChip(
                  label: Text(p.name),
                  selected: _players.any((x) => x.profileId == p.id),
                  onSelected: (_) => _toggleProfile(p.id, p.name),
                  showCheckmark: true,
                  checkmarkColor: C.accent,
                ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        for (var i = 0; i < _players.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: C.players[i % 4],
                  child: Text(
                    _players[i].name.characters.first.toUpperCase(),
                    style: const TextStyle(color: C.ink, fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_players[i].name, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  tooltip: '${_players[i].name} entfernen',
                  icon: Icon(Icons.close_rounded, color: C.muted),
                  onPressed: () => setState(() {
                    _players.removeAt(i);
                    _seeded = false;
                  }),
                ),
              ],
            ),
          ),
        if (_players.length < 3)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Mindestens 3 Spieler hinzufügen.',
              textAlign: TextAlign.center,
              style: TextStyle(color: C.muted),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------- 2 System

  Widget _systemStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        for (final s in TSystem.values)
          GlowCard(
            tint: s == _system ? C.accent : C.muted,
            strength: s == _system ? 0.14 : 0.02,
            borderAlpha: s == _system ? 0.8 : 0.1,
            onTap: () => setState(() {
              _system = s;
              if (s == TSystem.groups) _applyGroupSuggestion();
            }),
            child: Row(
              children: [
                Icon(
                  switch (s) {
                    TSystem.ko => Icons.account_tree_rounded,
                    TSystem.doubleKo => Icons.alt_route_rounded,
                    TSystem.groups => Icons.grid_view_rounded,
                    TSystem.league => Icons.table_rows_rounded,
                  },
                  color: s == _system ? C.accent : C.muted,
                  size: 30,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      Text(s.description, style: TextStyle(color: C.muted, fontSize: 13)),
                    ],
                  ),
                ),
                Icon(
                  s == _system ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: s == _system ? C.accent : C.line,
                ),
              ],
            ),
          ),
        if (_system == TSystem.league)
          GlowCard(
            strength: 0.04,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _homeAway,
              onChanged: (v) => setState(() => _homeAway = v),
              title: const Text('Hin- und Rückspiel', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Jeder spielt zweimal gegen jeden', style: TextStyle(color: C.muted)),
            ),
          ),
        if (_system == TSystem.groups) _groupOptions(),
        const SizedBox(height: 6),
        Text(
          _summary(),
          textAlign: TextAlign.center,
          style: TextStyle(color: C.muted, fontSize: 13),
        ),
      ],
    );
  }

  String _summary() {
    final n = _players.length;
    switch (_system) {
      case TSystem.ko:
        final byes = nextPow2(n) - n;
        return '${n - 1 + 1} Matches inkl. Spiel um Platz 3${byes > 0 ? ' · $byes Freilos${byes == 1 ? '' : 'e'}' : ''}';
      case TSystem.doubleKo:
        return 'Ca. ${2 * n - 1} Matches · ${nextPow2(n) - n} Freilose in Runde 1';
      case TSystem.league:
        final m = n * (n - 1) ~/ 2 * (_homeAway ? 2 : 1);
        return '$m Matches';
      case TSystem.groups:
        return '';
    }
  }

  Widget _groupOptions() {
    final groups = Tournament(
      id: '',
      name: '',
      created: DateTime.now(),
      system: TSystem.groups,
      players: _players,
      start: 501,
      doubleOut: true,
      formats: const {},
      groupCount: _groups,
      advance: _advance,
    ).groupMembers();
    final q = _groups * _advance;
    return GlowCard(
      strength: 0.05,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NumberStepper(
            label: 'Gruppen',
            value: _groups,
            min: 2,
            max: _maxGroups,
            onChanged: (v) => setState(() {
              _groups = v;
              _advance = _advance.clamp(1, max(1, _minGroupSize - 1));
            }),
          ),
          const SizedBox(height: 8),
          NumberStepper(
            label: 'Aufsteiger je Gruppe',
            value: _advance,
            min: 1,
            max: max(1, _minGroupSize - 1),
            onChanged: (v) => setState(() => _advance = v),
          ),
          const SizedBox(height: 10),
          Text(
            '${[for (var g = 0; g < groups.length; g++) '${String.fromCharCode(65 + g)}: ${groups[g].length}'].join(' · ')}'
            ' · $q im K.o.${nextPow2(q) > q ? ' (${nextPow2(q) - q} Freilos${nextPow2(q) - q == 1 ? '' : 'e'})' : ''}',
            style: TextStyle(color: C.muted, fontSize: 13),
          ),
          TextButton(onPressed: () => setState(_applyGroupSuggestion), child: const Text('Vorschlag übernehmen')),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 3 Setzliste

  Widget _seedStep() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _system == TSystem.league
                      ? 'Reihenfolge bestimmt den Spielplan.'
                      : 'Nr. 1 trifft erst spät auf Nr. 2. Zum Ändern ziehen.',
                  style: TextStyle(color: C.muted, fontSize: 13),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Sortieren',
                icon: const Icon(Icons.sort_rounded),
                onSelected: (v) => setState(() {
                  final list = v == 'avg' ? TournamentStore.seedByAverage(_players) : (List.of(_players)..shuffle());
                  _players
                    ..clear()
                    ..addAll(list);
                }),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'avg', child: Text('Nach Average setzen')),
                  PopupMenuItem(value: 'rnd', child: Text('Zufällig auslosen')),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _players.length,
            onReorderItem: (a, b) => setState(() => _players.insert(b, _players.removeAt(a))),
            itemBuilder: (_, i) {
              final p = _players[i];
              final avg = TournamentStore.averageOf(p.profileId);
              return Container(
                key: ValueKey(p.profileId),
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  gradient: C.cardGradient(i < 4 ? medalColor(i + 1) : C.accent, i < 4 ? 0.10 : 0.03),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: C.border),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontFamily: numFont,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: i < 4 ? medalColor(min(i + 1, 3)) : C.muted,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                    Text(avg > 0 ? 'Ø ${fmt1(avg)}' : 'neu', style: TextStyle(color: C.muted, fontSize: 13)),
                    const SizedBox(width: 8),
                    Icon(Icons.drag_handle_rounded, color: C.muted),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- 4 Format

  Widget _formatStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        const SectionTitle('Spiel'),
        GlowCard(
          strength: 0.05,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Startpunkte', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 301, label: Text('301')),
                    ButtonSegment(value: 501, label: Text('501')),
                    ButtonSegment(value: 701, label: Text('701')),
                  ],
                  selected: {_start},
                  onSelectionChanged: (v) => setState(() => _start = v.first),
                  style: segStyle(),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Check-Out', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: Text('Double Out')),
                    ButtonSegment(value: false, label: Text('Single Out')),
                  ],
                  selected: {_doubleOut},
                  onSelectionChanged: (v) => setState(() => _doubleOut = v.first),
                  style: segStyle(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const SectionTitle('Länge je Runde'),
        for (final st in _stages) _formatCard(st),
      ],
    );
  }

  Widget _formatCard(TStage st) {
    final f = _formats[st]!;
    void upd(TFormat v) => setState(() => _formats[st] = v);
    return GlowCard(
      tint: st == TStage.finale ? _gold : C.accent,
      strength: st == TStage.finale ? 0.10 : 0.04,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(st.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Legs')),
                  ButtonSegment(value: true, label: Text('Sets')),
                ],
                selected: {f.sets},
                onSelectionChanged: (v) => upd(f.copyWith(sets: v.first)),
                style: segStyle(),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (f.sets)
            NumberStepper(
              label: 'First to … Sets',
              value: f.setCount,
              min: 1,
              max: 7,
              onChanged: (v) => upd(f.copyWith(setCount: v)),
            ),
          NumberStepper(
            label: f.sets ? 'Legs pro Set' : 'First to … Legs',
            value: f.legs,
            min: 1,
            max: 9,
            onChanged: (v) => upd(f.copyWith(legs: v)),
          ),
        ],
      ),
    );
  }
}

// =================================================================== Übersicht

class TournamentScreen extends StatefulWidget {
  const TournamentScreen({super.key, required this.id, this.remote = false});
  final String id;

  /// Anzeige eines Turniers vom gekoppelten Host (Stand kommt live).
  final bool remote;

  @override
  State<TournamentScreen> createState() => _TournamentScreenState();
}

class _TournamentScreenState extends State<TournamentScreen> {
  late Tournament? _t = _load();
  int _view = 0; // 0 Spiele, 1 Baum, 2 Tabelle
  bool _celebrate = false;

  Tournament get t => _t!;

  Tournament? _load() {
    if (!widget.remote) return TournamentStore.byId(widget.id);
    final j = LinkCoordinator.remoteTournament;
    if (j == null || j['id'] != widget.id) return _t;
    try {
      return Tournament.fromJson(j);
    } catch (_) {
      return _t;
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.remote) {
      LinkCoordinator.remoteTick.addListener(_reload);
    } else {
      LinkCoordinator.tournamentOpened(widget.id);
      TournamentStore.changes.addListener(_onStoreChange);
    }
  }

  void _onStoreChange() => scheduleMicrotask(_reload);

  @override
  void dispose() {
    if (widget.remote) {
      LinkCoordinator.remoteTick.removeListener(_reload);
    } else {
      LinkCoordinator.tournamentClosed(widget.id);
      TournamentStore.changes.removeListener(_onStoreChange);
    }
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    final wasFinished = _t?.finished ?? false;
    setState(() => _t = _load());
    if (!widget.remote) LinkCoordinator.tournamentChanged();
    if (_t != null && _t!.finished && !wasFinished) {
      setState(() => _celebrate = Store.celebrations);
      if (!Store.celebrations) Sound.play('win');
    }
  }

  List<(int, String)> get _views => [
    (0, 'Spiele'),
    if (t.system != TSystem.league) (1, 'Baum'),
    if (t.system == TSystem.league || t.system == TSystem.groups) (2, 'Tabelle'),
  ];

  Future<void> _play(TMatch m) async {
    if (widget.remote) {
      final (a, b) = t.participants(m);
      final start = await showBullOff(context, [
        GamePlayer(t.players[a!].profileId, t.players[a].name, C.players[0].toARGB32()),
        GamePlayer(t.players[b!].profileId, t.players[b].name, C.players[1].toARGB32()),
      ]);
      if (start == null || !mounted) return;
      final c = TournamentStore.controllerFor(t, m, start);
      LinkCoordinator.startOnHost(c);
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(controller: c)));
      return;
    }
    var ctl = TournamentStore.activeFor(t, m.id);
    if (ctl == null) {
      final other = Store.activeMatch;
      if (other != null) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Laufendes Match verwerfen?'),
            content: const Text('Es gibt noch ein unterbrochenes Match. Wenn du dieses startest, geht es verloren.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Verwerfen')),
            ],
          ),
        );
        if (ok != true || !mounted) return;
        Store.activeMatch = null;
      }
      final (a, b) = t.participants(m);
      final start = await showBullOff(context, [
        GamePlayer(t.players[a!].profileId, t.players[a].name, C.players[0].toARGB32()),
        GamePlayer(t.players[b!].profileId, t.players[b].name, C.players[1].toARGB32()),
      ]);
      if (start == null || !mounted) return;
      ctl = TournamentStore.controllerFor(t, m, start);
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(controller: ctl!)));
    if (mounted) _reload();
  }

  Future<void> _confirmReset(TMatch m) async {
    if (!t.canReset(m)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ergebnis kann nicht mehr geändert werden – Folge-Matches sind gespielt.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ergebnis zurücksetzen?'),
        content: const Text('Das Match kann danach neu gespielt werden. Die Statistik bleibt erhalten.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Zurücksetzen')),
        ],
      ),
    );
    if (ok == true) {
      t.reset(m);
      TournamentStore.save(t);
      _reload();
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${t.name} löschen?'),
        content: const Text('Das Turnier und sein Verlauf werden entfernt. Die Spielerstatistik bleibt erhalten.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: C.danger, foregroundColor: Colors.white),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok == true) {
      TournamentStore.delete(t.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_t == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Turnier nicht gefunden')),
      );
    }
    final views = _views;
    if (!views.any((v) => v.$1 == _view)) _view = 0;
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              if (t.finished)
                IconButton(
                  tooltip: 'Siegerpodest teilen',
                  icon: const Icon(Icons.ios_share_rounded),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ShareCardScreen(card: TournamentShareCard(t: t), fileName: 'darts_turnier.png'),
                  )),
                ),
              if (!widget.remote)
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'del') _delete();
                  },
                  itemBuilder: (_) => const [PopupMenuItem(value: 'del', child: Text('Turnier löschen'))],
                ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${t.system.label} · ${t.n} Spieler · ${t.start} ${t.doubleOut ? 'DO' : 'SO'} · ${t.playedCount}/${t.realCount} Matches',
                        style: TextStyle(color: C.muted, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              if (views.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: [for (final (v, l) in views) ButtonSegment(value: v, label: Text(l))],
                      selected: {_view},
                      onSelectionChanged: (s) => setState(() => _view = s.first),
                      style: segStyle(),
                    ),
                  ),
                ),
              Expanded(
                child: switch (_view) {
                  1 => BracketView(t: t, onTap: _matchTap),
                  2 => _tables(),
                  _ => _matchList(),
                },
              ),
            ],
          ),
        ),
        if (_celebrate && t.champion != null)
          Positioned.fill(
            child: CelebrationOverlay(
              kind: CelebrationKind.match,
              name: t.players[t.champion!].name,
              color: _gold,
              darts: const [],
              label: 'TURNIERSIEG',
              onDone: () => setState(() => _celebrate = false),
            ),
          ),
      ],
    );
  }

  void _matchTap(TMatch m) {
    if (t.isPlayable(m)) {
      _play(m);
    } else if (m.played && !widget.remote) {
      _confirmReset(m);
    }
  }

  String _slotName(TMatch m, int side) => slotName(t, m, side);

  Widget _matchList() {
    final playable = t.playable;
    final played = t.matches.where((m) => m.played).toList().reversed.toList();
    final waiting = t.matches.where((m) => !m.played && !t.isDecided(m) && !t.isPlayable(m)).toList();
    final active = Store.activeMatch;
    final activeId = active != null && active['tid'] == t.id ? active['tmid'] as String? : null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (t.finished) _podium(),
        if (playable.isNotEmpty) ...[
          SectionTitle('Jetzt spielbar', trailing: '${playable.length}'),
          for (final m in playable) _matchCard(m, live: m.id == activeId),
        ],
        if (waiting.isNotEmpty) ...[
          const SizedBox(height: 8),
          SectionTitle('Ausstehend', trailing: '${waiting.length}'),
          for (final m in waiting) _matchCard(m),
        ],
        if (played.isNotEmpty) ...[
          const SizedBox(height: 8),
          SectionTitle('Gespielt', trailing: '${played.length}'),
          for (final m in played) _matchCard(m),
        ],
      ],
    );
  }

  Widget _matchCard(TMatch m, {bool live = false}) {
    final playable = t.isPlayable(m);
    final f = t.formatOf(m.stage);
    Widget side(int s) {
      final won = m.played && m.winnerSide == s;
      final score = m.played ? (f.sets ? m.sets[s] : m.legs[s]) : null;
      return Row(
        children: [
          Expanded(
            child: Text(
              _slotName(m, s),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: won ? FontWeight.w800 : FontWeight.w600,
                color: m.played && !won ? C.muted : C.text,
              ),
            ),
          ),
          if (score != null)
            Text(
              '$score',
              style: TextStyle(
                fontFamily: numFont,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: won ? C.accent : C.muted,
              ),
            ),
        ],
      );
    }

    return GlowCard(
      tint: live ? C.dbl : (playable ? C.accent : C.muted),
      strength: playable ? 0.10 : 0.02,
      borderAlpha: playable ? 0.45 : 0.08,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      margin: const EdgeInsets.only(bottom: 8),
      onTap: () => _matchTap(m),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${t.roundLabel(m)} · ${f.label}'.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: C.muted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6),
                ),
                const SizedBox(height: 4),
                side(0),
                side(1),
                if (m.played && m.darts[0] + m.darts[1] > 0)
                  Text('Ø ${fmt1(m.avg(0))} : ${fmt1(m.avg(1))}', style: TextStyle(color: C.muted, fontSize: 12)),
              ],
            ),
          ),
          if (playable) ...[
            const SizedBox(width: 8),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: live ? null : C.accentGradient,
                color: live ? C.dbl : null,
              ),
              child: Icon(live ? Icons.play_arrow_rounded : Icons.sports_score_rounded, color: C.onAccent),
            ),
          ],
        ],
      ),
    );
  }

  Widget _podium() {
    final pl = t.placements();
    String nameOf(int rank) => pl.where((p) => p.rank == rank).map((p) => t.players[p.player].name).join(' / ');
    Widget step(int rank, double h) {
      final name = nameOf(rank);
      return Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (rank == 1) const Icon(Icons.emoji_events_rounded, color: _gold, size: 36),
            Text(
              name.isEmpty ? '–' : name,
              textAlign: TextAlign.center,
              softWrap: true,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: rank == 1 ? 17 : 14),
            ),
            const SizedBox(height: 6),
            Container(
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [medalColor(rank), medalColor(rank).withValues(alpha: 0.35)],
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                '$rank',
                style: const TextStyle(fontFamily: numFont, fontSize: 34, fontWeight: FontWeight.w800, color: C.ink),
              ),
            ),
          ],
        ),
      );
    }

    return GlowCard(
      tint: _gold,
      strength: 0.12,
      borderAlpha: 0.5,
      child: Column(
        children: [
          Text(
            'SIEGEREHRUNG',
            style: TextStyle(color: C.muted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.4),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 215,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [step(2, 70), step(1, 100), step(3, 50)]),
          ),
          const SizedBox(height: 10),
          for (final p in pl.where((p) => p.rank > 3))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(
                      '${p.rank}.',
                      style: TextStyle(color: C.muted, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Expanded(child: Text(t.players[p.player].name)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tables() {
    final groups = t.system == TSystem.groups ? List.generate(t.groupCount, (g) => g) : <int?>[null];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (t.finished && t.system == TSystem.league) _podium(),
        for (final g in groups) ...[
          if (g != null) SectionTitle('Gruppe ${String.fromCharCode(65 + g)}'),
          _table(t.standings(group: g), g == null ? 0 : t.advance),
          const SizedBox(height: 8),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Sortierung: Siege, dann Legdifferenz, direkter Vergleich, Average',
            textAlign: TextAlign.center,
            style: TextStyle(color: C.muted, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _table(List<TStanding> rows, int qualify) {
    TextStyle h = TextStyle(color: C.muted, fontSize: 11, fontWeight: FontWeight.w800);
    Widget cell(String s, {double w = 34, TextStyle? style}) => SizedBox(
      width: w,
      child: Text(s, textAlign: TextAlign.center, style: style),
    );
    return GlowCard(
      strength: 0.04,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: Column(
        children: [
          Row(
            children: [
              cell('#', w: 26, style: h),
              Expanded(child: Text('SPIELER', style: h)),
              cell('SP', style: h),
              cell('S', style: h),
              cell('N', style: h),
              cell('LEGS', w: 52, style: h),
              cell('Ø', w: 44, style: h),
            ],
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: C.surface3)),
                color: i < qualify ? C.accent.withValues(alpha: 0.08) : null,
              ),
              child: Row(
                children: [
                  cell(
                    '${i + 1}',
                    w: 26,
                    style: TextStyle(fontWeight: FontWeight.w800, color: i < qualify ? C.accent : C.muted2),
                  ),
                  Expanded(
                    child: Text(
                      t.players[rows[i].player].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  cell('${rows[i].played}'),
                  cell('${rows[i].wins}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  cell('${rows[i].losses}'),
                  cell('${rows[i].legsFor}:${rows[i].legsAgainst}', w: 52),
                  cell(rows[i].darts == 0 ? '–' : fmt1(rows[i].average), w: 44, style: TextStyle(color: C.muted)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Anzeigename eines Teilnehmers – bei offenen Plätzen mit Herkunft.
String slotName(Tournament t, TMatch m, int side) {
  final (a, b) = t.participants(m);
  final v = side == 0 ? a : b;
  if (v != null) return v < 0 ? 'Freilos' : t.players[v].name;
  final slot = side == 0 ? m.a : m.b;
  if (slot.kind == 'q') return 'Gruppe ${String.fromCharCode(65 + slot.group)} · Platz ${slot.place + 1}';
  if ((slot.kind == 'win' || slot.kind == 'lose') && slot.match != null) {
    final src = t.matchById(slot.match!);
    final (sa, sb) = t.participants(src);
    if (sa != null && sb != null && sa >= 0 && sb >= 0) {
      return '${slot.kind == 'win' ? 'Sieger' : 'Verlierer'} ${t.players[sa].name}/${t.players[sb].name}';
    }
  }
  return 'offen';
}

// =================================================================== Baum

class BracketView extends StatelessWidget {
  const BracketView({super.key, required this.t, required this.onTap});
  final Tournament t;
  final void Function(TMatch m) onTap;

  static const _w = 176.0;
  static const _h = 62.0;
  static const _gap = 14.0;

  @override
  Widget build(BuildContext context) {
    final sections = <(String, List<TMatch>)>[
      ('Hauptrunde', t.matches.where((m) => m.bracket == 'W').toList()),
      if (t.system == TSystem.doubleKo) ('Verliererrunde', t.matches.where((m) => m.bracket == 'L').toList()),
      if (t.system == TSystem.doubleKo) ('Finale', t.matches.where((m) => m.bracket == 'F').toList()),
      if (t.matches.any((m) => m.bracket == 'P3'))
        ('Spiel um Platz 3', t.matches.where((m) => m.bracket == 'P3').toList()),
    ];
    return InteractiveViewer(
      constrained: false,
      minScale: 0.4,
      maxScale: 2,
      boundaryMargin: const EdgeInsets.all(80),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (title, ms) in sections)
              if (ms.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, top: 8),
                  child: Text(
                    title.toUpperCase(),
                    style: TextStyle(color: C.muted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2),
                  ),
                ),
                _section(ms, tree: title == 'Hauptrunde'),
              ],
          ],
        ),
      ),
    );
  }

  Widget _section(List<TMatch> ms, {required bool tree}) {
    final rounds = (ms.map((m) => m.round).toSet().toList()..sort());
    final first = ms.where((m) => m.round == rounds.first).length;
    final height = max(first, 1) * (_h + _gap);
    return SizedBox(
      height: tree ? height : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in rounds) ...[
            SizedBox(
              width: _w,
              height: tree ? height : null,
              child: Column(
                mainAxisAlignment: tree ? MainAxisAlignment.spaceAround : MainAxisAlignment.start,
                children: [
                  for (final m in (ms.where((m) => m.round == r).toList()..sort((a, b) => a.order.compareTo(b.order))))
                    Padding(
                      padding: EdgeInsets.only(bottom: tree ? 0 : _gap),
                      child: _box(m),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 18),
          ],
        ],
      ),
    );
  }

  Widget _box(TMatch m) {
    final (a, b) = t.participants(m);
    final skipped = t.isSkipped(m);
    final playable = t.isPlayable(m);
    final f = t.formatOf(m.stage);
    String label(int side, int? v) =>
        v == null ? slotName(t, m, side).replaceFirst('offen', '–') : (v < 0 ? 'Freilos' : t.players[v].name);
    Widget row(int side, int? v) {
      final won = (m.played && m.winnerSide == side) || (!m.played && t.isDecided(m) && v != null && v >= 0);
      final score = m.played ? (f.sets ? m.sets[side] : m.legs[side]) : null;
      return Expanded(
        child: Row(
          children: [
            Expanded(
              child: Text(
                label(side, v),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: won ? FontWeight.w800 : FontWeight.w600,
                  color: v == null || v < 0 || (m.played && !won) ? C.muted : C.text,
                ),
              ),
            ),
            if (score != null)
              Text(
                '$score',
                style: TextStyle(fontFamily: numFont, fontWeight: FontWeight.w800, color: won ? C.accent : C.muted),
              ),
          ],
        ),
      );
    }

    return Opacity(
      opacity: skipped ? 0.35 : 1,
      child: GestureDetector(
        onTap: () => onTap(m),
        child: Container(
          width: _w,
          height: _h,
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          decoration: BoxDecoration(
            gradient: C.cardGradient(playable ? C.accent : C.muted, playable ? 0.14 : 0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: playable ? C.accent.withValues(alpha: 0.7) : C.border),
          ),
          child: Column(
            children: [
              row(0, a),
              Divider(height: 1, color: C.surface3),
              row(1, b),
            ],
          ),
        ),
      ),
    );
  }
}

// =================================================================== Historie

class TournamentHistoryScreen extends StatefulWidget {
  const TournamentHistoryScreen({super.key});

  @override
  State<TournamentHistoryScreen> createState() => _TournamentHistoryScreenState();
}

class _TournamentHistoryScreenState extends State<TournamentHistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final list = TournamentStore.history;
    return Scaffold(
      appBar: AppBar(title: const Text('Turnier-Historie')),
      body: list.isEmpty
          ? Center(
              child: Text('Noch keine abgeschlossenen Turniere.', style: TextStyle(color: C.muted)),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                for (final t in list)
                  GlowCard(
                    tint: _gold,
                    strength: 0.06,
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TournamentScreen(id: t.id)));
                      if (mounted) setState(() {});
                    },
                    child: Row(
                      children: [
                        const Icon(Icons.emoji_events_rounded, color: _gold, size: 32),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                              Text(
                                'Sieger: ${t.champion == null ? '–' : t.players[t.champion!].name} · '
                                '${t.system.label} · ${t.n} Spieler · ${_dateLabel(t.created)}',
                                style: TextStyle(color: C.muted, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: C.muted),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

// =================================================================== Übersicht aller Turniere

class TournamentHubScreen extends StatefulWidget {
  const TournamentHubScreen({super.key});

  @override
  State<TournamentHubScreen> createState() => _TournamentHubScreenState();
}

class _TournamentHubScreenState extends State<TournamentHubScreen> {
  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() {});
  }

  Widget _iconBox(IconData icon, Color col) => Container(
    width: 52,
    height: 52,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [col.withValues(alpha: 0.28), col.withValues(alpha: 0.10)],
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Icon(icon, color: col, size: 28),
  );

  @override
  Widget build(BuildContext context) {
    final running = TournamentStore.running;
    final history = TournamentStore.history;
    return Scaffold(
      appBar: AppBar(title: const Text('Turnier')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          GlowCard(
            onTap: () => _open(const TournamentSetupScreen()),
            strength: 0.12,
            borderAlpha: 0.45,
            child: Row(
              children: [
                _iconBox(Icons.add_rounded, C.accent),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Neues Turnier', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      Text(
                        'K.o., Doppel-K.o., Gruppen oder Liga · 3–32 Spieler',
                        style: TextStyle(color: C.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: C.muted),
              ],
            ),
          ),
          if (running.isNotEmpty) ...[
            const SizedBox(height: 8),
            SectionTitle('Läuft', trailing: '${running.length}'),
            for (final t in running)
              GlowCard(
                tint: _gold,
                strength: 0.10,
                borderAlpha: 0.35,
                onTap: () => _open(TournamentScreen(id: t.id)),
                child: Row(
                  children: [
                    _iconBox(Icons.emoji_events_rounded, _gold),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                          Text(
                            '${t.system.label} · ${t.n} Spieler · ${t.playedCount}/${t.realCount} Matches',
                            style: TextStyle(color: C.muted, fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: t.realCount == 0 ? 0 : t.playedCount / t.realCount,
                              minHeight: 5,
                              color: _gold,
                              backgroundColor: C.surface3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right_rounded, color: C.muted),
                  ],
                ),
              ),
          ],
          if (history.isNotEmpty) ...[
            const SizedBox(height: 8),
            SectionTitle('Historie', trailing: '${history.length}'),
            for (final t in history)
              GlowCard(
                tint: _gold,
                strength: 0.04,
                onTap: () => _open(TournamentScreen(id: t.id)),
                child: Row(
                  children: [
                    const Icon(Icons.emoji_events_rounded, color: _gold, size: 30),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          Text(
                            'Sieger: ${t.champion == null ? '–' : t.players[t.champion!].name} · '
                            '${t.system.label} · ${_dateLabel(t.created)}',
                            style: TextStyle(color: C.muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: C.muted),
                  ],
                ),
              ),
          ],
          if (running.isEmpty && history.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Noch keine Turniere. Leg los mit „Neues Turnier“.',
                textAlign: TextAlign.center,
                style: TextStyle(color: C.muted),
              ),
            ),
        ],
      ),
    );
  }
}

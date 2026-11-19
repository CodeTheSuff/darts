import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../data/match_controller.dart';
import '../data/storage.dart';
import '../games/bot.dart';
import '../games/catalog.dart';
import '../games/engine.dart';
import '../models/player.dart';
import '../net/link.dart';
import 'bull_off.dart';
import 'game_screen.dart';
import 'link_coordinator.dart';
import 'theme.dart';

class _Slot {
  _Slot(String name, this.color)
      : ctl = TextEditingController(text: name),
        isBot = false;
  _Slot.bot(this.level, this.color, {this.avg = 55, this.dbl = 20})
      : ctl = TextEditingController(),
        isBot = true;
  final TextEditingController ctl;
  Color color;
  final bool isBot;

  /// Bot-Stufe; null = eigener Bot mit [avg] und [dbl].
  BotLevel? level;
  int avg = 55;
  int dbl = 20;

  String get botId => level != null ? botIdFor(level!) : customBotId(avg, dbl);
  String get botName => level != null ? botNameFor(level!) : customBotName(avg, dbl);
}

/// Spieler (Namen + Farben) und Regeln des gewählten Modus einstellen.
///
/// Mit [embedded] wird nur der Inhalt (ohne AppBar) gezeigt – für den
/// Spiel-Tab der Startseite. [header] und [footer] kommen in die Liste.
class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    required this.mode,
    this.embedded = false,
    this.header = const [],
    this.footer = const [],
    this.onReturn,
  });
  final ModeDef mode;
  final bool embedded;
  final List<Widget> header;
  final List<Widget> footer;

  /// Wird aufgerufen, wenn man aus dem Spiel zurückkommt.
  final VoidCallback? onReturn;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final List<_Slot> _slots = [];
  late Map<String, dynamic> _opts;
  bool _showRules = false;

  bool get _isX01 => widget.mode.id == 'x01';
  int get _humans => _slots.where((s) => !s.isBot).length;
  bool get _hasBot => _slots.any((s) => s.isBot);

  @override
  void initState() {
    super.initState();
    final last = Store.lastSetup;
    if (last != null) {
      for (final p in (last['players'] as List)) {
        final m = Map<String, dynamic>.from(p as Map);
        if (m['bot'] != null) {
          final bot = BotLevel.values.where((l) => l.name == m['bot']).firstOrNull;
          if (_isX01) {
            _slots.add(_Slot.bot(bot, Color(m['color'] as int),
                avg: (m['avg'] as int?) ?? 55, dbl: (m['dbl'] as int?) ?? 20));
          }
        } else {
          _slots.add(_Slot(m['name'] as String, Color(m['color'] as int)));
        }
      }
    }
    if (_humans == 0) _slots.insert(0, _Slot('', C.players[0]));
    _fixColors();

    _opts = widget.mode.defaults;
    final saved = Store.optionsFor(widget.mode.id);
    for (final o in widget.mode.options) {
      final v = saved[o.key];
      if (v == null) continue;
      if (o.isNumber && v is int && v >= o.min && v <= o.max) _opts[o.key] = v;
      if (!o.isNumber && o.choices.any((c) => c.value == v)) _opts[o.key] = v;
    }
  }

  @override
  void dispose() {
    for (final s in _slots) {
      s.ctl.dispose();
    }
    super.dispose();
  }

  /// Sorgt dafür, dass jede Farbe nur einmal vorkommt und Bot-Regeln gelten.
  void _fixColors() {
    if (_hasBot && _humans != 1) _slots.removeWhere((s) => s.isBot);
    if (_slots.length > 4) _slots.removeRange(4, _slots.length);
    final used = <Color>{};
    for (final s in _slots) {
      if (!C.players.contains(s.color) || used.contains(s.color)) {
        s.color = C.players.firstWhere(
          (c) => !used.contains(c) && !_slots.any((o) => o != s && o.color == c),
          orElse: () => C.players.firstWhere((c) => !used.contains(c)),
        );
      }
      used.add(s.color);
    }
  }

  void _setColor(int i, Color c) {
    setState(() {
      final old = _slots[i].color;
      for (var j = 0; j < _slots.length; j++) {
        if (j != i && _slots[j].color == c) _slots[j].color = old;
      }
      _slots[i].color = c;
    });
  }

  void _addPlayer([String name = '']) {
    if (_slots.length >= 4 || _hasBot) return;
    final free = C.players.firstWhere((c) => !_slots.any((s) => s.color == c));
    setState(() => _slots.add(_Slot(name, free)));
  }

  void _addBot() {
    if (_humans != 1 || _hasBot) return;
    final free = C.players.firstWhere((c) => !_slots.any((s) => s.color == c));
    final o = Store.optionsFor('bot');
    final last = BotLevel.values.where((l) => l.name == o['level']).firstOrNull;
    setState(() => _slots.add(_Slot.bot(o['level'] == 'custom' ? null : last ?? BotLevel.medium, free,
        avg: (o['avg'] as int?) ?? 55, dbl: (o['dbl'] as int?) ?? 20)));
  }

  void _removePlayer(int i) {
    if (_slots.length <= 1 || (!_slots[i].isBot && _humans <= 1)) return;
    setState(() => _slots.removeAt(i).ctl.dispose());
  }

  String _nameOf(int i) {
    final s = _slots[i];
    if (s.isBot) return s.botName;
    final t = s.ctl.text.trim();
    final humanNo = _slots.take(i + 1).where((x) => !x.isBot).length;
    return t.isEmpty ? 'Spieler $humanNo' : t;
  }

  Future<void> _start() async {
    final mode = widget.mode;
    if (_slots.length < mode.minPlayers) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${mode.name} braucht mindestens ${mode.minPlayers} Spieler.')),
      );
      return;
    }
    final names = [for (var i = 0; i < _slots.length; i++) _nameOf(i)];
    if (names.map((n) => n.toLowerCase()).toSet().length != names.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jeder Spieler braucht einen eigenen Namen.')),
      );
      return;
    }
    final players = [
      for (var i = 0; i < _slots.length; i++)
        _slots[i].isBot
            ? GamePlayer(_slots[i].botId, names[i], _slots[i].color.toARGB32())
            : GamePlayer(Store.ensureProfile(names[i]).id, names[i], _slots[i].color.toARGB32()),
    ];
    Store.lastSetup = {
      'players': [
        for (final s in _slots)
          if (s.isBot)
            {'bot': s.level?.name ?? 'custom', 'avg': s.avg, 'dbl': s.dbl, 'color': s.color.toARGB32()}
          else
            {'name': s.ctl.text.trim(), 'color': s.color.toARGB32()}
      ],
    };
    final bot = _slots.where((s) => s.isBot).firstOrNull;
    if (bot != null) Store.saveOptions('bot', {'level': bot.level?.name ?? 'custom', 'avg': bot.avg, 'dbl': bot.dbl});
    Store.saveOptions(mode.id, _opts);

    var start = 0;
    if (_isX01 && players.length > 1) {
      if (_hasBot) {
        start = Random().nextInt(players.length);
      } else {
        final s = await showBullOff(context, players);
        if (s == null || !mounted) return;
        start = s;
      }
    }
    if (!mounted) return;
    final ctl = MatchController(config: GameConfig(mode.id, Map.of(_opts)), players: players, startIndex: start);
    // Als Gast gekoppelt: der Host übernimmt das Match und zeigt es allen.
    if (Link.I.isClient && Link.I.isConnected) LinkCoordinator.startOnHost(ctl);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(controller: ctl)));
    if (mounted) setState(() {});
    widget.onReturn?.call();
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    final inRoster = {for (var i = 0; i < _slots.length; i++) _nameOf(i).toLowerCase()};
    final saved = Store.profiles.where((p) => !inRoster.contains(p.name.toLowerCase())).toList();
    final canAdd = _slots.length < 4 && !_hasBot;
    final canBot = _isX01 && _humans == 1 && !_hasBot;
    final opts = _visibleOptions();

    final content = <Widget>[
      ...widget.header,
      if (!widget.embedded)
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _showRules ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(mode.short, style: TextStyle(color: C.muted, fontSize: 14)),
          ),
          secondChild: GlowCard(
            padding: const EdgeInsets.all(14),
            child: Text(mode.rules, style: TextStyle(color: C.muted2, height: 1.4)),
          ),
        ),
      SectionTitle('Spieler', trailing: _hasBot ? 'Du gegen Bot' : '${_slots.length} / 4'),
      for (var i = 0; i < _slots.length; i++) _playerCard(i),
      if (canAdd || canBot)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              if (canAdd)
                Expanded(
                  flex: 3,
                  child: _addButton(Icons.person_add_alt_1_rounded, 'Spieler hinzufügen', () => _addPlayer()),
                ),
              if (canAdd && canBot) const SizedBox(width: 8),
              if (canBot) Expanded(flex: 2, child: _addButton(Icons.smart_toy_rounded, '+ Bot', _addBot)),
            ],
          ),
        ),
      if (saved.isNotEmpty && canAdd) ...[
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text('Gespeicherte Spieler', style: TextStyle(color: C.muted, fontSize: 13)),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in saved)
              ActionChip(
                label: Text(p.name),
                avatar: const Icon(Icons.add_rounded, size: 18),
                onPressed: () {
                  final empty = _slots.indexWhere((s) => !s.isBot && s.ctl.text.trim().isEmpty);
                  if (empty >= 0) {
                    setState(() => _slots[empty].ctl.text = p.name);
                  } else {
                    _addPlayer(p.name);
                  }
                },
                backgroundColor: C.surface,
                side: BorderSide(color: C.line),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
          ],
        ),
      ],
      if (opts.isNotEmpty) ...[
        const SizedBox(height: 18),
        SectionTitle(_isX01 ? 'Match' : 'Regeln'),
        GlowCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          strength: 0.05,
          child: Column(
            children: [
              for (var k = 0; k < opts.length; k++) ...[
                if (k > 0) Divider(height: 1, color: C.surface3),
                _option(opts[k]),
              ],
            ],
          ),
        ),
      ],
      ...widget.footer,
    ];

    final body = Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, widget.embedded ? 0 : 4, 16, 16),
            children: content,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: PrimaryButton(label: _isX01 ? 'Match starten' : 'Starten', onTap: _start),
        ),
      ],
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text(mode.name),
        actions: [
          IconButton(
            tooltip: 'Regeln',
            icon: Icon(_showRules ? Icons.info_rounded : Icons.info_outline_rounded),
            onPressed: () => setState(() => _showRules = !_showRules),
          ),
        ],
      ),
      body: SafeArea(child: body),
    );
  }

  List<OptionDef> _visibleOptions() => [
        for (final o in widget.mode.options)
          if (!(_isX01 && o.key == 'sets' && _opts['format'] != 'sets')) o
      ];

  Widget _addButton(IconData icon, String label, VoidCallback onTap) => SizedBox(
        height: 52,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon),
          label: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          style: OutlinedButton.styleFrom(
            foregroundColor: C.muted2,
            side: BorderSide(color: C.line, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
      );

  Widget _playerCard(int i) {
    final s = _slots[i];
    final name = _nameOf(i);
    final canRemove = _slots.length > 1 && (s.isBot || _humans > 1);
    return GlowCard(
      tint: s.color,
      strength: 0.10,
      borderAlpha: 0.30,
      radius: 18,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: s.color,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: s.color.withValues(alpha: 0.35), blurRadius: 12)],
                ),
                alignment: Alignment.center,
                child: s.isBot
                    ? const Icon(Icons.smart_toy_rounded, color: C.ink, size: 22)
                    : Text(name.characters.first.toUpperCase(),
                        style: const TextStyle(color: C.ink, fontSize: 19, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: s.isBot
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                          Text(
                              s.level != null
                                  ? '${botProfiles[s.level]!.avgLabel} · Doppelquote ${botProfiles[s.level]!.dblLabel}'
                                  : 'Eigene Stärke',
                              style: TextStyle(color: C.muted, fontSize: 12)),
                        ],
                      )
                    : TextField(
                        controller: s.ctl,
                        maxLength: 14,
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                        decoration: InputDecoration(
                          labelText: 'Spieler ${_slots.take(i + 1).where((x) => !x.isBot).length}',
                          hintText: 'Name eingeben',
                          counterText: '',
                          isDense: true,
                          border: InputBorder.none,
                          labelStyle: TextStyle(color: C.muted),
                        ),
                      ),
              ),
              if (canRemove)
                IconButton(
                  tooltip: '$name entfernen',
                  onPressed: () => _removePlayer(i),
                  icon: Icon(Icons.close_rounded, color: C.muted2),
                  style: IconButton.styleFrom(
                    backgroundColor: C.surface3,
                    minimumSize: const Size(44, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (s.isBot)
            _botEditor(s)
          else
            Row(
              children: [
                const SizedBox(width: 4),
                Text('Farbe', style: TextStyle(color: C.muted, fontSize: 12)),
                const SizedBox(width: 12),
                for (var k = 0; k < C.players.length; k++) _swatch(i, k),
              ],
            ),
        ],
      ),
    );
  }

  /// Stufe wählen oder eigenen Bot mit Average/Doppelquote einstellen.
  Widget _botEditor(_Slot s) {
    final me = _myLevel();
    final reachable = s.level != null || customBotReachable(s.avg, s.dbl);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              for (final l in BotLevel.values) ButtonSegment(value: l.index, label: Text(botProfiles[l]!.name, maxLines: 1)),
              const ButtonSegment(value: -1, label: Text('Eigen', maxLines: 1)),
            ],
            selected: {s.level?.index ?? -1},
            onSelectionChanged: (v) => setState(() => s.level = v.first < 0 ? null : BotLevel.values[v.first]),
            style: segStyle(),
          ),
        ),
        if (s.level == null) ...[
          const SizedBox(height: 8),
          _botSlider('Average', '${s.avg}', s.avg, customAvgMin, customAvgMax, (v) => setState(() => s.avg = v)),
          _botSlider('Doppelquote', '${s.dbl} %', s.dbl, customDblMin, customDblMax, (v) => setState(() => s.dbl = v)),
          if (!reachable)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text('Diese Kombination ist kaum erreichbar, der Bot kommt ihr so nah wie möglich.',
                  style: TextStyle(color: C.muted, fontSize: 12)),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: me == null
                  ? null
                  : () => setState(() {
                        s.avg = me.avg;
                        s.dbl = me.dbl;
                      }),
              icon: const Icon(Icons.person_rounded, size: 18),
              label: Text(me == null
                  ? 'Mein Niveau (noch keine X01-Statistik)'
                  : 'Auf mein Niveau: Ø ${me.avg} · ${me.dbl} %'),
            ),
          ),
        ],
      ],
    );
  }

  /// Average und Doppelquote des menschlichen Spielers aus seiner X01-Statistik.
  ({int avg, int dbl})? _myLevel() {
    final i = _slots.indexWhere((s) => !s.isBot);
    if (i < 0) return null;
    final name = _nameOf(i).toLowerCase();
    final p = Store.profiles.where((p) => p.name.toLowerCase() == name).firstOrNull;
    if (p == null) return null;
    final x = Store.statsFor(p.id).x01;
    if (x.darts < 30 || x.coAttempts == 0) return null;
    return (
      avg: x.average.round().clamp(customAvgMin, customAvgMax),
      dbl: x.coRate.round().clamp(customDblMin, customDblMax),
    );
  }

  Widget _botSlider(String label, String value, int v, int min, int max, ValueChanged<int> onChanged) => Row(
        children: [
          SizedBox(width: 92, child: Text(label, style: TextStyle(color: C.muted, fontSize: 13))),
          Expanded(
            child: Slider(
              value: v.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              label: value,
              onChanged: (x) => onChanged(x.round()),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontFamily: numFont, fontSize: 18, fontWeight: FontWeight.w800)),
          ),
        ],
      );

  Widget _swatch(int i, int k) {
    final c = C.players[k];
    final mine = _slots[i].color == c;
    final owner = _slots.indexWhere((s) => s.color == c);
    final taken = owner >= 0 && owner != i;
    final ownerName = taken ? _nameOf(owner) : '';
    return Semantics(
      button: true,
      selected: mine,
      label: '${C.playerColorNames[k]}${mine ? ', ausgewählt' : taken ? ', mit $ownerName tauschen' : ''}',
      child: InkResponse(
        onTap: () => _setColor(i, c),
        radius: 24,
        child: SizedBox(
          width: 48,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: taken ? c.withValues(alpha: 0.45) : c,
                shape: BoxShape.circle,
                boxShadow: mine
                    ? [
                        BoxShadow(color: C.surface, spreadRadius: 3),
                        BoxShadow(color: C.text, spreadRadius: 5),
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: taken
                  ? Text(ownerName.characters.first.toUpperCase(),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: C.ink))
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  String _labelOf(OptionDef o) {
    if (_isX01 && o.key == 'legs' && _opts['format'] == 'sets') return 'Legs pro Set (First to …)';
    return o.label;
  }

  Widget _option(OptionDef o) {
    if (o.isNumber) {
      final v = _opts[o.key] as int;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NumberStepper(
              label: _labelOf(o),
              value: v,
              min: o.min,
              max: o.max,
              step: o.step,
              onChanged: (x) => setState(() => _opts[o.key] = x),
              onTapValue: o.presets.isEmpty ? null : () => _editNumber(o),
            ),
            if (o.presets.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in o.presets)
                    ChoiceChip(
                      label: Text('$p'),
                      selected: v == p,
                      onSelected: (_) => setState(() => _opts[o.key] = p),
                    ),
                  ActionChip(
                    label: const Text('Eigene …'),
                    onPressed: () => _editNumber(o),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_labelOf(o), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<Object>(
              showSelectedIcon: false,
              segments: [
                for (final c in o.choices) ButtonSegment(value: c.value, label: Text(c.label)),
              ],
              selected: {_opts[o.key] as Object},
              onSelectionChanged: (s) => setState(() => _opts[o.key] = s.first),
              style: segStyle(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editNumber(OptionDef o) async {
    final ctl = TextEditingController(text: '${_opts[o.key]}');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: Text(o.label),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(helperText: '${o.min} bis ${o.max}'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctl.text.trim())),
            child: const Text('Übernehmen'),
          ),
        ],
      ),
    );
    if (v != null) setState(() => _opts[o.key] = v.clamp(o.min, o.max));
  }
}

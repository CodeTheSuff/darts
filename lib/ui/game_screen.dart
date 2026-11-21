import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/callouts.dart';
import '../data/match_controller.dart';
import '../data/match_report.dart';
import '../data/mode_report.dart';
import '../data/sound.dart';
import '../data/storage.dart';
import '../games/engine.dart';

import '../games/minigames.dart';
import '../games/training.dart';
import '../games/x01.dart';
import '../models/dart.dart';
import '../net/link.dart';
import 'celebration.dart';
import 'dartboard.dart';
import 'hit_boards.dart';
import 'match_share.dart';
import 'keypad.dart';
import 'link_coordinator.dart';
import 'stats_table.dart';
import 'theme.dart';

class _Pause {
  _Pause(this.player, this.darts);
  final int player;
  final List<Dart> darts;
}

class _CelebrationData {
  _CelebrationData(this.kind, this.player, this.darts, this.value, {this.label});
  final CelebrationKind kind;
  final int player;
  final List<Dart> darts;
  final int? value;
  final String? label;
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.controller});
  final MatchController controller;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  MatchController get ctl => widget.controller;
  GameEngine get e => ctl.engine;

  _Pause? _pause;
  int _pauseToken = 0;
  _CelebrationData? _celebration;
  Completer<void>? _celebrationDone;
  bool _busyFlag = false;
  bool get _busy => _busyFlag;
  set _busy(bool v) {
    _busyFlag = v;
    // Während Animationen keine Würfe/Undo von gekoppelten Geräten annehmen.
    ctl.inputLocked = v;
  }

  bool _showResult = false;
  int? _statsPlayer;

  /// Gerade angezeigte Leg-Statistik (nach jedem Leg).
  LegReport? _legStats;
  Completer<void>? _legStatsDone;

  /// Match-Statistik vor der Ergebnisseite.
  bool _matchStatsOpen = false;

  MatchReport? get _report => MatchReport.build(
    config: ctl.config,
    players: ctl.players,
    startIndex: ctl.startIndex,
    seed: ctl.seed,
    darts: ctl.darts,
  );

  /// Statistik-Zeilen fürs Teilen-Bild.
  List<StatRow> _shareRows() {
    final r = _report;
    if (r != null) return matchRows(r);
    final m = _modeReport;
    return m == null ? const [] : modeRows(m, e.results());
  }

  /// Statistik der Trainings- und Minispiele.
  ModeReport? get _modeReport => ModeReport.build(
    config: ctl.config,
    players: ctl.players,
    startIndex: ctl.startIndex,
    seed: ctl.seed,
    darts: ctl.darts,
  );

  /// Zeigt die Statistik des gerade beendeten Legs, bis „Weiter“ gedrückt wird
  /// oder ein gekoppeltes Gerät schon den nächsten Dart einträgt.
  Future<void> _showLegStats() async {
    final leg = _report?.lastFinishedLeg;
    if (leg == null || !mounted) return;
    final done = _legStatsDone = Completer<void>();
    setState(() => _legStats = leg);
    // Gekoppelte Geräte dürfen schon weiterspielen – ihr Dart schließt die Statistik hier.
    ctl.inputLocked = false;
    await done.future;
    ctl.inputLocked = _busy;
  }

  void _closeLegStats() {
    if (_legStats == null) return;
    setState(() => _legStats = null);
    _legStatsDone?.complete();
    _legStatsDone = null;
  }

  String? _flash;
  bool _flashBad = false;
  Timer? _flashTimer;
  Timer? _botTimer;
  StreamSubscription<ThrowEvent>? _extSub;
  int _resynced = 0;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().catchError((_) {});
    ctl.addListener(_onChange);
    Link.I.addListener(_onLink);
    _extSub = ctl.externalEvents.listen(_onExternal);
    _resynced = ctl.resynced;
    if (e.finished) _showResult = true;
    LinkCoordinator.gameOpened(ctl);
    _scheduleBot();
  }

  @override
  void dispose() {
    ctl.inputLocked = false;
    LinkCoordinator.gameClosed(ctl);
    _extSub?.cancel();
    Link.I.removeListener(_onLink);
    ctl.removeListener(_onChange);
    _flashTimer?.cancel();
    _botTimer?.cancel();
    WakelockPlus.disable().catchError((_) {});
    if (ctl.decided) ctl.commitStats();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    final pd = _playOnDialog;
    if (pd != null && !e.finished) {
      _playOnDialog = null;
      if (pd.mounted) Navigator.of(pd).pop(true);
    }
    final g = e;
    final d = _soDialog;
    if (d != null && (g is! X01Game || g.singleOutLeg || !g.singleOutOffered || g.finished)) {
      _soDialog = null;
      if (d.mounted) Navigator.of(d).pop();
    }
    setState(() {
      // Kompletter Neuaufbau durch den Host (z. B. Undo auf einem anderen Handy)
      if (ctl.resynced != _resynced) {
        _resynced = ctl.resynced;
        _pauseToken++;
        _pause = null;
        _showResult = e.finished;
      }
      if (!e.finished && _showResult && !_busy) _showResult = false;
    });
    _scheduleBot();
  }

  void _onLink() {
    if (mounted) setState(() {});
  }

  /// Wurf von einem gekoppelten Gerät: wie einen eigenen anzeigen.
  void _onExternal(ThrowEvent ev) {
    if (!mounted) return;
    _handleEvent(ev);
  }

  void _showFlash(String msg, {bool bad = false}) {
    _flashTimer?.cancel();
    setState(() {
      _flash = msg;
      _flashBad = bad;
    });
    _flashTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  Future<void> _celebrate(_CelebrationData data) {
    _celebrationDone = Completer<void>();
    setState(() => _celebration = data);
    return _celebrationDone!.future;
  }

  void _celebrationFinished() {
    setState(() => _celebration = null);
    _celebrationDone?.complete();
    _celebrationDone = null;
  }

  // ---------------------------------------------------------------- Bot

  int get _botDelay => const [1100, 700, 380][Store.botSpeed];

  bool get _botMayThrow =>
      mounted &&
      ctl.botTurn &&
      !_busy &&
      _pause == null &&
      _celebration == null &&
      _legStats == null &&
      !_showResult &&
      _soDialog == null;

  // ---------------------------------------------------------------- Weiterspielen um Plätze

  BuildContext? _playOnDialog;

  /// Fragt nach einem Sieg (bzw. Platz), ob die übrigen um den nächsten Platz weiterspielen.
  /// true = es wird weitergespielt (hier oder auf einem gekoppelten Gerät entschieden).
  Future<bool> _askPlayOn(int place) async {
    final g = e;
    if (g is! X01Game || g.remaining < 2) return false;
    final who = g.players[g.placed[place - 1]].name;
    final yes = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) {
        _playOnDialog = c;
        return AlertDialog(
          icon: Icon(Icons.emoji_events_rounded, color: C.gold, size: 40),
          title: Text(place == 1 ? '$who gewinnt!' : '$who wird $place.'),
          content: Text(
            'Weiterspielen um Platz ${place + 1}? Die übrigen ${g.remaining} Spieler spielen das Leg '
            'mit ihren Restpunkten zu Ende.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Beenden')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Weiterspielen')),
          ],
        );
      },
    );
    _playOnDialog = null;
    if (!mounted) return false;
    final now = e;
    // Hat ein anderes Gerät schon „Weiterspielen“ gewählt?
    if (now is X01Game && !now.finished) return true;
    if (yes == true) {
      ctl.playOn();
      return !e.finished;
    }
    return false;
  }

  // ---------------------------------------------------------------- Single Out

  BuildContext? _soDialog;

  bool get _soVisible {
    final g = e;
    return Store.singleOutOffer && g is X01Game && g.doubleOut && !g.finished && (g.singleOutOffered || g.singleOutLeg);
  }

  /// Nach der Aufnahme-Pause fragen, ob Single Out erlaubt werden soll.
  void _offerSingleOutLater(int player) {
    if (!Store.singleOutOffer || ctl.isBot(player)) return;
    Timer(const Duration(milliseconds: 1300), () => _offerSingleOut(player));
  }

  Future<void> _offerSingleOut(int player) async {
    final g = e;
    if (!mounted || g is! X01Game || g.finished || g.singleOutLeg || !g.singleOutOffered || _soDialog != null) return;
    final name = g.players[player].name;
    final rest = g.scores[player];
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) {
        _soDialog = c;
        return AlertDialog(
          icon: Icon(Icons.swap_horiz_rounded, color: C.accent, size: 36),
          title: const Text('Single Out erlauben?'),
          content: Text(
            '$name steht seit ${X01Game.stuckLimit} Aufnahmen auf $rest.\n\n'
            'Für dieses Leg dürfen dann alle Spieler auch ohne Double finishen. '
            'Ab dem nächsten Leg gilt wieder Double Out.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Nein, weiter Double')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ja, Single Out')),
          ],
        );
      },
    );
    _soDialog = null;
    if (yes == true) {
      ctl.setSingleOut(true);
      Haptics.medium();
      _showFlash('Single Out für dieses Leg');
    }
    _scheduleBot();
  }

  /// Schalter unter der Kopfzeile.
  Widget _singleOutBar() {
    final g = e as X01Game;
    final on = g.singleOutLeg;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: (on ? C.gold : C.surface).withValues(alpha: on ? 0.18 : 1),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _busy ? null : () => ctl.setSingleOut(!on),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
            child: Row(
              children: [
                Icon(Icons.swap_horiz_rounded, color: on ? C.gold : C.muted, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    on ? 'Single Out in diesem Leg' : 'Single Out für dieses Leg erlauben',
                    style: TextStyle(fontWeight: FontWeight.w700, color: on ? C.gold : C.muted2),
                  ),
                ),
                Switch(value: on, onChanged: _busy ? null : (v) => ctl.setSingleOut(v)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- Runde überspringen

  /// Checkout-Training/Catch 40: Einer ist fertig, andere werfen noch.
  bool get _skipVisible {
    final g = e;
    return g is CheckoutChallengeGame && g.canSkipRound && _celebration == null && !_showResult;
  }

  Future<void> _askSkipRound() async {
    final g = e;
    if (g is! CheckoutChallengeGame || !g.canSkipRound) return;
    final open = [for (var i = 0; i < g.n; i++) if (!g.done[i]) g.players[i].name];
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(Icons.skip_next_rounded, color: C.accent, size: 36),
        title: const Text('Runde wirklich überspringen?'),
        content: Text(
          '${open.join(', ')} ${open.length == 1 ? 'hat' : 'haben'} ${g.target} dann nicht geschafft. '
          'Danach geht es für alle mit der nächsten Zahl weiter.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Überspringen')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    _pauseToken++;
    setState(() {
      _pause = null;
      _flash = null;
    });
    ctl.skipRound();
    Haptics.medium();
    _showFlash(e.finished ? 'Runde übersprungen' : 'Runde übersprungen – nächste Zahl');
    if (e.finished) {
      // Letzte Runde übersprungen: Spielende wie nach einem Wurf anzeigen.
      _afterTurn(ThrowEvent(e.results().first.playerIndex)
        ..turnEnded = true
        ..gameOver = true);
      return;
    }
    _scheduleBot();
  }

  Widget _skipBar() => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Material(
          color: C.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _busy ? null : _askSkipRound,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.skip_next_rounded, color: C.muted, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Runde überspringen',
                      style: TextStyle(fontWeight: FontWeight.w700, color: C.muted2),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: C.muted, size: 20),
                ],
              ),
            ),
          ),
        ),
      );

  void _scheduleBot() {
    // In gekoppelten Spielen wirft der Bot nur auf dem Host.
    if (ctl.remote || !ctl.botTurn || (_botTimer?.isActive ?? false)) return;
    _botTimer = Timer(Duration(milliseconds: _botDelay), _botStep);
  }

  void _botStep() {
    if (!_botMayThrow) {
      // Später erneut versuchen (z. B. nach der Pause/Animation).
      if (mounted && ctl.botTurn && !_showResult) {
        _botTimer = Timer(const Duration(milliseconds: 250), _botStep);
      }
      return;
    }
    _throw(ctl.nextBotDart(), fromBot: true);
    if (ctl.botTurn && _pause == null) _scheduleBot();
  }

  void _onDart(int field, int mult) {
    if (ctl.botTurn) return;
    _throw(Dart.thrown(field, mult));
  }

  void _throw(Dart d, {bool fromBot = false}) {
    if (_busy || e.finished) return;
    _handleEvent(ctl.throwDart(d));
  }

  void _handleEvent(ThrowEvent ev) {
    if (_legStats != null && !ev.control) _closeLegStats();
    if (ev.control) {
      setState(() {});
      return;
    }
    if (ev.offerSingleOut != null) _offerSingleOutLater(ev.offerSingleOut!);
    if (_pause != null) {
      _pauseToken++;
      setState(() => _pause = null);
    }
    Sound.play('thunk', volume: 0.7);
    Callouts.onThrow(ev, e);
    if (ev.message != null) _showFlash(ev.message!, bad: ev.bust);
    if (ev.bust) Sound.play('bust', volume: 0.8);
    if (ev.turnEnded) _afterTurn(ev);
  }

  Future<void> _afterTurn(ThrowEvent ev) async {
    final token = ++_pauseToken;
    final needsShow = ev.celebration != null || ev.gameOver;
    setState(() {
      _pause = _Pause(ev.playerIndex, ev.turnDarts);
      _busy = needsShow;
    });

    if (!needsShow) {
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      // Inzwischen Rückgängig oder neue Aufnahme? Dann nichts mehr ansagen.
      if (!mounted || token != _pauseToken) return;
      setState(() => _pause = null);
      _scheduleBot();
      return;
    }

    // Kurz den letzten Pfeil auf der kleinen Scheibe zeigen, dann die große Animation
    await Future<void>.delayed(const Duration(milliseconds: 550));
    if (!mounted) return;
    final p = ev.playerIndex;
    final show = Store.celebrations;
    if (ev.celebration != null) {
      final kind = kindOf(ev.celebration!);
      String? label = ev.celebrationLabel;
      if (kind == CelebrationKind.legWon && e.legsToWin == null) label = 'GESCHAFFT!';
      final g = e;
      final placing = g is X01Game && g.playingOn;
      final skipLeg = kind == CelebrationKind.legWon && ev.gameOver && !placing;
      if (!skipLeg) {
        if (show) {
          await _celebrate(_CelebrationData(kind, p, ev.turnDarts, ev.celebrationValue, label: label));
        } else {
          final snd = celebrationSound(kind);
          if (snd != null) Sound.play(snd);
          await Future<void>.delayed(const Duration(milliseconds: 700));
        }
      }
      // Leg beendet (Match läuft weiter): Leg-Statistik
      final legOver = kind == CelebrationKind.legWon || kind == CelebrationKind.highFinish;
      if (legOver && !ev.gameOver && e is X01Game && mounted) await _showLegStats();
    }
    if (!mounted) return;
    if (ev.gameOver) {
      final res = e.results();
      final winner = res.first;
      final solo = e.n == 1;
      final g = e;
      final placing = g is X01Game && g.playingOn;
      if (placing) {
        // Platz beim Weiterspielen vergeben – keine zweite Sieger-Animation
      } else if (show) {
        await _celebrate(
          _CelebrationData(
            CelebrationKind.match,
            winner.playerIndex,
            winner.playerIndex == p ? ev.turnDarts : const [],
            null,
            label: solo ? 'GESCHAFFT' : (e.legsToWin != null ? 'MATCH GEWONNEN' : 'SIEG'),
          ),
        );
      } else if (!Callouts.replacesCheers) {
        Sound.play('win');
      }
      if (!mounted) return;
      // Ab 3 Spielern: um den nächsten Platz weiterspielen?
      if (ev.offerPlayOn != null && await _askPlayOn(ev.offerPlayOn!)) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _pause = null;
          _showResult = false;
        });
        _scheduleBot();
        return;
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _pause = null;
        _showResult = true;
        _matchStatsOpen = true;
      });
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (mounted && token == _pauseToken) {
      setState(() {
        _pause = null;
        _busy = false;
      });
    } else if (mounted) {
      setState(() => _busy = false);
    }
    _scheduleBot();
  }

  void _undo() {
    if (_busy) return;
    _botTimer?.cancel();
    _pauseToken++;
    setState(() {
      _pause = null;
      _showResult = false;
      _flash = null;
    });
    ctl.undo();
    _scheduleBot();
  }

  void _rematch() {
    ctl.commitStats();
    final next = ctl.rematch();
    if (ctl.remote) LinkCoordinator.startOnHost(next);
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => GameScreen(controller: next)));
  }

  Color _color(int i) => Color(e.players[i].color);

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final shown = _pause?.player ?? e.cur;
    final darts = _pause?.darts ?? e.visibleTurn;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: Column(
                children: [
                  _header(),
                  if (_soVisible) _singleOutBar(),
                  if (_skipVisible) _skipBar(),
                  const SizedBox(height: 8),
                  _activeCard(shown, darts),
                  const SizedBox(height: 8),
                  if (e is CricketGame)
                    _CricketTable(game: e as CricketGame, current: shown)
                  else if (e.n > 1)
                    _others(shown),
                  const SizedBox(height: 8),
                  _turnRow(darts),
                  const SizedBox(height: 8),
                  _hintBar(),
                  const SizedBox(height: 8),
                  Expanded(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 250),
                      opacity: ctl.botTurn ? 0.45 : 1,
                      child: Keypad(
                        key: ValueKey(e.input.kind),
                        spec: e.input,
                        color: _color(e.cur),
                        onDart: _onDart,
                        onUndo: _undo,
                        canUndo: ctl.canUndo && !_busy,
                        enabled: !_busy && !e.finished && !ctl.botTurn,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showResult) _matchStatsOpen ? _matchStatsPanel() : _resultPanel(),
          if (_legStats != null) _legStatsPanel(_legStats!),
          if (_celebration != null)
            Positioned.fill(
              child: CelebrationOverlay(
                key: ValueKey(_celebration),
                kind: _celebration!.kind,
                name: e.players[_celebration!.player].name,
                color: _color(_celebration!.player),
                darts: _celebration!.darts,
                value: _celebration!.value,
                label: _celebration!.label,
                onDone: _celebrationFinished,
              ),
            ),
        ],
      ),
    );
  }

  Widget _header() {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          _iconBtn(Icons.arrow_back_rounded, 'Zurück', () => Navigator.of(context).maybePop()),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    e.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: C.muted),
                  ),
                ],
              ),
            ),
          ),
          if (Link.I.role != LinkRole.none)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Tooltip(
                message: Link.I.isConnected ? 'Gekoppelt · ${Link.I.peerCount + 1} Geräte' : Link.I.status,
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: (Link.I.isConnected ? C.dbl : C.danger).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Link.I.isConnected ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded,
                        size: 16,
                        color: Link.I.isConnected ? C.dbl : C.danger,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${Link.I.isConnected ? Link.I.peerCount + 1 : '!'}',
                        style: TextStyle(fontWeight: FontWeight.w800, color: Link.I.isConnected ? C.dbl : C.danger),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          _iconBtn(
            Store.soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            Store.soundOn ? 'Sound aus' : 'Sound an',
            () {
              setState(() => Store.soundOn = !Store.soundOn);
            },
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, String label, VoidCallback onTap) => SizedBox(
    width: 44,
    height: 44,
    child: Key3(
      semantics: label,
      onTap: onTap,
      color: C.surface,
      borderColor: Colors.transparent,
      child: Icon(icon, size: 20, color: C.text),
    ),
  );

  Widget _dots(int total, int filled, Color color, {double size = 9, double gap = 4}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < total && i < 9; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: size,
          height: size,
          margin: EdgeInsets.only(right: gap),
          decoration: BoxDecoration(
            color: i < filled ? color : C.line,
            shape: BoxShape.circle,
            boxShadow: i < filled ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)] : null,
          ),
        ),
    ],
  );

  /// Legs bzw. Sets + Legs eines Spielers als Punktreihe.
  Widget _progress(int p, {bool small = false}) {
    final legs = e.legsToWin;
    if (legs == null) return const SizedBox.shrink();
    final color = _color(p);
    final sz = small ? 6.0 : 9.0;
    final label = TextStyle(fontSize: small ? 9 : 10, color: C.muted, fontWeight: FontWeight.w800, letterSpacing: 0.6);
    final sets = e.setsToWin;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (sets != null) ...[
          if (!small) Text('SETS ', style: label),
          _dots(sets, e.setsOf(p), color, size: sz + 1, gap: small ? 3 : 4),
          SizedBox(width: small ? 4 : 8),
          if (!small) Text('LEGS ', style: label),
        ],
        _dots(
          legs,
          e.legsOf(p),
          color.withValues(alpha: sets != null ? 0.75 : 1),
          size: sz,
          gap: small ? 3 : 4,
        ),
      ],
    );
  }

  Widget _scoreText(String value, double size) {
    final style = TextStyle(
      fontSize: size,
      fontFamily: numFont,
      fontWeight: FontWeight.w700,
      letterSpacing: -1,
      height: 1.0,
      color: C.text,
      fontFeatures: tabular,
    );
    final n = int.tryParse(value);
    if (n == null) return Text(value, style: style);
    return AnimatedNumber(n, style: style);
  }

  Widget _activeCard(int p, List<Dart> darts) {
    final color = _color(p);
    final value = _pause == null ? e.activeValue() : e.mainValue(p);
    final boardSize = min(146.0, MediaQuery.sizeOf(context).width * 0.37);
    final isBot = ctl.isBot(p);
    // Bei voller Zahleneingabe keine Scheibe: rechts stehen Ø und letzte Aufnahme.
    final compact = e.input.kind == InputKind.full;
    final stat = e.cardStat(p);
    final sub = e.subLine(p);

    final nameRow = Row(
      children: [
        if (isBot) ...[Icon(Icons.smart_toy_rounded, size: 18, color: color), const SizedBox(width: 6)],
        Flexible(
          child: Text(
            e.players[p].name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            isBot && _pause == null ? 'WIRFT …' : 'AM WURF',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: color),
          ),
        ),
      ],
    );

    final Widget body;
    if (compact) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                nameRow,
                SizedBox(
                  height: 68,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomLeft,
                    child: _scoreText(value, 76),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (stat != null)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        stat,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          color: C.text,
                          fontFeatures: tabular,
                        ),
                      ),
                    )
                  else if (sub != null)
                    Text(
                      sub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, color: C.muted2, fontWeight: FontWeight.w700),
                    ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (e.legsToWin != null) ...[_progress(p), const SizedBox(width: 2)],
                        Text(
                          'Letzte ${e.lastLine(p)}',
                          maxLines: 1,
                          style: TextStyle(fontSize: 17, color: C.muted, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    } else {
      body = Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                nameRow,
                SizedBox(
                  height: 86,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: _scoreText(value, 92),
                  ),
                ),
                if (sub != null)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w600),
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (e.legsToWin != null) ...[
                      Flexible(
                        child: FittedBox(fit: BoxFit.scaleDown, child: _progress(p)),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        'Letzte ${e.lastLine(p)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: C.muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Dartboard(size: boardSize, darts: darts, color: color, targets: _pause == null ? e.targets : const []),
        ],
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: compact ? const EdgeInsets.fromLTRB(16, 12, 14, 10) : const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.alphaBlend(color.withValues(alpha: 0.16), C.surface), C.surface],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color, width: 2),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 28)],
      ),
      child: body,
    );
  }

  Widget _others(int shown) {
    final idx = [for (var k = 1; k < e.n; k++) (shown + k) % e.n];
    // Bis 3 Mitspieler nebeneinander, ab 4 als scrollbare Reihe mit fester Breite.
    if (idx.length <= 3) {
      return Row(
        children: [for (final i in idx) Expanded(child: _otherCard(i, last: i == idx.last))],
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [for (final i in idx) SizedBox(width: 124, child: _otherCard(i, last: i == idx.last))],
      ),
    );
  }

  Widget _otherCard(int i, {required bool last}) {
    return Container(
      margin: EdgeInsets.only(right: last ? 0 : 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        gradient: C.cardGradient(_color(i), 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color.alphaBlend(_color(i).withValues(alpha: 0.18), C.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ctl.isBot(i)
                  ? Icon(Icons.smart_toy_rounded, size: 12, color: _color(i))
                  : Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: _color(i), shape: BoxShape.circle),
                    ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  e.players[i].name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: C.muted2, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: _scoreText(e.mainValue(i), 30)),
          Row(
            children: [
              Expanded(
                child: Text(
                  e.legsToWin != null ? 'Letzte ${e.lastLine(i)}' : (e.subLine(i) ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: C.muted),
                ),
              ),
              if (e.legsToWin != null) _progress(i, small: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _turnRow(List<Dart> darts) {
    Widget slot(int i) {
      final d = i < darts.length ? darts[i] : null;
      return Expanded(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(right: 8),
          height: 46,
          decoration: BoxDecoration(
            color: d != null ? C.surface3 : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: d != null ? C.surface3 : C.line, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            d?.label ?? '–',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: d != null ? C.text : C.muted,
              fontFeatures: tabular,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        slot(0),
        slot(1),
        slot(2),
        if (e.showTurnSum)
          Container(
            width: 72,
            height: 46,
            decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(14)),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('SUMME', style: TextStyle(fontSize: 10, color: C.muted, letterSpacing: 0.6)),
                  Text(
                    '${sumOf(darts)}',
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, fontFeatures: tabular),
                  ),
                ],
              ),
            ),
          )
        else
          const SizedBox(width: 0),
      ],
    );
  }

  /// Farbe eines Checkout-Felds: Double (und Bull) grün, Triple orange, Single weiß.
  Color _segColor(String seg) {
    if (seg == 'Bull' || seg.startsWith('D')) return C.dbl;
    if (seg.startsWith('T')) return C.trp;
    return C.text;
  }

  Widget _hintBar() {
    final color = _color(_pause?.player ?? e.cur);
    var bg = C.surface;
    var border = C.line;
    Widget child;
    if (_flash != null) {
      final tone = _flashBad ? C.danger : color;
      bg = Color.alphaBlend(tone.withValues(alpha: 0.14), C.surface);
      border = tone.withValues(alpha: 0.5);
      child = Text(
        _flash!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: _flashBad ? const Color(0xFFFF9494) : color,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      );
    } else {
      var h = _pause == null ? e.hint : null;
      if (h != null && (h.label == 'Checkout' || h.label == 'Stellen') && !Store.checkoutHint) h = null;
      if (h == null) {
        child = Text(
          _pause != null ? 'Nächster Spieler …' : (ctl.botTurn ? 'Bot ist am Wurf …' : ' '),
          style: TextStyle(color: C.muted, fontWeight: FontWeight.w600, fontSize: 15),
        );
      } else if (h.label == 'Checkout') {
        // Ein gleich großer Bereich pro Dart des Finish-Wegs.
        final segs = h.text.split(' · ');
        child = Row(
          children: [
            for (var i = 0; i < segs.length; i++) ...[
              if (i > 0) Container(width: 1, height: 26, color: C.line),
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      segs[i],
                      maxLines: 1,
                      style: TextStyle(
                        color: _segColor(segs[i]),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        fontFeatures: tabular,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      } else {
        final fg = h.strong ? color : C.muted;
        if (h.strong) bg = Color.alphaBlend(color.withValues(alpha: 0.12), C.surface);
        child = Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (h.label != null) ...[
              Text(
                h.label!.toUpperCase(),
                style: TextStyle(
                  color: fg.withValues(alpha: 0.85),
                  fontSize: 11,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Text(
                h.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: h.strong ? fg : (h.label == null ? C.muted : C.muted2),
                  fontSize: h.strong ? 17 : 15,
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabular,
                ),
              ),
            ),
          ],
        );
      }
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 1.5),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  /// Trefferbild des Matches: gewählter Spieler, Felder eingefärbt + Anzahl im Kreis.
  Widget _hitSection(List<PlayerResult> res) {
    final order = [for (final r in res) r.playerIndex];
    final sel = order.contains(_statsPlayer) ? _statsPlayer! : order.first;
    final hits = e.hits[sel];
    final misses = hits['Miss'] ?? 0;
    final total = e.dartCount[sel];
    final rate = total == 0 ? 0 : ((total - misses) / total * 100).round();
    final col = _color(sel);
    final top = (hits.entries.where((x) => x.key != 'Miss').toList()..sort((a, b) => b.value.compareTo(a.value)))
        .take(3)
        .map(
          (x) =>
              '${x.key == '50'
                  ? 'Bull'
                  : x.key.startsWith('S')
                  ? x.key.substring(1)
                  : x.key} ×${x.value}',
        )
        .join('  ·  ');
    final boardSize = min(MediaQuery.sizeOf(context).width - 72, 340.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'TREFFERBILD',
              style: TextStyle(color: C.muted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1),
            ),
          ),
          const SizedBox(height: 10),
          if (order.length > 1)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final i in order)
                  ChoiceChip(
                    selected: i == sel,
                    onSelected: (_) => setState(() => _statsPlayer = i),
                    showCheckmark: false,
                    avatar: CircleAvatar(backgroundColor: _color(i), radius: 6),
                    label: Text(e.players[i].name),
                    selectedColor: _color(i).withValues(alpha: 0.22),
                    side: BorderSide(color: i == sel ? _color(i) : C.line),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Dartboard(size: boardSize, heat: hits, color: col, showCounts: true),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [_miniStat('Darts', '$total'), _miniStat('Getroffen', '$rate %'), _miniStat('Miss', '$misses')],
          ),
          if (top.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Am häufigsten: $top',
              textAlign: TextAlign.center,
              style: TextStyle(color: C.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, fontFeatures: tabular),
      ),
      Text(label, style: TextStyle(color: C.muted, fontSize: 12)),
    ],
  );

  /// Gemeinsamer Rahmen der Statistik-Seiten.
  Widget _statsPage({
    required String eyebrow,
    required String title,
    required Color color,
    required List<Widget> children,
    required String button,
    required VoidCallback onButton,
    Widget? side,
  }) {
    // Breite Bildschirme (Tablet quer): Tabellen links, Trefferbilder rechts daneben.
    final wide = side != null && MediaQuery.sizeOf(context).width >= 1000;
    return Positioned.fill(
      child: Container(
        color: C.bg,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  eyebrow,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 2),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: SingleChildScrollView(child: side)),
                          ],
                        )
                      : SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [...children, ?side],
                          ),
                        ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 56,
                  child: Key3(
                    semantics: button,
                    onTap: onButton,
                    gradient: C.accentGradient,
                    borderColor: Colors.transparent,
                    radius: 16,
                    child: Text(
                      button,
                      style: TextStyle(color: C.onAccent, fontWeight: FontWeight.w800, fontSize: 17),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(String title, Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
    decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(18)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(color: C.muted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1),
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );

  /// Statistik des gerade beendeten Legs.
  Widget _legStatsPanel(LegReport leg) {
    final w = leg.winner!;
    final ws = leg.players[w];
    return _statsPage(
      eyebrow: 'LEG ${leg.number} BEENDET',
      title: '${e.players[w].name} checkt ${ws.finish} mit ${ws.darts} Darts',
      color: _color(w),
      children: [
        _card('LEG-STATISTIK', StatsTable(players: e.players, rows: legRows(leg))),
      ],
      side: _card('TREFFERBILD DIESES LEGS',
          HitBoards(players: e.players, hits: [for (final p in leg.players) p.hits])),
      button: 'Weiter',
      onButton: _closeLegStats,
    );
  }

  /// Statistik des ganzen Matches (vor der Ergebnisseite).
  Widget _matchStatsPanel() {
    final r = _report;
    final res = e.results();
    final order = [for (final x in res) x.playerIndex];
    if (r == null) {
      final m = _modeReport;
      if (m == null) return _resultPanel();
      final w = res.first.playerIndex;
      return _statsPage(
        eyebrow: 'STATISTIK',
        title: e.n == 1 ? '${e.players[w].name} · ${res.first.value}' : '${e.players[w].name} gewinnt',
        color: C.gold,
        children: [
          _card(e.n == 1 ? 'WERTE' : 'VERGLEICH', StatsTable(players: e.players, rows: modeRows(m, res))),
        ],
        side: _card('TREFFERBILD', HitBoards(players: e.players, hits: e.hits, order: order)),
        button: 'Fortsetzen',
        onButton: () => setState(() => _matchStatsOpen = false),
      );
    }
    final w = res.first.playerIndex;
    final legsLine = e.n == 2 && e.legsToWin != null ? '  ${e.legsOf(w)} : ${e.legsOf(1 - w)}' : '';
    return _statsPage(
      eyebrow: 'MATCHSTATISTIK',
      title: '${e.players[w].name} gewinnt$legsLine',
      color: C.gold,
      children: [
        _card('VERGLEICH', StatsTable(players: e.players, rows: matchRows(r))),
        if (r.legs.length > 1) _card('LEGS', LegList(report: r)),
      ],
      side: _card('TREFFERBILD', HitBoards(players: e.players, hits: e.hits, order: order)),
      button: 'Fortsetzen',
      onButton: () => setState(() => _matchStatsOpen = false),
    );
  }

  Widget _resultPanel() {
    final res = e.results();
    final winner = res.first;
    final wColor = _color(winner.playerIndex);
    return Positioned.fill(
      child: Container(
        color: C.overlay,
        child: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                child: Column(
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: wColor,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: wColor.withValues(alpha: 0.5), blurRadius: 30)],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        e.players[winner.playerIndex].name.characters.first.toUpperCase(),
                        style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: C.ink),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      e.n == 1 ? 'GESCHAFFT' : 'GEWONNEN',
                      style: TextStyle(color: wColor, fontWeight: FontWeight.w800, letterSpacing: 1.5),
                    ),
                    Text(
                      e.players[winner.playerIndex].name,
                      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800),
                    ),
                    Text(e.title, style: TextStyle(color: C.muted)),
                    const SizedBox(height: 18),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final r in res)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: C.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: r.rank == 1 ? Border.all(color: _color(r.playerIndex), width: 1.5) : null,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 28,
                                    child: Text(
                                      '${r.rank}.',
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: C.muted2),
                                    ),
                                  ),
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(color: _color(r.playerIndex), shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e.players[r.playerIndex].name,
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                        ),
                                        if (r.detail.isNotEmpty)
                                          Text(r.detail, style: TextStyle(fontSize: 12, color: C.muted)),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    r.value,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      fontFeatures: tabular,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          TextButton.icon(
                              onPressed: () => setState(() => _matchStatsOpen = true),
                              icon: const Icon(Icons.query_stats_rounded),
                              label: Text(
                                e is X01Game ? 'Matchstatistik ansehen' : 'Statistik ansehen',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          const SizedBox(height: 10),
                          _hitSection(res),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: Key3(
                              semantics: 'Letzten Pfeil rückgängig machen',
                              onTap: _undo,
                              enabled: ctl.canUndo,
                              color: C.surface2,
                              borderColor: C.line,
                              radius: 16,
                              child: const Text('Undo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 52,
                            child: Key3(
                              semantics: ctl.isTournament ? 'Zum Turnier' : 'Revanche',
                              onTap: ctl.isTournament
                                  ? () {
                                      ctl.commitStats();
                                      Navigator.of(context).pop();
                                    }
                                  : _rematch,
                              gradient: C.accentGradient,
                              borderColor: Colors.transparent,
                              radius: 16,
                              child: Text(
                                ctl.isTournament ? 'Zum Turnier' : 'Revanche',
                                style: TextStyle(color: C.onAccent, fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!ctl.isTournament) const SizedBox(height: 8),
                    if (!ctl.isTournament)
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: Key3(
                                semantics: 'Neues Setup',
                                onTap: () => Navigator.of(context).pop(),
                                color: C.surface2,
                                borderColor: C.line,
                                radius: 16,
                                child: const Text('Neues Setup', style: TextStyle(fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: Key3(
                                semantics: 'Zur Startseite',
                                onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
                                color: C.surface2,
                                borderColor: C.line,
                                radius: 16,
                                child: const Text('Startseite', style: TextStyle(fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: IconButton(
                  tooltip: 'Ergebnis teilen',
                  icon: Icon(Icons.ios_share_rounded, color: C.text),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MatchShareScreen(
                        engine: e,
                        rows: _shareRows(),
                        date: DateTime.now(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kompakte Cricket-Tabelle: Markierungen pro Spieler und Zahl.
class _CricketTable extends StatelessWidget {
  const _CricketTable({required this.game, required this.current});
  final CricketGame game;
  final int current;

  String _mark(int m) => switch (m) {
    0 => '',
    1 => '/',
    2 => '✕',
    _ => '⊗',
  };

  @override
  Widget build(BuildContext context) {
    final n = game.n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 44),
              for (var i = 0; i < n; i++)
                Expanded(
                  child: Text(
                    game.players[i].name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: i == current ? FontWeight.w800 : FontWeight.w600,
                      color: Color(game.players[i].color),
                    ),
                  ),
                ),
            ],
          ),
          for (var k = 0; k < CricketGame.numbers.length; k++)
            SizedBox(
              height: 17,
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      CricketGame.numbers[k] == 25 ? 'Bull' : '${CricketGame.numbers[k]}',
                      style: TextStyle(fontSize: 12, color: C.muted2, fontWeight: FontWeight.w700),
                    ),
                  ),
                  for (var i = 0; i < n; i++)
                    Expanded(
                      child: Text(
                        _mark(game.marks[i][k]),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          color: game.marks[i][k] >= 3 ? Color(game.players[i].color) : C.text,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

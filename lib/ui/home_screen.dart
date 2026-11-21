import 'package:material_ui/material_ui.dart';

import '../data/match_controller.dart';
import '../data/storage.dart';
import '../data/tournament_store.dart';
import '../games/catalog.dart';
import '../net/link.dart';
import '../platform/web_notices.dart';
import 'game_screen.dart';
import 'link_coordinator.dart';
import 'about_screen.dart';
import 'coach_overlay.dart';
import 'tutorial/tutorial_screen.dart';
import 'link_screen.dart';
import 'logo.dart';
import 'settings_screen.dart';
import 'setup_screen.dart';
import 'stats_screen.dart';
import 'theme.dart';
import 'tournament_screens.dart';

IconData modeIcon(String id) => switch (id) {
      'x01' => Icons.adjust_rounded,
      'atc' => Icons.schedule_rounded,
      'bobs27' => Icons.looks_two_rounded,
      'checkout' => Icons.flag_rounded,
      '121' => Icons.trending_up_rounded,
      'scoring' => Icons.speed_rounded,
      'halveit' => Icons.call_split_rounded,
      'cricket' => Icons.grid_on_rounded,
      'killer' => Icons.whatshot_rounded,
      'shanghai' => Icons.auto_awesome_rounded,
      'highscore' => Icons.emoji_events_rounded,
      'catch40' => Icons.timer_rounded,
      _ => Icons.adjust_rounded,
    };

Color categoryColor(ModeCategory c) => switch (c) {
      ModeCategory.game => C.accent,
      ModeCategory.training => C.dbl,
      ModeCategory.mini => C.players[3],
    };

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  static const _tabs = [
    (ModeCategory.game, 'Spiel', 'Das klassische Match'),
    (ModeCategory.training, 'Training', 'Allein oder mit bis zu 4 Spielern'),
    (ModeCategory.mini, 'Minispiele', 'Für die Runde mit Freunden'),
  ];

  @override
  void initState() {
    super.initState();
    MatchController.onTournamentMatchDone ??= TournamentStore.onMatchDone;
    LinkCoordinator.init();
    Link.I.addListener(_onLink);
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterOpen());
  }

  // ---------------------------------------------------------------- Einführung

  final _kX01 = GlobalKey();
  final _kTour = GlobalKey();
  final _kNav = GlobalKey();
  final _kLink = GlobalKey();
  final _kStats = GlobalKey();
  final _kSettings = GlobalKey();
  bool _coach = false;

  /// Nach dem Start bzw. nach Rückkehr: Einführung oder „Was ist neu“.
  Future<void> _afterOpen() async {
    if (!mounted) return;
    if (!Store.onboarded) {
      setState(() {
        _tab = 0;
        _coach = true;
      });
      return;
    }
    await maybeShowWhatsNew(context);
  }

  void _coachDone() {
    Store.onboarded = true;
    Store.seenVersion = appVersion;
    setState(() => _coach = false);
  }

  Rect? _navPart(int i) {
    final r = rectOf(_kNav);
    if (r == null) return null;
    final w = r.width / 3;
    return Rect.fromLTWH(r.left + w * i + 6, r.top + 6, w - 12, r.height - 12);
  }

  List<CoachStep> get _steps => [
        CoachStep(
          target: () => rectOf(_kX01),
          icon: Icons.adjust_rounded,
          title: 'X01',
          text: 'Das klassische Match: 301, 501 oder 701, mit Legs oder Sets – auch gegen Bots.',
        ),
        CoachStep(
          target: () => rectOf(_kTour),
          icon: Icons.emoji_events_rounded,
          title: 'Turnier',
          text: 'Turniere mit 3 bis 32 Spielern: K.o., Doppel-K.o., Gruppen oder Liga.',
        ),
        CoachStep(
          target: () => _navPart(1),
          icon: Icons.fitness_center_rounded,
          title: 'Training',
          text: 'Around the Clock, Bob’s 27, Checkout-Training und mehr – allein oder zu mehreren.',
        ),
        CoachStep(
          target: () => _navPart(2),
          icon: Icons.celebration_rounded,
          title: 'Minispiele',
          text: 'Cricket, Killer, Shanghai und High Score für die Runde mit Freunden.',
        ),
        CoachStep(
          target: () => rectOf(_kLink),
          icon: Icons.wifi_tethering_rounded,
          title: 'Handys koppeln',
          text: 'Mehrere Handys spielen zusammen, ein Tablet wird zur Anzeige an der Wand. Im Turnier spielt jedes Handy auf seiner eigenen Scheibe.',
        ),
        CoachStep(
          target: () => rectOf(_kStats),
          icon: Icons.insights_rounded,
          title: 'Statistik',
          text: 'Averages, Verlauf, Match-Historie, Direktvergleich, Doppel-Analyse und Erfolge.',
        ),
        CoachStep(
          target: () => rectOf(_kSettings),
          icon: Icons.settings_rounded,
          title: 'Einstellungen',
          text: 'Design, Ton, Ansagen, Vibration und deine Daten. Diesen Rundgang kannst du hier erneut starten.',
        ),
        CoachStep(
          target: () => rectOf(_kSettings),
          icon: Icons.menu_book_rounded,
          title: 'Großes Tutorial',
          text: 'Es gibt ein ausführliches Tutorial, das jede Funktion erklärt – vom Eintragen bis zu Turnieren auf mehreren Scheiben. '
              'Du findest es jederzeit in den Einstellungen unter „Tutorial“.',
          actionLabel: 'Jetzt ansehen',
          onAction: () => _open(const TutorialScreen()),
        ),
      ];

  @override
  void dispose() {
    Link.I.removeListener(_onLink);
    super.dispose();
  }

  void _onLink() {
    if (mounted) setState(() {});
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() {});
    if (mounted && !Store.onboarded) _afterOpen();
  }

  @override
  Widget build(BuildContext context) {
    final active = Store.activeMatch;
    final resume = active == null ? null : MatchController.fromJson(active);
    final resumeCard =
        resume != null && !resume.engine.finished && !resume.isTournament ? _resumeCard(resume) : null;

    final scaffold = Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            const DartsLogo(size: 34),
            const SizedBox(width: 10),
            const Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Darts', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 24)),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: _kLink,
            tooltip: 'Handys koppeln',
            icon: Badge(
              isLabelVisible: Link.I.role != LinkRole.none,
              backgroundColor: Link.I.isConnected ? C.dbl : C.danger,
              label: Text('${Link.I.isConnected ? Link.I.peerCount + 1 : '!'}'),
              child: Icon(Link.I.role == LinkRole.none || Link.I.isConnected
                  ? Icons.wifi_tethering_rounded
                  : Icons.wifi_tethering_off_rounded),
            ),
            onPressed: () => _open(const LinkScreen()),
          ),
          IconButton(
            key: _kStats,
            tooltip: 'Statistik',
            icon: const Icon(Icons.insights_rounded),
            onPressed: () => _open(const StatsScreen()),
          ),
          IconButton(
            key: _kSettings,
            tooltip: 'Einstellungen',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => _open(const SettingsScreen()),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _gameTab(resumeCard),
          _modeList(1, resumeCard),
          _modeList(2, resumeCard),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        key: _kNav,
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.adjust_rounded), label: 'Spiel'),
          NavigationDestination(icon: Icon(Icons.fitness_center_rounded), label: 'Training'),
          NavigationDestination(icon: Icon(Icons.celebration_rounded), label: 'Minispiele'),
        ],
      ),
    );
    return Stack(children: [scaffold, if (_coach) CoachOverlay(steps: _steps, onDone: _coachDone)]);
  }

  Widget _tabTitle(int i) {
    final (_, title, subtitle) = _tabs[i];
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.1)),
          Text(subtitle, style: TextStyle(color: C.muted, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _modeList(int tab, Widget? resumeCard) {
    final cat = _tabs[tab].$1;
    final list = modes.where((m) => m.category == cat).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        ?resumeCard,
        _tabTitle(tab),
        for (final m in list) _modeCard(m),
      ],
    );
  }

  Widget _gameTab(Widget? resumeCard) {
    final running = TournamentStore.running.length;
    final done = TournamentStore.history.length;
    final tInfo = [
      if (running > 0) '$running läuft',
      if (done > 0) '$done beendet',
    ].join(' · ');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        ?resumeCard,
        _tabTitle(0),
        // Nur im Browser: „Zum Home-Bildschirm“ (iPhone) und Backup-Erinnerung
        const WebNotices(),
        KeyedSubtree(key: _kX01, child: _modeCard(modeById('x01'))),
        GlowCard(
          key: _kTour,
          tint: C.gold,
          strength: running > 0 ? 0.10 : 0.06,
          borderAlpha: running > 0 ? 0.35 : 0.18,
          onTap: () => _open(const TournamentHubScreen()),
          child: Row(
            children: [
              _iconBox(Icons.emoji_events_rounded, C.gold),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Turnier', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('K.o., Doppel-K.o., Gruppen oder Liga', style: TextStyle(color: C.muted, fontSize: 13)),
                    const SizedBox(height: 6),
                    Text(tInfo.isEmpty ? '3–32 Spieler' : tInfo,
                        style: TextStyle(color: C.gold, fontSize: 11, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: C.muted),
            ],
          ),
        ),
      ],
    );
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

  Widget _resumeCard(MatchController m) {
    final e = m.engine;
    final col = Color(e.players[e.cur].color);
    return GlowCard(
      tint: col,
      strength: 0.14,
      borderAlpha: 0.6,
      onTap: () => _open(GameScreen(controller: m)),
      child: Row(
        children: [
          Icon(Icons.play_circle_fill_rounded, size: 44, color: col),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Match fortsetzen', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text('${e.title} · ${e.players.map((p) => p.name).join(', ')}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 13)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Verwerfen',
            icon: Icon(Icons.close_rounded, color: C.muted),
            onPressed: () => setState(() => Store.activeMatch = null),
          ),
        ],
      ),
    );
  }

  Widget _modeCard(ModeDef m) {
    final col = categoryColor(m.category);
    return GlowCard(
      tint: col,
      strength: 0.06,
      onTap: () => _open(SetupScreen(mode: m)),
      child: Row(
        children: [
          _iconBox(modeIcon(m.id), col),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(m.short, style: TextStyle(color: C.muted, fontSize: 13)),
                const SizedBox(height: 6),
                Text(m.minPlayers > 1 ? '${m.minPlayers}–8 Spieler' : '1–8 Spieler',
                    style: TextStyle(color: col, fontSize: 11, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: C.muted),
        ],
      ),
    );
  }
}

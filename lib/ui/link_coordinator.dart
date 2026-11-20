import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../data/error_log.dart';
import '../data/match_controller.dart';
import '../data/storage.dart';
import '../data/sync.dart';
import '../models/player.dart';
import '../data/tournament_store.dart';
import '../models/dart.dart';
import '../net/link.dart';
import 'game_screen.dart';
import 'scoreboard_screen.dart';
import 'share_screens.dart';
import 'tournament_screens.dart';

/// Globaler Navigator – damit gekoppelte Spiele automatisch geöffnet werden können.
final navigatorKey = GlobalKey<NavigatorState>();

/// Verbindet die Kopplung ([Link]) mit der Oberfläche.
class LinkCoordinator {
  LinkCoordinator._();

  // Host
  static MatchController? hostMatch;
  static String? hostTournamentId;

  // Gast
  static MatchController? clientMatch;
  static Route<void>? _clientRoute;
  static Map<String, dynamic>? remoteTournament;
  static final remoteTick = ValueNotifier<int>(0);
  static bool _showingRemoteTournament = false;
  static String? _dismissedTournament;

  static bool _init = false;

  /// Dieses Gerät ist reine Anzeige (Scoreboard an der Wand).
  static bool viewer = false;
  static final viewerState = ValueNotifier<Map<String, dynamic>?>(null);
  static bool _showingBoard = false;

  static void _showBoard() {
    if (_showingBoard) return;
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    _showingBoard = true;
    nav.push(MaterialPageRoute<void>(settings: const RouteSettings(name: 'scoreboard'), builder: (_) => const ScoreboardScreen())).then((_) {
      _showingBoard = false;
    });
  }

  /// Als Anzeige beitreten.
  static void startViewer() {
    viewer = true;
    viewerState.value = null;
    _showBoard();
  }

  /// Nach Absturz/Neustart: Raum wieder öffnen bzw. neu verbinden (nur, wenn die
  /// Kopplung höchstens [Link.sessionMaxAge] her ist). Der Host öffnet das laufende Match.
  static Future<void> restoreSession() async {
    final s = Link.recentSession();
    if (s == null || Link.I.role != LinkRole.none) return;
    ErrorLog.crumb('Kopplung wird wiederhergestellt (${s['role']})');
    if (s['role'] == 'host') {
      try {
        await Link.I.startHost();
      } catch (_) {
        return;
      }
      final active = Store.activeMatch;
      final m = active == null ? null : MatchController.fromJson(active);
      final nav = navigatorKey.currentState;
      if (m != null && !m.engine.finished && nav != null) {
        unawaited(nav.push(MaterialPageRoute<void>(builder: (_) => GameScreen(controller: m))));
      }
      return;
    }
    final address = s['address'] as String?;
    final code = s['code'] as String? ?? '';
    final device = s['device'] as String?;
    final asViewer = s['viewer'] == true;
    final name = s['name'] as String?;
    final port = (s['port'] as num?)?.toInt() ?? Link.defaultPort;

    Future<bool> tryJoin(String addr, int p) async {
      viewer = asViewer;
      final ok = await Link.I.join(addr, p, code, name: name, viewer: asViewer, hostDevice: device);
      if (ok && asViewer) startViewer();
      if (!ok) viewer = false;
      return ok;
    }

    if (address != null && await tryJoin(address, port)) return;
    // Host evtl. noch nicht wieder da oder neue Adresse: bis zu 2 Minuten suchen.
    if (device == null) return;
    await Link.I.startDiscovery();
    final until = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(until) && Link.I.role == LinkRole.none) {
      final room = Link.I.rooms.value.where((r) => r.device == device).firstOrNull;
      if (room != null) {
        if (await tryJoin(room.address, room.port)) break;
      } else if (address != null && await tryJoin(address, port)) {
        break;
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    Link.I.stopDiscovery();
  }

  static void init() {
    if (_init) return;
    _init = true;
    final l = Link.I;
    l.hostState = _hostState;
    l.onHostMessage = _onHostMessage;
    l.onState = _onState;
    l.onShare = _onShare;
    l.onSync = _onSync;
    l.onJoinRequest = _askJoin;
    MatchController.onMatchCommitted = (_) => _scheduleSync();
    TournamentStore.changes.addListener(_scheduleSync);
    var wasConnected = false;
    var peers = 0;
    l.addListener(() {
      if (!l.isClient) {
        remoteTournament = null;
      }
      if (!l.isConnected) _syncedThisConnection = false;
      // Host: neuer Gast verbunden → abgleichen
      if (l.isHost && l.peerCount > peers) _scheduleSync();
      peers = l.peerCount;
      if (l.isConnected != wasConnected) wasConnected = l.isConnected;
    });
  }

  static (String?, int)? _tourKey;
  static Map<String, dynamic>? _tourJson;

  /// Turnier für den Stand – nur neu gelesen, wenn es sich geändert hat.
  static Map<String, dynamic>? _tournamentJson() {
    final id = hostTournamentId;
    if (id == null) return null;
    final key = (id, TournamentStore.changes.value);
    if (_tourKey != key) {
      _tourKey = key;
      _tourJson = TournamentStore.byId(id)?.toJson();
    }
    return _tourJson;
  }

  static Map<String, dynamic> _hostState() => {
        'match': hostMatch?.toJson(),
        'tournament': _tournamentJson(),
      };

  // ---------------------------------------------------------------- Bildschirme melden sich

  static void gameOpened(MatchController c) {
    if (c.remote) {
      clientMatch = c;
      return;
    }
    if (!Link.I.isHost) return;
    if (hostMatch != null && hostMatch != c) hostMatch!.removeListener(Link.I.broadcastState);
    hostMatch = c;
    c.addListener(Link.I.broadcastState);
    Link.I.broadcastState();
  }

  static void gameClosed(MatchController c) {
    if (_syncPending) Timer(const Duration(milliseconds: 10), _scheduleSync);
    if (clientMatch == c) {
      clientMatch = null;
      _clientRoute = null;
    }
    if (hostMatch == c) {
      c.removeListener(Link.I.broadcastState);
      hostMatch = null;
      Link.I.broadcastState();
    }
  }

  static void tournamentOpened(String id) {
    if (!Link.I.isHost) return;
    hostTournamentId = id;
    Link.I.broadcastState();
  }

  static void tournamentClosed(String id) {
    if (hostTournamentId == id) {
      hostTournamentId = null;
      Link.I.broadcastState();
    }
  }

  /// Host: Turnier hat sich geändert (Ergebnis eingetragen).
  static void tournamentChanged() => Link.I.broadcastState();

  /// Gast: eigenes Match starten – der Host übernimmt es und zeigt es allen.
  static void startOnHost(MatchController c) {
    c.remote = true;
    Link.I.sendToHost({'t': 'start', 'match': c.toJson()});
  }

  // ---------------------------------------------------------------- Host empfängt

  static void _onHostMessage(Map<String, dynamic> msg) {
    switch (msg['t']) {
      case 'dart':
        final m = hostMatch;
        if (m == null || m.matchId != msg['mid']) return;
        m.throwDartExternal(Dart.fromJson(Map<String, dynamic>.from(msg['d'] as Map)));
      case 'undo':
        final m = hostMatch;
        if (m == null || m.matchId != msg['mid'] || m.inputLocked) return;
        m.undo();
      case 'start':
        final c = MatchController.fromJson(Map<String, dynamic>.from(msg['match'] as Map));
        if (c == null || hostMatch?.matchId == c.matchId) return;
        navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => GameScreen(controller: c)));
    }
  }

  // ---------------------------------------------------------------- Gast empfängt

  /// Zuletzt empfangener Stand (für den Wechsel zwischen Anzeige und Mitspielen).
  static Map<String, dynamic>? _lastState;

  /// Gast: zwischen Mitspielen und reiner Anzeige (Punktetafel) wechseln.
  static void setViewer(bool v) {
    if (viewer == v) return;
    viewer = v;
    Link.I.setViewerMode(v);
    final st = _lastState;
    if (v) {
      // laufendes Mitspiel-Match schließen, Punktetafel zeigen
      final r = _clientRoute;
      if (r != null && r.isActive) navigatorKey.currentState?.removeRoute(r);
      clientMatch = null;
      _clientRoute = null;
      viewerState.value = st;
      _showBoard();
    } else {
      final nav = navigatorKey.currentState;
      if (_showingBoard && nav != null) nav.popUntil((r) => r.settings.name != 'scoreboard');
      if (st != null) _onState(st);
    }
  }

  static void _onState(Map<String, dynamic> state) {
    _lastState = state;
    if (viewer) {
      viewerState.value = state;
      _showBoard();
      return;
    }
    if (!_syncedThisConnection && Store.autoSync) {
      _syncedThisConnection = true;
      Link.I.requestSync(AutoSync.have);
    }
    final nav = navigatorKey.currentState;
    final mj = state['match'];
    final tj = state['tournament'];

    if (tj is Map) {
      final t = Map<String, dynamic>.from(tj);
      if (remoteTournament?['id'] != t['id']) _dismissedTournament = null;
      remoteTournament = t;
      remoteTick.value++;
    } else {
      remoteTournament = null;
      remoteTick.value++;
    }

    if (mj is Map) {
      final j = Map<String, dynamic>.from(mj);
      final cur = clientMatch;
      if (cur != null && cur.matchId == j['mid']) {
        final remoteDarts = [
          for (final d in j['darts'] as List) Dart.fromJson(Map<String, dynamic>.from(d as Map)),
        ];
        cur.applyRemote(remoteDarts);
        return;
      }
      final c = MatchController.fromJson(j);
      if (c == null || nav == null) return;
      c.remote = true;
      final route = MaterialPageRoute<void>(builder: (_) => GameScreen(controller: c));
      if (_clientRoute != null && _clientRoute!.isActive) {
        nav.replace(oldRoute: _clientRoute!, newRoute: route);
      } else {
        nav.push(route);
      }
      _clientRoute = route;
      clientMatch = c;
      return;
    }

    // Kein Match beim Host: laufendes Gast-Match schließen (fertige bleiben für das Ergebnis offen).
    final cur = clientMatch;
    if (cur != null && !cur.engine.finished && _clientRoute != null && _clientRoute!.isActive) {
      nav?.removeRoute(_clientRoute!);
      clientMatch = null;
      _clientRoute = null;
    }

    final rt = remoteTournament;
    if (rt != null && !_showingRemoteTournament && _dismissedTournament != rt['id'] && clientMatch == null) {
      _showingRemoteTournament = true;
      nav
          ?.push(MaterialPageRoute<void>(builder: (_) => TournamentScreen(id: rt['id'] as String, remote: true)))
          .then((_) {
        _showingRemoteTournament = false;
        _dismissedTournament = rt['id'] as String?;
      });
    }
  }

  // ---------------------------------------------------------------- Automatischer Abgleich

  static Timer? _syncTimer;
  static int _gotNew = 0;
  static Timer? _manualDone;

  /// Ergebnis des letzten Abgleichs (für Anzeige im Koppeln-Bildschirm).
  static final lastSync = ValueNotifier<String?>(null);

  static bool _syncPending = false;

  /// Läuft gerade ein Match (hier oder auf dem Host)? Dann wird nicht abgeglichen.
  static bool get _matchRunning => hostMatch != null || clientMatch != null;

  static void _scheduleSync() {
    if (!Store.autoSync || !Link.I.isConnected || Link.I.peerCount == 0) return;
    _syncTimer?.cancel();
    if (_matchRunning) {
      _syncPending = true;
      return;
    }
    _syncTimer = Timer(const Duration(milliseconds: 1500), () {
      if (_matchRunning) {
        _syncPending = true;
        return;
      }
      _syncPending = false;
      ErrorLog.crumb('Automatischer Abgleich startet');
      Link.I.requestSync(AutoSync.have);
    });
  }

  /// Gast: direkt nach dem Verbinden (erster Stand vom Host) abgleichen.
  static bool _syncedThisConnection = false;

  /// „Jetzt abgleichen“.
  static void syncNow() {
    _gotNew = 0;
    lastSync.value = 'Gleiche ab …';
    Link.I.requestSync(AutoSync.have);
    _manualDone?.cancel();
    _manualDone = Timer(const Duration(seconds: 3), () {
      if (_gotNew == 0) _report('Alles auf dem neuesten Stand');
    });
  }

  static void _report(String text) {
    lastSync.value = text;
    final ctx = navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      ScaffoldMessenger.of(ctx)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    }
  }

  static Future<void> _onSync(Map<String, dynamic> msg, void Function(Map<String, dynamic>) reply, String from) async {
    switch (msg['t']) {
      case 'syncreq':
        reply({'t': 'have', 'have': AutoSync.have(), 'reply': true});
      case 'have':
        final pkg = AutoSync.missingFor(Map<String, dynamic>.from(msg['have'] as Map));
        if (pkg != null) reply({'t': 'syncpkg', 'pkg': pkg.toJson()});
        if (msg['reply'] == true) reply({'t': 'have', 'have': AutoSync.have(), 'reply': false});
      case 'syncpkg':
        try {
          final pkg = SharePackage.fromJson(Map<String, dynamic>.from(msg['pkg'] as Map));
          final (added, created, ts) = await AutoSync.apply(pkg, confirm: _confirmSamePlayer);
          if (added + created + ts > 0) {
            _gotNew += added + created + ts;
            final parts = [
              if (added > 0) '$added neue Einträge',
              if (created > 0) '$created ${created == 1 ? 'neuer Spieler' : 'neue Spieler'}',
              if (ts > 0) '$ts ${ts == 1 ? 'Turnier' : 'Turniere'}',
            ];
            _report('Abgeglichen mit $from: ${parts.join(' · ')}');
          }
        } catch (_) {}
    }
  }

  /// Host: ein neues Gerät möchte beitreten.
  static Future<bool> _askJoin(String device, String name) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return false;
    final res = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.devices_rounded, size: 36),
        title: const Text('Neues Gerät'),
        content: Text('„$name“ möchte sich mit diesem Raum verbinden.\n\n'
            'Erlaube das nur, wenn es eines deiner Geräte ist. Erlaubte Geräte merkt sich die App.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Ablehnen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Erlauben')),
        ],
      ),
    ).timeout(const Duration(minutes: 2), onTimeout: () => false);
    return res ?? false;
  }

  /// Fragt einmalig, ob ein gleichnamiger Spieler derselbe ist.
  static Future<bool> _confirmSamePlayer(Profile incoming, Profile local) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return true;
    final res = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Derselbe Spieler?'),
        content: Text('„${incoming.name}“ vom anderen Handy – ist das dein Spieler „${local.name}“?\n\n'
            'Bei „Ja“ werden die Statistiken zusammengeführt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Nein, neu anlegen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ja')),
        ],
      ),
    );
    return res ?? true;
  }

  // ---------------------------------------------------------------- Spielerdaten

  static Future<void> _onShare(Map<String, dynamic> j, String from) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    try {
      final pkg = SharePackage.fromJson(j);
      final res = await nav.push<String>(MaterialPageRoute(builder: (_) => ImportPreviewScreen(pkg: pkg)));
      final ctx = navigatorKey.currentContext;
      if (res != null && ctx != null && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(res)));
      }
    } catch (_) {}
  }
}

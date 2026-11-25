import 'dart:async';

import 'package:flutter/foundation.dart' show mapEquals, visibleForTesting;
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
import 'theme.dart';
import 'tournament_screens.dart';
import 'update_dialog.dart';

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
  ///
  /// Wird beim App-Start aufgerufen – dort hängt auch die tägliche Update-Prüfung.
  /// Online: Der Host holt seinen Raum (Code + Token) zurück, der Gast tritt demselben
  /// Raum wieder bei und meldet sich mit seinem Schlüssel an (keine neue Freigabe).
  static Future<void> restoreSession() async {
    unawaited(UpdateUi.checkOnStart());
    final s = Link.recentSession();
    if (s == null || Link.I.role != LinkRole.none) return;
    final online = s['mode'] == 'online';
    // Im Browser gibt es keine WLAN-Kopplung.
    if (!online && !Link.lanSupported) return;
    ErrorLog.crumb('Kopplung wird wiederhergestellt (${s['role']}${online ? ', online' : ''})');
    if (s['role'] == 'host') {
      try {
        await (online ? Link.I.startOnlineHost() : Link.I.startHost());
      } catch (_) {
        return;
      }
      final active = Store.activeMatch;
      final m = active == null ? null : MatchController.fromJson(active);
      if (m != null && !m.engine.finished) _openHostGame(m);
      return;
    }
    // Gast: zuletzt laufendes Spiel gleich wieder öffnen – auch ohne Verbindung kann weiter
    // eingetragen werden, der Abgleich mit dem Host folgt beim Wiederverbinden.
    if (s['viewer'] != true) _reopenGuestMatch();
    final address = s['address'] as String?;
    final code = s['code'] as String? ?? '';
    final device = s['device'] as String?;
    final asViewer = s['viewer'] == true;
    final name = s['name'] as String?;
    if (online) {
      viewer = asViewer;
      final ok = await Link.I.joinOnline(code, name: name, viewer: asViewer, hostDevice: device);
      if (ok && asViewer) startViewer();
      if (!ok) viewer = false;
      return;
    }
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

  /// Kopplung scheitert an der App-Version: erklären und – wenn diese App zu alt ist – Update anbieten.
  static Future<void> _versionMismatch(VersionMismatch why) async {
    if (why == VersionMismatch.selfTooOld && await UpdateUi.checkNow(force: true)) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await showDialog<void>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('App-Versionen passen nicht'),
        content: Text(why == VersionMismatch.selfTooOld
            ? 'Das Raum-Gerät hat eine neuere Darts-Version als dieses Gerät. Bitte aktualisiere die App hier '
                '(Einstellungen → „Nach Updates suchen“) und tritt danach wieder bei.'
            : 'Das Raum-Gerät hat eine ältere Darts-Version als dieses Gerät. Bitte aktualisiere die App dort '
                'und öffne den Raum danach neu.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
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
    l.onDirect = _onDirect;
    l.onUpdateRequired = (info) => unawaited(UpdateUi.showRequired(info));
    l.onVersionMismatch = (why) => unawaited(_versionMismatch(why));
    MatchController.onMatchCommitted = (_) => _scheduleSync();
    TournamentStore.changes.addListener(_scheduleSync);
    var wasConnected = false;
    var peers = 0;
    l.addListener(() {
      if (!l.isClient) {
        remoteTournament = null;
      }
      if (!l.isConnected) _syncedThisConnection = false;
      // Raum erst während eines Spiels eröffnet (Verbindungs-Symbol im Spiel): Spiel anbieten.
      final open = _openLocal;
      if (l.isHost && hostMatch == null && open != null) gameOpened(open);
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

  static Map<String, dynamic> _hostState() {
    _assignBoards();
    final hm = hostMatch;
    final boards = <Map<String, dynamic>>[
      if (hm != null) {'n': hostBoard, 'name': 'Scheibe $hostBoard', 'match': hm.toJson()},
      for (final b in _boardMatches.entries)
        if (b.value['paused'] != true) {'n': b.key, 'name': 'Scheibe ${b.key}', 'match': b.value['match']},
    ]..sort((a, b) => (a['n'] as int).compareTo(b['n'] as int));
    return {
      'match': hm?.toJson(),
      'tournament': _tournamentJson(),
      'boards': boards,
      'boardOf': {Store.deviceId: hostBoard, ..._boardOfDevice},
      'claims': claims,
      // Hier bewusst verlassene Spiele: Gäste schließen sie, statt sie zu behalten.
      if (_endedMatches.isNotEmpty) 'ended': _endedMatches,
    };
  }

  // ---------------------------------------------------------------- Mehrere Scheiben (Turnier)

  /// Scheiben-Nummer dieses Geräts als Host.
  static int hostBoard = 1;

  /// Host: Scheibe je Gast-Gerät.
  static final Map<String, int> _boardOfDevice = {};

  /// Host: Spiele der Gast-Scheiben (Nummer → {match, tmid, dev, paused, done}).
  static final Map<int, Map<String, dynamic>> _boardMatches = {};

  /// Gast: zuletzt vom Host gemeldete Zuordnungen.
  static Map<String, int> _remoteBoardOf = {};
  static Map<String, int> _remoteClaims = {};

  /// Ändert sich, wenn Scheiben/Sperren sich ändern (für Turnier-Bildschirme).
  static final boardsTick = ValueNotifier<int>(0);

  /// Eigene Scheiben-Nummer (Host: [hostBoard], Gast: vom Host vergeben).
  static int? get myBoard => Link.I.isHost ? hostBoard : _remoteBoardOf[Store.deviceId];

  /// Turnierspiel-ID → Scheibe, auf der es gerade läuft (oder unterbrochen ist).
  static Map<String, int> get claims {
    if (!Link.I.isHost) return _remoteClaims;
    final out = <String, int>{};
    final hm = hostMatch;
    if (hm != null && hm.isTournament && !hm.engine.finished) out[hm.tournamentMatchId!] = hostBoard;
    for (final b in _boardMatches.entries) {
      final tmid = b.value['tmid'] as String?;
      if (tmid != null && b.value['done'] != true) out[tmid] = b.key;
    }
    return out;
  }

  /// Host: jedem eingabefähigen Gast eine freie Nummer geben (2, 3, …).
  static void _assignBoards() {
    for (final (dev, _) in Link.I.inputPeers) {
      if (_boardOfDevice.containsKey(dev)) continue;
      var n = 1;
      while (n == hostBoard || _boardOfDevice.containsValue(n)) {
        n++;
      }
      _boardOfDevice[dev] = n;
    }
  }

  /// Nummer ändern (Host direkt, Gast fragt beim Host an).
  static void requestBoardNumber(int n) {
    if (Link.I.isHost) {
      if (_boardOfDevice.containsValue(n)) {
        _report('Scheibe $n ist schon vergeben.');
        return;
      }
      hostBoard = n;
      _boardsChanged();
    } else {
      Link.I.sendToHost({'t': 'boardNo', 'n': n});
    }
  }

  static void _boardsChanged() {
    boardsTick.value++;
    Link.I.broadcastState();
  }

  /// Host: ein Turnierspiel freigeben (z. B. Gerät ausgefallen).
  static void releaseClaim(String tmid) {
    final e = _boardMatches.entries.where((x) => x.value['tmid'] == tmid).firstOrNull;
    if (e == null) return;
    _boardMatches.remove(e.key);
    final dev = e.value['dev'] as String?;
    if (dev != null) Link.I.sendToDevice(dev, {'t': 'direct', 'kind': 'boardReleased', 'tmid': tmid});
    _boardsChanged();
  }

  static void _onBoardMessage(Map<String, dynamic> msg) {
    final dev = msg['_dev'] as String? ?? '';
    _assignBoards();
    final n = _boardOfDevice[dev];
    if (n == null) return;
    if (msg['t'] == 'boardNo') {
      final want = (msg['n'] as num?)?.toInt() ?? 0;
      final taken = want == hostBoard || _boardOfDevice.entries.any((x) => x.value == want && x.key != dev);
      if (want < 1 || want > 99 || taken) {
        Link.I.sendToDevice(dev, {'t': 'direct', 'kind': 'boardNoTaken', 'n': want});
        return;
      }
      _boardOfDevice[dev] = want;
      final cur = _boardMatches.remove(n);
      if (cur != null) _boardMatches[want] = cur;
      _boardsChanged();
      return;
    }
    final tmid = msg['tmid'] as String?;
    final mj = msg['match'];
    if (msg['closed'] == true) {
      // Gast hat das Spiel verlassen: fertig → entfernen, sonst als unterbrochen gesperrt lassen.
      if (mj is Map) {
        final c = MatchController.fromJson(Map<String, dynamic>.from(mj));
        if (c != null && c.engine.finished && c.isTournament) {
          TournamentStore.onMatchDone(c);
          _boardMatches[n]?['done'] = true;
        }
      }
      final cur = _boardMatches[n];
      if (cur != null) {
        if (cur['done'] == true || tmid == null) {
          _boardMatches.remove(n);
        } else {
          cur['paused'] = true;
        }
      }
      _boardsChanged();
      return;
    }
    if (mj is! Map) return;
    if (tmid != null) {
      final owner = claims[tmid];
      final t = TournamentStore.byId(msg['tid'] as String? ?? '');
      final tm = t?.matches.where((m) => m.id == tmid).firstOrNull;
      final alreadyPlayed = tm != null && tm.played && _boardMatches[n]?['tmid'] != tmid;
      if ((owner != null && owner != n) || alreadyPlayed) {
        Link.I.sendToDevice(dev, {'t': 'direct', 'kind': 'boardDenied', 'tmid': tmid, 'by': owner});
        return;
      }
    }
    final j = Map<String, dynamic>.from(mj);
    var done = false;
    final c = MatchController.fromJson(j);
    if (c != null && c.engine.finished) {
      done = true;
      // Ergebnis ins Turnier übernehmen (wird ignoriert, wenn schon eingetragen). Ältere Geräte
      // schicken kein „final“ – dann wie bisher sofort; sonst erst, wenn der Gast das Ergebnis verlässt.
      if (c.isTournament && msg['final'] != false) TournamentStore.onMatchDone(c);
    }
    _boardMatches[n] = {'match': j, 'tmid': tmid, 'dev': dev, 'done': done};
    _boardsChanged();
  }

  // ---------------------------------------------------------------- Gast: eigene Scheibe

  /// Gast: selbst geführtes Turnierspiel (läuft auf diesem Gerät, der Host bekommt den Stand).
  static MatchController? boardMatch;
  static Route<void>? _boardRoute;

  static void _sendBoard({bool closed = false}) {
    final c = boardMatch;
    if (c == null) return;
    Link.I.sendToHost({
      't': 'board',
      'mid': c.matchId,
      'tid': c.tournamentId,
      'tmid': c.tournamentMatchId,
      'match': c.toJson(),
      // Erst beim Verlassen des Ergebnisses gilt es – bis dahin kann noch zurückgenommen werden.
      'final': c.committed || closed,
      if (closed) 'closed': true,
    });
  }

  /// Gast: Turnierspiel auf dieser Scheibe starten bzw. fortsetzen.
  static Future<void> playBoardMatch(MatchController c) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    boardMatch?.removeListener(_sendBoard);
    boardMatch = c;
    c.addListener(_sendBoard);
    _sendBoard();
    final route = MaterialPageRoute<void>(builder: (_) => GameScreen(controller: c));
    _boardRoute = route;
    await nav.push(route);
  }

  static void _onDirect(Map<String, dynamic> msg) {
    final c = boardMatch;
    switch (msg['kind']) {
      case 'boardDenied' || 'boardReleased':
        if (c == null || c.tournamentMatchId != msg['tmid']) return;
        c.removeListener(_sendBoard);
        boardMatch = null;
        final r = _boardRoute;
        if (r != null && r.isActive) navigatorKey.currentState?.removeRoute(r);
        _boardRoute = null;
        final a = Store.activeMatch;
        if (a != null && a['mid'] == c.matchId) Store.activeMatch = null;
        final by = msg['by'];
        _report(msg['kind'] == 'boardReleased'
            ? 'Das Spiel wurde am Turnier-Gerät freigegeben.'
            : by != null
                ? 'Dieses Spiel läuft schon auf Scheibe $by.'
                : 'Dieses Spiel ist schon eingetragen.');
      case 'boardNoTaken':
        _report('Scheibe ${msg['n']} ist schon vergeben.');
      case 'catchupDone':
        _onCatchupDone(msg);
    }
  }


  // ---------------------------------------------------------------- Bildschirme melden sich

  /// Auf diesem Gerät offenes eigenes Spiel (auch ohne Kopplung).
  static MatchController? _openLocal;

  /// Host: zuletzt hier verlassene Spiele (Match-IDs) – Gäste schließen sie dann ebenfalls.
  static final List<String> _endedMatches = [];

  /// Host: Spiel wird gerade (wieder) geöffnet – nicht doppelt öffnen.
  static String? _openingMid;

  /// Host: Abgleich-Anfragen, die auf das Öffnen ihres Spiels warten.
  static final Map<String, Map<String, dynamic>> _pendingCatchup = {};

  /// Host: eigenes Spiel öffnen (nach Neustart oder auf Wunsch eines Gasts), höchstens einmal.
  static void _openHostGame(MatchController m) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    if (_openLocal?.matchId == m.matchId || hostMatch?.matchId == m.matchId || _openingMid == m.matchId) return;
    _openingMid = m.matchId;
    unawaited(nav.push(MaterialPageRoute<void>(builder: (_) => GameScreen(controller: m))));
  }

  static void gameOpened(MatchController c) {
    if (c.remote) {
      clientMatch = c;
      return;
    }
    _openLocal = c;
    if (_openingMid == c.matchId) _openingMid = null;
    _endedMatches.remove(c.matchId);
    if (!Link.I.isHost) return;
    if (hostMatch != null && hostMatch != c) hostMatch!.removeListener(Link.I.broadcastState);
    hostMatch = c;
    c.addListener(Link.I.broadcastState);
    Link.I.broadcastState();
    final pending = _pendingCatchup.remove(c.matchId);
    if (pending != null) scheduleMicrotask(() => _onCatchup(pending));
  }

  static void gameClosed(MatchController c) {
    if (_openLocal == c) _openLocal = null;
    if (boardMatch == c) {
      _sendBoard(closed: true);
      c.removeListener(_sendBoard);
      boardMatch = null;
      _boardRoute = null;
    }
    if (_syncPending) Timer(const Duration(milliseconds: 10), _scheduleSync);
    if (clientMatch == c) {
      clientMatch = null;
      _clientRoute = null;
      // Bewusst verlassen (oder vom Host beendet): nicht mehr wiederherstellen.
      if (Store.guestMatch?['mid'] == c.matchId) Store.guestMatch = null;
    }
    if (hostMatch == c) {
      c.removeListener(Link.I.broadcastState);
      hostMatch = null;
      _endedMatches
        ..remove(c.matchId)
        ..add(c.matchId);
      if (_endedMatches.length > 20) _endedMatches.removeAt(0);
      Link.I.broadcastState();
    }
  }

  static void tournamentOpened(String id) {
    // Auch ohne Kopplung merken: Wird der Raum erst danach eröffnet, sehen die Gäste das Turnier.
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
      case 'board' || 'boardNo':
        _onBoardMessage(msg);
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
      case 'catchup':
        _onCatchup(msg);
    }
  }

  // ---------------------------------------------------------------- Nachsync (Host)

  /// Ein Gast meldet nach dem Wiederverbinden seinen Stand eines Spiels:
  /// - Host-Stand ist Anfang des Gast-Stands → Würfe des Gasts übernehmen.
  /// - Gast-Stand ist Anfang des Host-Stands oder gleich → nichts zu tun (Gast holt auf).
  /// - Beide haben unterschiedlich weitergezählt → am Host fragen, welcher Stand bleibt.
  /// Hat der Host das Spiel gerade nicht offen (z. B. nach Neustart), öffnet er es wieder:
  /// den eigenen gespeicherten Stand, sonst den des Gasts.
  static Future<void> _onCatchup(Map<String, dynamic> msg) async {
    final mid = msg['mid'] as String?;
    final dev = msg['_dev'] as String? ?? '';
    final from = msg['_name'] as String? ?? 'Anderes Gerät';
    if (mid == null || msg['darts'] is! List) return;
    void done({bool gone = false}) {
      Link.I.sendToDevice(dev, {'t': 'direct', 'kind': 'catchupDone', 'mid': mid, if (gone) 'gone': true});
      Link.I.broadcastState();
    }

    final List<Dart> theirs;
    try {
      theirs = [for (final d in msg['darts'] as List) Dart.fromJson(Map<String, dynamic>.from(d as Map))];
    } catch (_) {
      return;
    }
    if (theirs.any((d) => !MatchController.isValidDart(d))) return;
    final m = hostMatch;
    if (m == null || m.matchId != mid) {
      if (m != null || _endedMatches.contains(mid)) {
        // Hier läuft schon ein anderes Spiel bzw. es wurde bewusst beendet.
        done(gone: true);
        return;
      }
      // Spiel wieder öffnen; der Abgleich läuft, sobald es offen ist.
      final active = Store.activeMatch;
      MatchController? c;
      if (active != null && active['mid'] == mid) c = MatchController.fromJson(active);
      final mj = msg['match'];
      if (c == null && mj is Map) c = MatchController.fromJson(Map<String, dynamic>.from(mj));
      if (c == null) {
        done(gone: true);
        return;
      }
      _pendingCatchup[mid] = msg;
      ErrorLog.crumb('Nachsync: Spiel wird für $from wieder geöffnet');
      _openHostGame(c);
      return;
    }
    if (m.committed) {
      done();
      return;
    }
    final mine = m.darts;
    bool prefix(List<Dart> a, List<Dart> b) {
      if (a.length > b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i].code != b[i].code) return false;
      }
      return true;
    }

    if (prefix(theirs, mine)) {
      done();
      return;
    }
    if (prefix(mine, theirs)) {
      ErrorLog.crumb('Nachsync: ${theirs.length - mine.length} Würfe von $from übernommen');
      m.applyRemote(theirs);
      _report('${theirs.length - mine.length} Würfe von $from nachgetragen');
      done();
      return;
    }
    if (msg['dirty'] != true) {
      done();
      return;
    }
    // Beide haben unterschiedlich weitergezählt.
    if (_conflictOpen.contains(mid)) {
      _conflictLatest[mid] = msg;
      return;
    }
    _conflictOpen.add(mid);
    _conflictLatest[mid] = msg;
    final keepTheirs = await _askConflict(m, theirs, from);
    _conflictOpen.remove(mid);
    final latest = _conflictLatest.remove(mid) ?? msg;
    if (keepTheirs == true && hostMatch == m && !m.committed) {
      final List<Dart> chosen = [
        for (final d in latest['darts'] as List) Dart.fromJson(Map<String, dynamic>.from(d as Map)),
      ];
      ErrorLog.crumb('Nachsync: Stand von $from übernommen');
      m.applyRemote(chosen);
    } else {
      ErrorLog.crumb('Nachsync: eigener Stand behalten');
    }
    done();
  }

  static final Set<String> _conflictOpen = {};
  static final Map<String, Map<String, dynamic>> _conflictLatest = {};

  /// Test: Antwort auf die Konflikt-Frage vorgeben (true = Stand des Gasts).
  @visibleForTesting
  static Future<bool?> Function(MatchController mine, MatchController theirs, String from)? conflictForTest;

  /// Kurzstand je Spieler, z. B. „Simon 121 · Anna 87“.
  static String _summary(MatchController c) {
    final e = c.engine;
    return [for (var i = 0; i < e.n; i++) '${e.players[i].name} ${e.mainValue(i)}'].join(' · ');
  }

  static Future<bool?> _askConflict(MatchController m, List<Dart> theirs, String from) async {
    final other = MatchController.fromJson({...m.toJson(), 'darts': [for (final d in theirs) d.toJson()]});
    if (other == null) return false;
    final t = conflictForTest;
    if (t != null) return t(m, other, from);
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return false;
    Widget box(String title, MatchController c, int darts) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(_summary(c)),
              Text('$darts Würfe eingetragen', style: TextStyle(color: C.muted, fontSize: 12)),
            ],
          ),
        );
    return showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.sync_problem_rounded, size: 36),
        title: const Text('Zwei verschiedene Spielstände'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Während die Verbindung weg war, wurde hier und auf „$from“ unterschiedlich '
                  'weitergezählt. Welcher Stand soll gelten? Alle Geräte bekommen danach diesen Stand.'),
              box('Dieses Gerät (${Store.deviceName})', m, m.darts.length),
              box(from, other, theirs.length),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Diesen behalten')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text('Stand von $from')),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- Nachsync (Gast)

  /// Gast: Enthält der Host-Stand alle eigenen Würfe (gleich oder weiter)?
  static bool _hostHasAll(MatchController c, List<Dart> host) {
    final mine = c.darts;
    if (mine.length > host.length) return false;
    for (var i = 0; i < mine.length; i++) {
      if (mine[i].code != host[i].code) return false;
    }
    return true;
  }

  /// Gast: Muss der eigene Stand an den Host (statt einfach dessen Stand zu übernehmen)?
  /// Ja, wenn hier mehr eingetragen ist als beim Host oder offline anders weitergezählt wurde.
  static bool _needsCatchup(MatchController c, List<Dart> host) {
    if (Link.I.hostCompat < linkCatchupCompat) return false;
    final mine = c.darts;
    var same = 0;
    while (same < mine.length && same < host.length && mine[same].code == host[same].code) {
      same++;
    }
    if (same == mine.length) return false; // gleich oder Host weiter → übernehmen
    // Hier mehr oder anders eingetragen: nur, wenn es eigene, unbestätigte Eingaben sind
    // (sonst hat der Host z. B. etwas zurückgenommen, und sein Stand gilt).
    return c.offlineDirty;
  }

  /// Gast: Verbindung, für die der Abgleich schon lief.
  static int _catchupEpoch = -1;

  /// Gast: gespeichertes Spiel nach Neustart wieder öffnen (offline weiterzählen möglich).
  static void _reopenGuestMatch() {
    final g = Store.guestMatch;
    final nav = navigatorKey.currentState;
    if (g == null || nav == null || clientMatch != null || boardMatch != null) return;
    final c = MatchController.fromJson(g);
    if (c == null || c.engine.finished) {
      Store.guestMatch = null;
      return;
    }
    c
      ..remote = true
      ..offlineDirty = g['dirty'] == true;
    ErrorLog.crumb('Gekoppeltes Spiel wiederhergestellt (${c.darts.length} Würfe)');
    final route = MaterialPageRoute<void>(builder: (_) => GameScreen(controller: c));
    _clientRoute = route;
    clientMatch = c;
    unawaited(nav.push(route));
  }

  /// Gast: eigenen Stand an den Host schicken (er entscheidet, was gilt).
  static void _sendCatchup(MatchController c) {
    c.awaitingCatchup = true;
    Link.I.sendToHost({
      't': 'catchup',
      'mid': c.matchId,
      'darts': [for (final d in c.darts) d.toJson()],
      'dirty': c.offlineDirty,
      'match': c.toJson(),
    });
    // Ohne Antwort (Verbindung wieder weg) wird bei der nächsten Verbindung erneut gefragt.
  }

  /// Gast: Antwort des Hosts auf den Abgleich.
  static void _onCatchupDone(Map<String, dynamic> msg) {
    final c = clientMatch;
    if (c == null || c.matchId != msg['mid']) return;
    c
      ..awaitingCatchup = false
      ..offlineDirty = false;
    final st = _lastState;
    if (msg['gone'] == true) {
      // Host spielt etwas anderes bzw. hat das Spiel beendet → hier schließen.
      final r = _clientRoute;
      if (r != null && r.isActive) navigatorKey.currentState?.removeRoute(r);
      clientMatch = null;
      _clientRoute = null;
      Store.guestMatch = null;
      _report('Das Spiel wurde am anderen Gerät beendet.');
      if (st != null) _onState(st);
      return;
    }
    final mj = st?['match'];
    if (mj is Map && mj['mid'] == c.matchId) {
      c.applyRemote([for (final d in mj['darts'] as List) Dart.fromJson(Map<String, dynamic>.from(d as Map))]);
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
    final bo = state['boardOf'];
    final cl = state['claims'];
    final newBoardOf = bo is Map ? {for (final e in bo.entries) '${e.key}': (e.value as num).toInt()} : <String, int>{};
    final newClaims = cl is Map ? {for (final e in cl.entries) '${e.key}': (e.value as num).toInt()} : <String, int>{};
    if (!mapEquals(newBoardOf, _remoteBoardOf) || !mapEquals(newClaims, _remoteClaims)) {
      _remoteBoardOf = newBoardOf;
      _remoteClaims = newClaims;
      boardsTick.value++;
    }
    // Nach Neuverbindung den Stand der eigenen Scheibe erneut melden (auch offline Eingetragenes).
    final fresh = Link.I.connectionEpoch != _catchupEpoch;
    _catchupEpoch = Link.I.connectionEpoch;
    final bm = boardMatch;
    if (bm != null && !bm.engine.finished && (fresh || newClaims[bm.tournamentMatchId] == null)) _sendBoard();
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

    // Spielt dieses Gerät selbst eine Scheibe, oder ist das Host-Match ein Turnierspiel
    // (läuft auf der Scheibe des Hosts), wird es hier nicht automatisch geöffnet.
    final hostTournamentMatch = mj is Map && mj['tmid'] != null;
    if (mj is Map && (boardMatch != null || (hostTournamentMatch && clientMatch?.matchId != mj['mid']))) {
      return;
    }
    if (mj is Map) {
      final j = Map<String, dynamic>.from(mj);
      final cur = clientMatch;
      if (cur != null && cur.matchId == j['mid']) {
        final remoteDarts = [
          for (final d in j['darts'] as List) Dart.fromJson(Map<String, dynamic>.from(d as Map)),
        ];
        // Abgleich läuft: eigenen Stand behalten, bis der Host geantwortet hat – außer der Host
        // hat unsere Würfe inzwischen schon (dann ist der Abgleich erledigt).
        if (cur.awaitingCatchup && !fresh && !_hostHasAll(cur, remoteDarts)) return;
        if (fresh && _needsCatchup(cur, remoteDarts)) {
          _sendCatchup(cur);
          return;
        }
        cur
          ..awaitingCatchup = false
          ..offlineDirty = false;
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
    // Hat der Host das Spiel nicht bewusst beendet (z. B. nach Neustart noch nicht wieder offen),
    // bleibt es hier offen, und der Host bekommt es zum Wiederöffnen angeboten.
    final cur = clientMatch;
    final ended = state['ended'];
    final hostEnded = ended is List && ended.contains(cur?.matchId);
    if (cur != null && !cur.engine.finished && !hostEnded && Link.I.hostCompat >= linkCatchupCompat) {
      if (fresh || !cur.awaitingCatchup) _sendCatchup(cur);
      return;
    }
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

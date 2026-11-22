import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:darts_protocol/darts_protocol.dart';
import 'package:flutter/foundation.dart';

import '../data/error_log.dart';
import '../data/storage.dart';
import '../data/sync.dart';
import 'lan_stub.dart' if (dart.library.io) 'lan_io.dart';
import 'peer_socket.dart';
import 'relay.dart';
import 'server_config.dart';

export 'relay.dart' show RelayStatus;

enum LinkRole { none, host, client }

/// Stand des Spiel-/Kopplungsformats zwischen den Geräten. Erhöhen, wenn sich Nachrichten oder der
/// Spielstand so ändern, dass ältere Apps sie nicht mehr richtig verstehen – und dann ggf.
/// [linkMinCompat] mitziehen. Apps ohne Angabe (bis 3.0.0) zählen als 2.
const linkCompat = 3;

/// Ältester Stand, mit dem diese App noch zusammen spielt. Ältere Geräte bekommen „Bitte aktualisieren“.
const linkMinCompat = 2;

/// Warum ein Gerät wegen der App-Version nicht mitspielen kann.
enum VersionMismatch {
  /// Diese App ist älter, als das Raum-Gerät erlaubt.
  selfTooOld,

  /// Das Raum-Gerät hat eine ältere App, als diese erlaubt.
  hostTooOld,
}

/// Über welchen Weg gekoppelt wird: direkt im WLAN oder über den Vermittlungs-Server.
enum LinkMode { lan, online }

/// Fehler beim Öffnen eines Raums (Text ist für die Anzeige gedacht).
class LinkException implements Exception {
  LinkException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Ein im WLAN gefundener Raum.
class Room {
  Room({required this.address, required this.port, this.code, required this.name, required this.device});
  final String address;
  final int port;

  /// Wird nicht mehr übers Netz verraten – nur bekannt, wenn schon einmal verbunden.
  final String? code;
  final String name;
  final String device;
  DateTime seen = DateTime.now();
}

class _Peer {
  _Peer(this.ws, this.ip);
  final PeerSocket ws;
  final String ip;
  String device = '';
  String name = 'Gerät';

  /// Vom Host erlaubt (vorher bekommt das Gerät keine Daten).
  bool approved = false;
  bool helloSeen = false;

  /// Mit richtigem Code verbunden (sonst nur per Schlüssel erlaubt).
  bool byCode = false;

  /// Nur Anzeige: darf nichts eintragen.
  bool viewer = false;

  /// Schlüssel-Anmeldung: Herausforderung des Hosts.
  String? challenge;
  String? key;
}

/// Zufällige Hex-Zeichenkette (kryptografisch sicher).
String randomHex(int bytes) {
  final r = Random.secure();
  return [for (var i = 0; i < bytes; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
}

/// Nachweis, dass man den gemeinsamen Schlüssel kennt (ohne ihn zu senden).
String authProof(String key, String role, String nonce, String device) =>
    Hmac(sha256, utf8.encode(key)).convert(utf8.encode('$role|$nonce|$device')).toString();

/// Kopplung mehrerer Geräte – im lokalen Netz (WLAN oder Hotspot) oder online über den
/// Vermittlungs-Server.
///
/// Ein Gerät ist Host, die anderen verbinden sich. Der Host ist die Schiedsstelle:
/// Würfe der Gäste gehen an ihn, er schickt den neuen Stand an alle.
/// Der Transport ist austauschbar ([PeerSocket]): im WLAN ein eigener WebSocket-Server
/// (`lan_io.dart`, nur Android), online virtuelle Kanäle durch das Relais (`relay.dart`).
/// Das Protokoll darüber (hello/auth/welcome/state …) ist in beiden Fällen gleich.
class Link extends ChangeNotifier {
  Link._();
  static final Link I = Link._();

  /// Eigene Instanz für Tests (Host und Gast im selben Prozess).
  @visibleForTesting
  factory Link.forTest() => Link._()..trustAll = true;

  /// Tests: eigene Geräte-ID für mehrere simulierte Gäste in einem Prozess.
  @visibleForTesting
  String? deviceForTest;

  /// Test: jedes Gerät ohne Nachfrage erlauben.
  @visibleForTesting
  bool trustAll = false;

  /// Host: fragt, ob ein neues Gerät beitreten darf (true = erlauben und merken).
  Future<bool> Function(String device, String name)? onJoinRequest;

  /// Eigener Format-Stand und ältester erlaubter Stand (Tests stellen hier andere Versionen nach;
  /// [compat] = 0 verhält sich wie eine App bis 3.0.0 ohne Angabe).
  @visibleForTesting
  int compat = linkCompat;
  @visibleForTesting
  int minCompat = linkMinCompat;

  /// Gast: Kopplung scheitert an der App-Version (Hinweis + Update anbieten).
  void Function(VersionMismatch why)? onVersionMismatch;

  /// Gast: letzter Versionskonflikt (für die Anzeige), sonst null.
  VersionMismatch? versionMismatch;

  static const maxPeers = 8;
  static const maxFails = 5;
  static const failWindow = Duration(minutes: 10);

  /// Max. Größe einer Nachricht (größere werden verworfen).
  static const maxMessage = 16 * 1024 * 1024;

  /// Falsche Code-Versuche je Adresse (Zeitpunkte).
  final Map<String, List<DateTime>> _fails = {};

  static const defaultPort = 47123;
  static const discoveryPort = 47124;

  /// Gibt es auf dieser Plattform die WLAN-Kopplung? (Im Browser nicht.)
  static bool get lanSupported => lanAvailable;

  LinkRole role = LinkRole.none;

  /// Aktueller Weg (nur sinnvoll, solange [role] nicht none ist).
  LinkMode mode = LinkMode.lan;
  bool get isOnline => mode == LinkMode.online;

  /// Raum-Code: im WLAN 4 Ziffern, online 6 Zeichen vom Server ([RoomCode]).
  String? code;
  int port = 0;
  List<String> addresses = [];
  String status = '';

  /// Online: Zustand der Verbindung zum Server.
  RelayStatus? relayStatus;

  /// Server meldet „App zu alt“ (Update-Dialog anzeigen).
  void Function(Map<String, dynamic>? info)? onUpdateRequired;

  // Host
  LanServer? _server;
  RelayHost? _relayHost;
  final List<_Peer> _peers = [];
  Timer? _announce;

  // Gast
  PeerSocket? _ws;
  RelayGuest? _relayGuest;
  String? hostAddress;
  int? hostPort;
  String? hostName;
  bool _wantConnected = false;
  Timer? _retry;

  // ---------------------------------------------------------------- Sitzung merken

  /// Wie lange nach dem letzten Lebenszeichen eine Kopplung wiederhergestellt wird.
  static const sessionMaxAge = Duration(minutes: 30);
  Map<String, dynamic>? _session;
  Timer? _sessionBeat;

  /// Kopplung merken und alle 30 s den Zeitstempel erneuern (Lebenszeichen).
  void _remember(Map<String, dynamic> session) {
    _session = session;
    _beat();
    _sessionBeat?.cancel();
    _sessionBeat = Timer.periodic(const Duration(seconds: 30), (_) => _beat());
  }

  void _beat() {
    final s = _session;
    if (s == null) return;
    Store.linkSession = {...s, 'ts': DateTime.now().millisecondsSinceEpoch};
  }

  void _clientSession() {
    if (role != LinkRole.client) return;
    _remember({
      'role': 'client',
      if (isOnline) 'mode': 'online',
      'address': hostAddress,
      'port': hostPort,
      'code': code,
      'name': hostName,
      'viewer': joinedAsViewer,
      'device': _remembered ?? _expectHost,
    });
  }

  /// Gemerkte Kopplung, falls jünger als [sessionMaxAge] (sonst null und gelöscht).
  static Map<String, dynamic>? recentSession([DateTime? now]) {
    final s = Store.linkSession;
    if (s == null) return null;
    final ts = (s['ts'] as num?)?.toInt() ?? 0;
    final age = (now ?? DateTime.now()).millisecondsSinceEpoch - ts;
    if (age < 0 || age > sessionMaxAge.inMilliseconds) {
      Store.linkSession = null;
      return null;
    }
    return s;
  }

  /// Vom Nutzer gewollt trennen bzw. Raum schließen: nichts wiederherstellen.
  /// Online-Host: der Raum wird auf dem Server geschlossen (Gäste bekommen „closed“).
  Future<void> leave() async {
    _forget();
    await stop(closeRoom: true);
  }

  void _forget() {
    _session = null;
    _sessionBeat?.cancel();
    _sessionBeat = null;
    Store.linkSession = null;
  }
  int remoteDevices = 0;

  // Raumsuche
  final rooms = ValueNotifier<List<Room>>([]);
  LanListener? _udpListen;
  Timer? _prune;

  // ---------------------------------------------------------------- Anbindung an die App
  /// Host: aktueller Stand (laufendes Match, Turnier), der an alle geht.
  Map<String, dynamic> Function()? hostState;

  /// Host: Nachricht eines Gasts (dart, undo, start).
  void Function(Map<String, dynamic> msg)? onHostMessage;

  /// Gast: Antwort des Hosts nur an dieses Gerät (z. B. Turnierspiel schon vergeben).
  void Function(Map<String, dynamic> msg)? onDirect;

  /// Host: eingabefähige Gäste (keine reinen Anzeigen) mit Geräte-ID und Name.
  List<(String, String)> get inputPeers => [
        for (final p in _approved)
          if (!p.viewer && p.device.isNotEmpty) (p.device, p.name),
      ];

  /// Host: Nachricht nur an ein bestimmtes Gerät.
  void sendToDevice(String device, Map<String, dynamic> msg) {
    for (final p in _approved) {
      if (p.device == device) _send(p.ws, msg);
    }
  }

  /// Gast: neuer Stand vom Host.
  void Function(Map<String, dynamic> state)? onState;

  /// Eingehende Spielerdaten.
  void Function(Map<String, dynamic> pkg, String from)? onShare;

  /// Abgleich-Nachrichten (have / syncpkg / syncreq) mit Antwortfunktion an den Absender.
  void Function(Map<String, dynamic> msg, void Function(Map<String, dynamic>) reply, String from)? onSync;

  bool get isHost => role == LinkRole.host;
  bool get isClient => role == LinkRole.client;
  /// Host: Raum offen (online: Server erreichbar). Gast: mit dem Host verbunden und erlaubt.
  bool get isConnected =>
      (isHost && (!isOnline || relayStatus == RelayStatus.online)) || (isClient && _ws != null && !awaitingApproval);

  /// Gast: Host muss den Beitritt noch bestätigen.
  bool awaitingApproval = false;

  /// Gast: Host hat den Beitritt abgelehnt.
  bool denied = false;

  Iterable<_Peer> get _approved => _peers.where((p) => p.approved);

  /// Anzahl der anderen verbundenen Geräte.
  int get peerCount => isHost ? _approved.length : (isConnected ? max(1, remoteDevices - 1) : 0);

  /// Gast: Zahl der Anzeige-Geräte, die mit dem Host verbunden sind.
  int remoteViewers = 0;

  /// Ist irgendwo eine Anzeige (Punktetafel) verbunden?
  bool get hasViewer =>
      isHost ? _approved.any((p) => p.viewer) : (isConnected && (joinedAsViewer || remoteViewers > 0));

  List<String> get peerNames => [for (final p in _approved) p.viewer ? '${p.name} · Anzeige' : p.name];

  // ---------------------------------------------------------------- Host

  /// WLAN: eigenen kleinen Server öffnen (nur Android).
  Future<void> startHost({int preferredPort = defaultPort}) async {
    await stop();
    mode = LinkMode.lan;
    code = Store.roomCode;
    _server = await LanServer.bind(
      preferredPort: preferredPort,
      info: () => code == null ? null : _roomInfo(),
      gate: _lanGate,
      onPeer: (socket, query) => _addPeer(socket, byCode: query['code'] == code),
    );
    port = _server!.port;
    role = LinkRole.host;
    status = 'Raum offen';
    addresses = await localAddresses();
    await _acquireMulticast();
    _announce = Timer.periodic(const Duration(seconds: 1), (_) => _sendAnnouncement());
    _sendAnnouncement();
    _remember({'role': 'host'});
    notifyListeners();
  }

  /// WLAN: Sperrliste und Code prüfen, bevor die Verbindung angenommen wird
  /// (0 = annehmen, sonst HTTP-Status).
  Future<int> _lanGate(String ip, Map<String, String> query) async {
    final now = DateTime.now();
    final fails = (_fails[ip] ?? [])..removeWhere((t) => now.difference(t) > failWindow);
    if (fails.length >= maxFails) {
      ErrorLog.crumb('Kopplung: $ip gesperrt (zu viele falsche Codes)');
      return 429;
    }
    final byKey = query['auth'] == '1';
    final byCode = query['code'] == code;
    if (!byKey && !byCode) {
      _fails[ip] = fails..add(now);
      return 403;
    }
    if (_peers.length >= maxPeers) return 503;
    _fails.remove(ip);
    return 0;
  }

  /// Online: Raum auf dem Vermittlungs-Server öffnen bzw. den eigenen zurückholen.
  ///
  /// Der Raum-Code kommt vom Server (6 Zeichen) und wird mit dem Token gemerkt, damit
  /// er nach Abbruch/Neustart gleich bleibt. Wirft [LinkException], wenn der Server
  /// nicht erreichbar ist oder ablehnt.
  Future<void> startOnlineHost({String? serverUrl}) async {
    await stop();
    mode = LinkMode.online;
    final r = RelayHost(ServerConfig.relayUri(serverUrl), room: Store.onlineRoom, token: Store.onlineToken);
    _relayHost = r;
    r.onHosted = (room, token, resumed) {
      if (_relayHost != r) return;
      Store.onlineRoom = room;
      Store.onlineToken = token;
      code = room;
      ErrorLog.crumb('Online-Raum ${resumed ? 'zurückgeholt' : 'geöffnet'}');
      notifyListeners();
      // Nach dem Zurückholen bekommen wieder verbundene Gäste ihren Stand über „hello“.
    };
    r.onPeer = (socket) {
      if (_relayHost == r) _addPeer(socket, byCode: true);
    };
    r.onStatus = (st, text) {
      if (_relayHost != r) return;
      relayStatus = st;
      status = text;
      notifyListeners();
    };
    r.onUpdateRequired = (info) => onUpdateRequired?.call(info);
    role = LinkRole.host;
    relayStatus = RelayStatus.connecting;
    status = 'Verbinde mit Server …';
    notifyListeners();
    r.start();
    final err = await r.first;
    if (_relayHost != r) throw LinkException('Abgebrochen');
    if (err != null) {
      await stop();
      status = err;
      notifyListeners();
      throw LinkException(err);
    }
    _remember({'role': 'host', 'mode': 'online'});
  }

  /// Neue Verbindung eines Gasts (WLAN oder online).
  ///
  /// [byCode]: mit richtigem Raum-Code gekommen. Online prüft den Code der Server beim
  /// Beitritt – neue Geräte brauchen trotzdem die Freigabe am Host.
  void _addPeer(PeerSocket socket, {required bool byCode}) {
    if (_peers.length >= maxPeers) {
      socket.close();
      return;
    }
    final peer = _Peer(socket, socket.remote)..byCode = byCode;
    _peers.add(peer);
    socket.messages.listen(
      (data) => _hostReceive(peer, data),
      onDone: () => _dropPeer(peer),
      onError: (_) => _dropPeer(peer),
      cancelOnError: true,
    );
    // Ohne „hello“ innerhalb kurzer Zeit wieder trennen.
    Timer(const Duration(seconds: 10), () {
      if (!peer.helloSeen && _peers.contains(peer)) peer.ws.close();
    });
  }

  void _dropPeer(_Peer p) {
    if (_peers.remove(p) && p.approved) {
      notifyListeners();
      broadcastState();
    }
  }

  Future<void> _deny(_Peer peer, [String reason = '']) async {
    _send(peer.ws, {'t': 'denied', 'reason': reason});
    await peer.ws.close();
  }

  Future<void> _onHello(_Peer peer, Map<String, dynamic> msg) async {
    if (peer.helloSeen) return;
    peer.helloSeen = true;
    final device = '${msg['device'] ?? ''}';
    final name = '${msg['name'] ?? 'Gerät'}';
    peer.device = device.length > 64 ? device.substring(0, 64) : device;
    peer.name = name.length > 40 ? name.substring(0, 40) : name;
    peer.viewer = msg['viewer'] == true;
    if (peer.device.isEmpty) return _deny(peer);
    // Zu alte App? Dann gar nicht erst koppeln – der Gast bekommt „Bitte aktualisieren“.
    final guestCompat = msg['compat'];
    if ((guestCompat is num ? guestCompat.toInt() : 2) < minCompat) {
      ErrorLog.crumb('Kopplung: ${peer.name} hat eine zu alte App');
      return _deny(peer, 'update');
    }

    // Bekanntes Gerät mit Schlüssel: gegenseitiger Nachweis, kein Code nötig.
    if (msg['auth'] == true) {
      final key = Store.guestKey(peer.device);
      final nonce = '${msg['nonce'] ?? ''}';
      if (key == null || nonce.length < 16) return _deny(peer, 'unknown');
      peer.key = key;
      peer.challenge = randomHex(16);
      _send(peer.ws, {
        't': 'auth',
        if (compat > 0) 'compat': compat,
        'hostDevice': Store.deviceId,
        'proof': authProof(key, 'host', nonce, Store.deviceId),
        'nonce': peer.challenge,
      });
      return;
    }

    // Neues Gerät (mit Code): nur nach Erlaubnis am Host.
    if (!peer.byCode) return _deny(peer);
    var ok = trustAll;
    if (!ok) {
      _send(peer.ws, {'t': 'pending'});
      ErrorLog.crumb('Kopplung: ${peer.name} fragt nach Erlaubnis');
      ok = await onJoinRequest?.call(peer.device, peer.name) ?? false;
      if (!_peers.contains(peer)) return; // inzwischen getrennt
      if (!ok) return _deny(peer);
    }
    final key = randomHex(32);
    Store.trustGuest(peer.device, peer.name, key);
    _send(peer.ws, {'t': 'welcome', if (compat > 0) 'compat': compat, 'key': key, 'hostDevice': Store.deviceId});
    _approve(peer);
  }

  void _onAuthReply(_Peer peer, Map<String, dynamic> msg) {
    final key = peer.key, ch = peer.challenge;
    if (peer.approved || key == null || ch == null) return;
    peer.challenge = null;
    if (msg['proof'] != authProof(key, 'guest', ch, peer.device)) {
      _deny(peer, 'unknown');
      return;
    }
    _approve(peer);
  }

  void _approve(_Peer peer) {
    peer.approved = true;
    notifyListeners();
    _send(peer.ws, _stateMessage(full: true));
    broadcastState();
  }

  void _hostReceive(_Peer peer, Object? data) {
    final msg = _decode(data);
    if (msg == null) return;
    if (msg['t'] == 'hello') {
      _onHello(peer, msg);
      return;
    }
    if (msg['t'] == 'auth2') {
      _onAuthReply(peer, msg);
      return;
    }
    // Nicht erlaubte Geräte dürfen nichts tun.
    if (!peer.approved) return;
    switch (msg['t']) {
      case 'mode':
        peer.viewer = msg['viewer'] == true;
        notifyListeners();
      case 'dart' || 'undo' || 'start' || 'board' || 'boardNo':
        // Anzeige-Geräte dürfen nichts eintragen. Absender mitgeben (Scheiben-Zuordnung).
        if (!peer.viewer) onHostMessage?.call({...msg, '_dev': peer.device, '_name': peer.name});
      case 'share':
        // an die anderen Gäste weiterreichen und selbst anzeigen
        for (final p in _approved) {
          if (p != peer) _send(p.ws, msg);
        }
        onShare?.call(Map<String, dynamic>.from(msg['pkg'] as Map), msg['from'] as String? ?? peer.name);
      case 'have' || 'syncpkg' || 'syncreq':
        onSync?.call(msg, (m) => _send(peer.ws, m), peer.name);
        // Neue Daten von einem Gast → die anderen Gäste ebenfalls abgleichen lassen
        if (msg['t'] == 'syncpkg') {
          for (final p in _approved) {
            if (p != peer) _send(p.ws, {'t': 'syncreq'});
          }
        }
      default:
        onHostMessage?.call(msg);
    }
  }

  /// Zuletzt an alle gesendetes Turnier (gleiches Objekt = unverändert).
  Object? _lastTour;
  Object? _tourOfLast;

  /// Stand für die Gäste. Ein unverändertes Turnier wird nicht jedes Mal mitgeschickt.
  Map<String, dynamic> _stateMessage({bool full = false}) {
    final st = {
      't': 'state',
      'devices': _approved.length + 1,
      'viewers': _approved.where((p) => p.viewer).length,
      'host': Store.deviceName,
      'hostDevice': Store.deviceId,
      ...?hostState?.call(),
    };
    final tour = st['tournament'];
    _tourOfLast = tour;
    if (!full && tour != null && identical(tour, _lastTour)) {
      st.remove('tournament');
      st['tsame'] = true;
    }
    return st;
  }

  /// Host: aktuellen Stand an alle Gäste schicken.
  void broadcastState() {
    if (!isHost || _approved.isEmpty) return;
    // Mehrere Änderungen kurz hintereinander (z. B. Dart + Speichern) nur einmal senden.
    if (_bcTimer?.isActive ?? false) return;
    _bcTimer = Timer(const Duration(milliseconds: 60), _broadcastNow);
  }

  Timer? _bcTimer;

  void _broadcastNow() {
    final peers = _approved.toList();
    if (!isHost || peers.isEmpty) return;
    final sw = Stopwatch()..start();
    final msg = _stateMessage();
    // Alle bekommen dieses Turnier jetzt – beim nächsten Mal reicht „unverändert“.
    _lastTour = _tourOfLast;
    ErrorLog.crumb('Stand an ${peers.length} Gerät(e) gesendet (${sw.elapsedMilliseconds} ms)');
    for (final p in peers) {
      _send(p.ws, msg);
    }
  }

  /// Was die Suche über den Raum erfährt – bewusst ohne Code.
  Map<String, dynamic> _roomInfo() => {
        'app': 'darts_counter',
        'v': 2,
        'port': port,
        'name': Store.deviceName,
        'device': Store.deviceId,
      };

  void _sendAnnouncement() {
    final s = _server;
    if (s == null || code == null) return;
    final payload = utf8.encode(jsonEncode(_roomInfo()));
    final targets = <String>{'255.255.255.255'};
    for (final a in addresses) {
      final parts = a.split('.');
      if (parts.length == 4) targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
    }
    s.announce(payload, targets, discoveryPort);
  }

  /// Test: alle Gäste hart trennen, Server läuft weiter.
  @visibleForTesting
  Future<void> dropAllForTest() async {
    for (final p in List.of(_peers)) {
      await p.ws.close();
    }
  }

  // ---------------------------------------------------------------- Gast

  /// Verbindet sich mit einem Raum. Liefert false bei falschem Code / nicht erreichbar.
  /// Gast: zuletzt gespeichertes Host-Gerät dieser Verbindung.
  String? _remembered;

  /// Gast ist als reine Anzeige verbunden (wird bei bekannten Geräten gemerkt).
  bool joinedAsViewer = false;

  /// Gast: erwartetes Host-Gerät (bei bekannten Geräten) und ob per Schlüssel angemeldet wird.
  String? _expectHost;
  bool _byKey = false;
  String? _nonce;

  /// Verbindet sich mit einem Raum. Hat das Gerät für [hostDevice] einen Schlüssel,
  /// wird kein Code gesendet, und der Host muss sich selbst ausweisen.
  Future<bool> join(String address, int port, String roomCode,
      {String? name, bool viewer = false, String? hostDevice}) async {
    await stop();
    mode = LinkMode.lan;
    _prepareClient(roomCode, name: name, viewer: viewer, hostDevice: hostDevice);
    hostAddress = address;
    hostPort = port;
    notifyListeners();
    final ok = await _connect();
    if (!ok) {
      _wantConnected = false;
      role = LinkRole.none;
      status = 'Verbindung fehlgeschlagen';
      notifyListeners();
    } else {
      _clientSession();
    }
    return ok;
  }

  void _prepareClient(String roomCode, {String? name, bool viewer = false, String? hostDevice}) {
    _expectHost = hostDevice;
    _byKey = hostDevice != null &&
        (Store.knownHosts.where((h) => h.device == hostDevice).firstOrNull?.key?.isNotEmpty ?? false);
    _remembered = null;
    _lastTourIn = null;
    awaitingApproval = false;
    denied = false;
    versionMismatch = null;
    joinedAsViewer = viewer;
    role = LinkRole.client;
    hostAddress = null;
    hostPort = null;
    code = roomCode;
    hostName = name;
    _wantConnected = true;
    status = 'Verbinde …';
  }

  /// Online: einem Raum auf dem Vermittlungs-Server beitreten (Code mit 6 Zeichen).
  ///
  /// Liefert false, wenn der Server nicht erreichbar ist oder den Code nicht kennt
  /// ([status] enthält dann die Meldung). Ist der Host gerade offline, ist der Beitritt
  /// trotzdem erfolgreich – die Verbindung entsteht, sobald er wieder da ist.
  /// Hat das Gerät für [hostDevice] einen Schlüssel, meldet es sich damit an
  /// (keine erneute Freigabe nötig).
  Future<bool> joinOnline(String roomCode,
      {String? name, bool viewer = false, String? hostDevice, String? serverUrl}) async {
    await stop();
    final room = RoomCode.normalize(roomCode);
    if (!RoomCode.isValid(room)) {
      status = 'Der Raum-Code hat ${RoomCode.length} Zeichen (Buchstaben und Ziffern).';
      notifyListeners();
      return false;
    }
    mode = LinkMode.online;
    _prepareClient(room, name: name, viewer: viewer, hostDevice: hostDevice);
    final g = RelayGuest(ServerConfig.relayUri(serverUrl), room: room);
    _relayGuest = g;
    g.onHostSocket = (socket) {
      if (_relayGuest == g) _attach(socket);
    };
    g.onStatus = (st, text) {
      if (_relayGuest != g) return;
      relayStatus = st;
      if (st == RelayStatus.closed || st == RelayStatus.failed) {
        _wantConnected = false;
        _forget();
        status = text;
      } else if (st != RelayStatus.online || _ws == null) {
        status = text;
      }
      notifyListeners();
    };
    g.onUpdateRequired = (info) => onUpdateRequired?.call(info);
    relayStatus = RelayStatus.connecting;
    notifyListeners();
    g.start();
    final err = await g.first;
    if (_relayGuest != g) return false;
    if (err != null) {
      _relayGuest = null;
      await g.close();
      _wantConnected = false;
      role = LinkRole.none;
      relayStatus = null;
      status = err;
      notifyListeners();
      return false;
    }
    _clientSession();
    return true;
  }

  Future<bool> _connect() async {
    try {
      final q = _byKey ? 'auth=1' : 'code=${Uri.encodeQueryComponent(code ?? '')}';
      final ws = await lanConnect(hostAddress ?? '', hostPort ?? defaultPort, q, const Duration(seconds: 5));
      _attach(ws);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Neue Verbindung zum Host: anmelden (mit Schlüssel oder Code) und lauschen.
  void _attach(PeerSocket ws) {
    _ws = ws;
    status = 'Verbunden';
    _nonce = randomHex(16);
    _send(ws, {
      't': 'hello',
      if (compat > 0) 'compat': compat,
      'device': deviceForTest ?? Store.deviceId,
      'name': Store.deviceName,
      'viewer': joinedAsViewer,
      if (_byKey) 'auth': true,
      if (_byKey) 'nonce': _nonce,
    });
    if (_byKey) awaitingApproval = true;
    ws.messages.listen(
      _clientReceive,
      onDone: () => _lostHost(ws),
      onError: (_) => _lostHost(ws),
      cancelOnError: true,
    );
    notifyListeners();
  }

  /// Gast gibt auf (abgelehnt / Host nicht ausgewiesen): online auch den Raum verlassen.
  void _giveUp() {
    final g = _relayGuest;
    _relayGuest = null;
    if (g != null) unawaited(g.close());
  }

  void _lostHost(PeerSocket ws) {
    // Eine ältere Sitzung (online nach „Host wieder da“) darf die neue nicht abräumen.
    if (!identical(_ws, ws)) return;
    _ws = null;
    if (!_wantConnected) return;
    if (isOnline) {
      // Online baut das Relais die Verbindung selbst wieder auf.
      final g = _relayGuest;
      status = g == null || g.status == RelayStatus.online ? 'Verbindung verloren – verbinde neu …' : g.statusText;
      notifyListeners();
      return;
    }
    status = 'Verbindung verloren – verbinde neu …';
    notifyListeners();
    _retry?.cancel();
    _retry = Timer.periodic(const Duration(seconds: 2), (t) async {
      if (!_wantConnected) {
        t.cancel();
        return;
      }
      if (_ws != null) return;
      if (await _connect()) t.cancel();
    });
  }

  /// Gast: zuletzt empfangenes Turnier (für „unverändert“-Stände).
  Object? _lastTourIn;

  /// Gast: wegen der App-Version aufhören (Kopplung bleibt gespeichert – nach dem Update geht es weiter).
  void _versionStop(VersionMismatch why) {
    awaitingApproval = false;
    denied = true;
    _wantConnected = false;
    versionMismatch = why;
    status = why == VersionMismatch.selfTooOld
        ? 'Diese App ist zu alt für den Raum – bitte aktualisieren'
        : 'Das Raum-Gerät hat eine ältere App – bitte dort aktualisieren';
    ErrorLog.crumb('Kopplung: Versionskonflikt (${why.name})');
    _ws?.close();
    _giveUp();
    notifyListeners();
    onVersionMismatch?.call(why);
  }

  void _clientReceive(Object? data) {
    final msg = _decode(data);
    if (msg == null) return;
    // Raum-Gerät zu alt für diese App? (Hosts bis 3.0.0 schicken keine Angabe → 2)
    if (msg['t'] == 'auth' || msg['t'] == 'welcome') {
      final hc = msg['compat'];
      if ((hc is num ? hc.toInt() : 2) < minCompat) {
        _versionStop(VersionMismatch.hostTooOld);
        return;
      }
    }
    switch (msg['t']) {
      case 'auth':
        // Host muss beweisen, dass er der bekannte ist – sonst sofort trennen.
        final key = Store.knownHosts.where((h) => h.device == _expectHost).firstOrNull?.key;
        final ok = key != null &&
            msg['hostDevice'] == _expectHost &&
            msg['proof'] == authProof(key, 'host', _nonce ?? '', _expectHost ?? '');
        if (!ok) {
          _forget();
          _wantConnected = false;
          awaitingApproval = false;
          denied = true;
          status = 'Das Gerät konnte sich nicht ausweisen – Verbindung abgebrochen';
          ErrorLog.crumb('Kopplung: Host-Nachweis falsch, getrennt');
          _ws?.close();
          _giveUp();
          notifyListeners();
          return;
        }
        sendToHost({'t': 'auth2', 'proof': authProof(key, 'guest', '${msg['nonce']}', deviceForTest ?? Store.deviceId)});
      case 'welcome':
        final hd = '${msg['hostDevice'] ?? ''}';
        final key = msg['key'] as String?;
        if (hd.isNotEmpty && key != null && key.length >= 32) {
          _expectHost = hd;
          Store.rememberHost(_hostEntry(hd, key: key));
          // Wiederverbinden ab jetzt mit Schlüssel
          _byKey = true;
          _remembered = hd;
          _clientSession();
        }
      case 'pending':
        awaitingApproval = true;
        status = 'Warte auf Bestätigung am anderen Gerät …';
        notifyListeners();
      case 'denied' when msg['reason'] == 'update':
        _versionStop(VersionMismatch.selfTooOld);
      case 'denied':
        awaitingApproval = false;
        denied = true;
        _wantConnected = false;
        _forget();
        if (msg['reason'] == 'unknown' && _expectHost != null) {
          // Host kennt den Schlüssel nicht mehr → beim nächsten Mal mit Code neu koppeln.
          Store.setHostKey(_expectHost!, null);
          status = 'Dieses Gerät ist dort nicht mehr erlaubt – bitte mit Code neu koppeln';
        } else {
          status = 'Das andere Gerät hat die Verbindung abgelehnt';
        }
        _giveUp();
        notifyListeners();
      case 'state':
        if (awaitingApproval) {
          awaitingApproval = false;
          status = 'Verbunden';
        }
        if (msg['tsame'] == true) {
          msg['tournament'] = _lastTourIn;
        } else {
          _lastTourIn = msg['tournament'];
        }
        remoteDevices = (msg['devices'] as num?)?.toInt() ?? 2;
        remoteViewers = (msg['viewers'] as num?)?.toInt() ?? 0;
        hostName = msg['host'] as String? ?? hostName;
        final hd = msg['hostDevice'] as String?;
        // Nur ein ausgewiesener Host (Schlüssel) bzw. ein per Code erlaubter wird gemerkt.
        if (hd != null && hd != _remembered && (!_byKey || hd == _expectHost)) {
          _remembered = hd;
          Store.rememberHost(_hostEntry(hd));
        }
        notifyListeners();
        onState?.call(msg);
      case 'share':
        onShare?.call(Map<String, dynamic>.from(msg['pkg'] as Map), msg['from'] as String? ?? 'Anderes Gerät');
      case 'direct':
        onDirect?.call(msg);
      case 'have' || 'syncpkg' || 'syncreq':
        onSync?.call(msg, sendToHost, hostName ?? 'Host');
    }
  }

  /// Eintrag für „Bekannte Geräte“: WLAN-Angaben und Online-Raum bleiben jeweils erhalten,
  /// wenn das Gerät auf dem anderen Weg schon bekannt war.
  KnownHost _hostEntry(String hd, {String? key}) {
    final old = Store.knownHosts.where((h) => h.device == hd).firstOrNull;
    return KnownHost(
      device: hd,
      name: hostName ?? 'Gerät',
      address: isOnline ? (old?.address ?? '') : (hostAddress ?? ''),
      port: isOnline ? (old?.port ?? defaultPort) : (hostPort ?? defaultPort),
      code: isOnline ? (old?.code ?? '') : (code ?? ''),
      viewer: joinedAsViewer,
      key: key,
      room: isOnline ? code : old?.room,
    );
  }

  /// Gast: zwischen Mitspielen und reiner Anzeige wechseln.
  void setViewerMode(bool viewer) {
    joinedAsViewer = viewer;
    sendToHost({'t': 'mode', 'viewer': viewer});
    final hd = _remembered ?? _expectHost;
    final h = Store.knownHosts.where((x) => x.device == hd).firstOrNull;
    if (h != null) {
      Store.rememberHost(h.copyWith(viewer: viewer));
    }
    notifyListeners();
  }

  /// Gast: Nachricht an den Host.
  void sendToHost(Map<String, dynamic> msg) {
    final ws = _ws;
    if (ws != null) _send(ws, msg);
  }

  /// Abgleich anstoßen: Gast schickt seine Übersicht an den Host, der Host bittet alle Gäste darum.
  void requestSync(Map<String, dynamic> Function() have) {
    if (isHost) {
      for (final p in _approved) {
        _send(p.ws, {'t': 'syncreq'});
      }
    } else if (_ws != null) {
      sendToHost({'t': 'have', 'have': have(), 'reply': true});
    }
  }

  /// Spielerdaten an alle anderen gekoppelten Geräte.
  void sendShare(SharePackage pkg) {
    final msg = {'t': 'share', 'pkg': pkg.toJson(), 'from': Store.deviceName};
    if (isHost) {
      for (final p in _approved) {
        _send(p.ws, msg);
      }
    } else {
      sendToHost(msg);
    }
  }

  // ---------------------------------------------------------------- Raumsuche

  Future<void> startDiscovery({@visibleForTesting bool includeSelf = false}) async {
    if (_udpListen != null || !lanAvailable) return;
    await _acquireMulticast();
    _udpListen = await LanListener.bind(discoveryPort, (address, payload) {
      try {
        final j = jsonDecode(payload);
        if (j is! Map || j['app'] != 'darts_counter') return;
        if (!includeSelf && j['device'] == Store.deviceId) return;
        _addRoom(address, Map<String, dynamic>.from(j), includeSelf: includeSelf);
      } catch (_) {}
    });
    _prune = Timer.periodic(const Duration(seconds: 2), (_) {
      final now = DateTime.now();
      final list = rooms.value.where((r) => now.difference(r.seen).inSeconds < 9).toList();
      if (list.length != rooms.value.length) rooms.value = list;
    });
    // Viele Router und manche Handys verwerfen Broadcasts. Darum:
    // bekannte und gefundene Geräte alle 2 s direkt fragen, das ganze Netz gebremst durchsuchen.
    _includeSelf = includeSelf;
    _scanTimer = Timer.periodic(const Duration(seconds: 2), (_) => _quickProbe());
    _quickProbe();
    _scanNetwork(includeSelf: includeSelf);
  }

  Timer? _scanTimer;
  Timer? _sweepAgain;
  bool _scanning = false;
  bool _quick = false;
  bool _includeSelf = false;

  /// Netzsuche: so viele neue Adressen je [scanTick] (≈ 240 pro Sekunde).
  /// Gemessen: Android hält max. 1024 Nachbarn, jede gefragte Adresse bleibt ~3 s drin.
  static const scanBatch = 120;
  static const scanTick = Duration(milliseconds: 500);

  /// Pause zwischen zwei kompletten Durchläufen.
  static const sweepPause = Duration(seconds: 30);

  /// Bekannte Geräte und gefundene Räume direkt fragen (auf ihrem eigenen Port).
  Future<void> _quickProbe() async {
    if (_quick || _scanTimer == null) return;
    _quick = true;
    final client = LanProber(const Duration(milliseconds: 1500));
    try {
      final targets = <(String, int)>{
        for (final h in Store.knownHosts)
          if (h.address.isNotEmpty) (h.address, h.port),
        for (final r in rooms.value) (r.address, r.port),
      };
      await Future.wait([for (final (a, p) in targets) _probe(client, a, _includeSelf, port: p, patient: true)]);
    } finally {
      client.close();
      _quick = false;
    }
  }

  /// Fortschritt der Netzsuche (geprüft, gesamt).
  final scanProgress = ValueNotifier<(int, int)>((0, 0));

  void _addRoom(String address, Map<String, dynamic> j, {bool includeSelf = false}) {
    if (j['app'] != 'darts_counter') return;
    if (!includeSelf && j['device'] == Store.deviceId) return;
    final name = '${j['name'] ?? 'Gerät'}';
    final room = Room(
      address: address,
      port: (j['port'] as num?)?.toInt() ?? defaultPort,
      code: j['code'] as String?,
      name: name.length > 40 ? name.substring(0, 40) : name,
      device: '${j['device'] ?? ''}',
    );
    // Gespeicherte Adressen werden hier bewusst NICHT überschrieben: Suchmeldungen sind
    // nicht beglaubigt. Erst eine echte, ausgewiesene Verbindung merkt sich die Adresse.
    rooms.value = rooms.value.where((r) => r.device != room.device).toList()..add(room);
  }

  /// Fester Anfang der eigenen Netzadresse (z. B. "10.192." bei /19, "192.168.0." bei /24).
  static String networkPrefix(String own, int prefix) {
    final p = own.split('.');
    if (p.length != 4) return '';
    final fixed = prefix >= 24 ? 3 : (prefix >= 16 ? 2 : 1);
    return '${p.take(fixed).join('.')}.';
  }

  /// Kurzform einer Adresse ohne den festen Netzanfang (z. B. "63.187").
  static String shortAddress(String address, String prefix) =>
      prefix.isNotEmpty && address.startsWith(prefix) ? address.substring(prefix.length) : address;

  /// Ergänzt eine Kurzeingabe wie "63.187" mit dem eigenen Netzanfang zur vollen Adresse.
  static String completeAddress(String input, String prefix) {
    final t = input.trim();
    if (t.split('.').length >= 4 || prefix.isEmpty) return t;
    final need = 4 - t.split('.').length;
    final pre = prefix.split('.').where((x) => x.isNotEmpty).toList();
    if (pre.length < need) return t;
    return '${pre.take(need).join('.')}.$t';
  }

  /// Höchstens so viele Adressen werden pro Suchlauf abgefragt.
  static const maxScan = 8192;

  static int _ip(String a) {
    final p = a.split('.').map(int.parse).toList();
    return (p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3];
  }

  static String _str(int v) => '${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}';

  static bool _private(String a) {
    final p = a.split('.').map(int.parse).toList();
    return p[0] == 10 || (p[0] == 172 && p[1] >= 16 && p[1] < 32) || (p[0] == 192 && p[1] == 168);
  }

  /// Eigene Adressen mit Netzgröße (Präfix). Auf Android vom System, sonst /24.
  static Future<List<(String, int)>> networks() async {
    final out = await lanNetworks();
    return [for (final n in out) if (_private(n.$1)) n];
  }

  /// Adressen im eigenen Netz, nach Nähe zur eigenen Adresse sortiert
  /// (große Netze wie /19 werden so zuerst in der Nachbarschaft durchsucht).
  static List<String> targetsFor(String own, int prefix, {int limit = maxScan}) {
    final p = prefix.clamp(16, 30);
    final me = _ip(own);
    final mask = p == 0 ? 0 : (0xFFFFFFFF << (32 - p)) & 0xFFFFFFFF;
    final net = me & mask;
    final last = net | (~mask & 0xFFFFFFFF);
    final out = <String>[];
    for (var d = 1; out.length < limit; d++) {
      final lo = me - d, hi = me + d;
      final loOk = lo > net, hiOk = hi < last;
      if (!loOk && !hiOk) break;
      if (hiOk) out.add(_str(hi));
      if (loOk && out.length < limit) out.add(_str(lo));
    }
    return out;
  }

  /// Alle Suchziele über alle eigenen Netze.
  static Future<List<String>> scanTargets() async {
    final out = <String>{};
    final nets = await networks();
    final own = {for (final n in nets) n.$1};
    for (final n in nets) {
      out.addAll(targetsFor(n.$1, n.$2, limit: maxScan ~/ nets.length));
    }
    out.removeAll(own);
    return out.toList();
  }

  Future<void> _scanNetwork({bool includeSelf = false}) async {
    if (_scanning || _scanTimer == null) return;
    _scanning = true;
    final client = LanProber(const Duration(milliseconds: 1200));
    final pending = <Future<void>>[];
    try {
      final known = {for (final h in Store.knownHosts) h.address};
      final targets = (await scanTargets()).where((a) => !known.contains(a)).toList();
      scanProgress.value = (0, targets.length);
      // Gleichmäßiges Tempo statt großer Schübe: Android merkt sich jede gefragte Adresse
      // ~3 s in der Nachbar-Tabelle (max. 1024 Einträge). Zu viele auf einmal → Tabelle voll,
      // und die Antwort des echten Geräts geht verloren.
      for (var i = 0; i < targets.length && _scanTimer != null; i += scanBatch) {
        final tick = Stopwatch()..start();
        for (final t in targets.skip(i).take(scanBatch)) {
          final f = _probe(client, t, includeSelf);
          pending.add(f);
          f.whenComplete(() => pending.remove(f));
        }
        scanProgress.value = (min(i + scanBatch, targets.length), targets.length);
        final rest = scanTick - tick.elapsed;
        if (rest > Duration.zero) await Future<void>.delayed(rest);
      }
      await Future.wait(List.of(pending));
    } finally {
      client.close();
      _scanning = false;
      // Nach einem kompletten Durchlauf erst nach einer Pause wieder (Akku, Router).
      if (_scanTimer != null) {
        _sweepAgain?.cancel();
        _sweepAgain = Timer(sweepPause, () => _scanNetwork(includeSelf: includeSelf));
      }
    }
  }

  Future<void> _probe(LanProber client, String address, bool includeSelf,
      {int port = defaultPort, bool patient = false}) async {
    final j = await client.info(address, port, patient: patient);
    if (j != null) _addRoom(address, j, includeSelf: includeSelf);
  }

  void stopDiscovery() {
    _udpListen?.close();
    _udpListen = null;
    _prune?.cancel();
    _scanTimer?.cancel();
    _scanTimer = null;
    _sweepAgain?.cancel();
    _sweepAgain = null;
    scanProgress.value = (0, 0);
    rooms.value = [];
  }

  // ---------------------------------------------------------------- Allgemein

  /// Kopplung beenden. Die gemerkte Sitzung bleibt (Neustart stellt sie wieder her).
  ///
  /// [closeRoom]: Online-Host schließt den Raum auf dem Server (Close-Code 4000) –
  /// sonst gilt das Beenden dort nur als „Host offline“ und die Gäste warten.
  Future<void> stop({bool closeRoom = false}) async {
    _wantConnected = false;
    // Gemerkte Kopplung bleibt bestehen (Absturz/Beenden) – nur [leave] löscht sie.
    _session = null;
    _sessionBeat?.cancel();
    _sessionBeat = null;
    _retry?.cancel();
    _announce?.cancel();
    _announce = null;
    // Relais zuerst schließen: Die virtuellen Kanäle enden dann ohne „kick“,
    // die Gäste bleiben im Raum und warten auf den Host.
    final rh = _relayHost;
    _relayHost = null;
    if (rh != null) await (closeRoom ? rh.closeRoom() : rh.close());
    final rg = _relayGuest;
    _relayGuest = null;
    if (rg != null) await rg.close();
    for (final p in List.of(_peers)) {
      await p.ws.close();
    }
    _peers.clear();
    await _server?.close();
    _server = null;
    await _ws?.close();
    _ws = null;
    role = LinkRole.none;
    status = '';
    relayStatus = null;
    remoteDevices = 0;
    if (_udpListen == null) await _releaseMulticast();
    notifyListeners();
  }

  static Future<List<String>> localAddresses() => lanLocalAddresses();

  Future<void> _acquireMulticast() => lanMulticast(true);

  Future<void> _releaseMulticast() => lanMulticast(false);

  static Map<String, dynamic>? _decode(Object? data) {
    if (data is! String || data.length > maxMessage) return null;
    try {
      final j = jsonDecode(data);
      return j is Map ? Map<String, dynamic>.from(j) : null;
    } catch (_) {
      return null;
    }
  }

  static void _send(PeerSocket ws, Map<String, dynamic> msg) {
    try {
      ws.send(jsonEncode(msg));
    } catch (_) {}
  }
}

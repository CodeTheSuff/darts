import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/error_log.dart';
import '../data/storage.dart';
import '../data/sync.dart';

enum LinkRole { none, host, client }

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
  final WebSocket ws;
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

/// Kopplung mehrerer Handys im lokalen Netz (WLAN oder Hotspot).
///
/// Ein Gerät ist Host (kleiner WebSocket-Server), die anderen verbinden sich.
/// Der Host ist die Schiedsstelle: Würfe der Gäste gehen an ihn, er schickt
/// den neuen Stand an alle.
class Link extends ChangeNotifier {
  Link._();
  static final Link I = Link._();

  /// Eigene Instanz für Tests (Host und Gast im selben Prozess).
  @visibleForTesting
  factory Link.forTest() => Link._()..trustAll = true;

  /// Test: jedes Gerät ohne Nachfrage erlauben.
  @visibleForTesting
  bool trustAll = false;

  /// Host: fragt, ob ein neues Gerät beitreten darf (true = erlauben und merken).
  Future<bool> Function(String device, String name)? onJoinRequest;

  static const maxPeers = 8;
  static const maxFails = 5;
  static const failWindow = Duration(minutes: 10);

  /// Max. Größe einer Nachricht (größere werden verworfen).
  static const maxMessage = 16 * 1024 * 1024;

  /// Falsche Code-Versuche je Adresse (Zeitpunkte).
  final Map<String, List<DateTime>> _fails = {};

  static const defaultPort = 47123;
  static const discoveryPort = 47124;
  static const _channel = MethodChannel('darts/net');

  LinkRole role = LinkRole.none;
  String? code;
  int port = 0;
  List<String> addresses = [];
  String status = '';

  // Host
  HttpServer? _server;
  final List<_Peer> _peers = [];
  Timer? _announce;
  RawDatagramSocket? _udpSend;

  // Gast
  WebSocket? _ws;
  String? hostAddress;
  int? hostPort;
  String? hostName;
  bool _wantConnected = false;
  Timer? _retry;
  int remoteDevices = 0;

  // Raumsuche
  final rooms = ValueNotifier<List<Room>>([]);
  RawDatagramSocket? _udpListen;
  Timer? _prune;

  // ---------------------------------------------------------------- Anbindung an die App
  /// Host: aktueller Stand (laufendes Match, Turnier), der an alle geht.
  Map<String, dynamic> Function()? hostState;

  /// Host: Nachricht eines Gasts (dart, undo, start).
  void Function(Map<String, dynamic> msg)? onHostMessage;

  /// Gast: neuer Stand vom Host.
  void Function(Map<String, dynamic> state)? onState;

  /// Eingehende Spielerdaten.
  void Function(Map<String, dynamic> pkg, String from)? onShare;

  /// Abgleich-Nachrichten (have / syncpkg / syncreq) mit Antwortfunktion an den Absender.
  void Function(Map<String, dynamic> msg, void Function(Map<String, dynamic>) reply, String from)? onSync;

  bool get isHost => role == LinkRole.host;
  bool get isClient => role == LinkRole.client;
  bool get isConnected => isHost || (isClient && _ws != null && !awaitingApproval);

  /// Gast: Host muss den Beitritt noch bestätigen.
  bool awaitingApproval = false;

  /// Gast: Host hat den Beitritt abgelehnt.
  bool denied = false;

  Iterable<_Peer> get _approved => _peers.where((p) => p.approved);

  /// Anzahl der anderen verbundenen Geräte.
  int get peerCount => isHost ? _approved.length : (isConnected ? max(1, remoteDevices - 1) : 0);

  List<String> get peerNames => [for (final p in _approved) p.viewer ? '${p.name} · Anzeige' : p.name];

  // ---------------------------------------------------------------- Host

  Future<void> startHost({int preferredPort = defaultPort}) async {
    await stop();
    code = Store.roomCode;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, preferredPort, shared: true);
    } catch (_) {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    port = _server!.port;
    role = LinkRole.host;
    status = 'Raum offen';
    _server!.listen(_onRequest, onError: (_) {});
    addresses = await localAddresses();
    await _acquireMulticast();
    try {
      _udpSend = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udpSend!.broadcastEnabled = true;
    } catch (_) {}
    _announce = Timer.periodic(const Duration(seconds: 1), (_) => _sendAnnouncement());
    _sendAnnouncement();
    notifyListeners();
  }

  Future<void> _onRequest(HttpRequest req) async {
    final ip = req.connectionInfo?.remoteAddress.address ?? '?';
    if (req.uri.path == '/darts/info' && code != null) {
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(_roomInfo()));
      await req.response.close();
      return;
    }
    if (req.uri.path != '/darts' || !WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final now = DateTime.now();
    final fails = (_fails[ip] ?? [])..removeWhere((t) => now.difference(t) > failWindow);
    if (fails.length >= maxFails) {
      ErrorLog.crumb('Kopplung: $ip gesperrt (zu viele falsche Codes)');
      req.response.statusCode = HttpStatus.tooManyRequests;
      await req.response.close();
      return;
    }
    final byKey = req.uri.queryParameters['auth'] == '1';
    final byCode = req.uri.queryParameters['code'] == code;
    if (!byKey && !byCode) {
      _fails[ip] = fails..add(now);
      req.response.statusCode = HttpStatus.forbidden;
      await req.response.close();
      return;
    }
    if (_peers.length >= maxPeers) {
      req.response.statusCode = HttpStatus.serviceUnavailable;
      await req.response.close();
      return;
    }
    _fails.remove(ip);
    final ws = await WebSocketTransformer.upgrade(req);
    ws.pingInterval = const Duration(seconds: 4);
    final peer = _Peer(ws, ip)..byCode = byCode;
    _peers.add(peer);
    ws.listen(
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

    // Bekanntes Gerät mit Schlüssel: gegenseitiger Nachweis, kein Code nötig.
    if (msg['auth'] == true) {
      final key = Store.guestKey(peer.device);
      final nonce = '${msg['nonce'] ?? ''}';
      if (key == null || nonce.length < 16) return _deny(peer, 'unknown');
      peer.key = key;
      peer.challenge = randomHex(16);
      _send(peer.ws, {
        't': 'auth',
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
    _send(peer.ws, {'t': 'welcome', 'key': key, 'hostDevice': Store.deviceId});
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
      case 'dart' || 'undo' || 'start':
        // Anzeige-Geräte dürfen nichts eintragen.
        if (!peer.viewer) onHostMessage?.call(msg);
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
    final s = _udpSend;
    if (s == null || code == null) return;
    final payload = utf8.encode(jsonEncode(_roomInfo()));
    final targets = <String>{'255.255.255.255'};
    for (final a in addresses) {
      final parts = a.split('.');
      if (parts.length == 4) targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
    }
    for (final t in targets) {
      try {
        s.send(payload, InternetAddress(t), discoveryPort);
      } catch (_) {}
    }
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
    _expectHost = hostDevice;
    _byKey = hostDevice != null &&
        (Store.knownHosts.where((h) => h.device == hostDevice).firstOrNull?.key?.isNotEmpty ?? false);
    _remembered = null;
    _lastTourIn = null;
    awaitingApproval = false;
    denied = false;
    joinedAsViewer = viewer;
    role = LinkRole.client;
    hostAddress = address;
    hostPort = port;
    code = roomCode;
    hostName = name;
    _wantConnected = true;
    status = 'Verbinde …';
    notifyListeners();
    final ok = await _connect();
    if (!ok) {
      _wantConnected = false;
      role = LinkRole.none;
      status = 'Verbindung fehlgeschlagen';
      notifyListeners();
    }
    return ok;
  }

  Future<bool> _connect() async {
    try {
      final q = _byKey ? 'auth=1' : 'code=${Uri.encodeQueryComponent(code ?? '')}';
      final ws = await WebSocket.connect('ws://$hostAddress:$hostPort/darts?$q').timeout(const Duration(seconds: 5));
      ws.pingInterval = const Duration(seconds: 4);
      _ws = ws;
      status = 'Verbunden';
      _nonce = randomHex(16);
      _send(ws, {
        't': 'hello',
        'device': Store.deviceId,
        'name': Store.deviceName,
        'viewer': joinedAsViewer,
        if (_byKey) 'auth': true,
        if (_byKey) 'nonce': _nonce,
      });
      if (_byKey) awaitingApproval = true;
      ws.listen(
        _clientReceive,
        onDone: _lostHost,
        onError: (_) => _lostHost(),
        cancelOnError: true,
      );
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _lostHost() {
    _ws = null;
    if (!_wantConnected) return;
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

  void _clientReceive(Object? data) {
    final msg = _decode(data);
    if (msg == null) return;
    switch (msg['t']) {
      case 'auth':
        // Host muss beweisen, dass er der bekannte ist – sonst sofort trennen.
        final key = Store.knownHosts.where((h) => h.device == _expectHost).firstOrNull?.key;
        final ok = key != null &&
            msg['hostDevice'] == _expectHost &&
            msg['proof'] == authProof(key, 'host', _nonce ?? '', _expectHost ?? '');
        if (!ok) {
          _wantConnected = false;
          awaitingApproval = false;
          denied = true;
          status = 'Das Gerät konnte sich nicht ausweisen – Verbindung abgebrochen';
          ErrorLog.crumb('Kopplung: Host-Nachweis falsch, getrennt');
          _ws?.close();
          notifyListeners();
          return;
        }
        sendToHost({'t': 'auth2', 'proof': authProof(key, 'guest', '${msg['nonce']}', Store.deviceId)});
      case 'welcome':
        final hd = '${msg['hostDevice'] ?? ''}';
        final key = msg['key'] as String?;
        if (hd.isNotEmpty && key != null && key.length >= 32) {
          _expectHost = hd;
          Store.rememberHost(KnownHost(
            device: hd,
            name: hostName ?? 'Gerät',
            address: hostAddress ?? '',
            port: hostPort ?? defaultPort,
            code: code ?? '',
            viewer: joinedAsViewer,
            key: key,
          ));
          // Wiederverbinden ab jetzt mit Schlüssel
          _byKey = true;
          _remembered = hd;
        }
      case 'pending':
        awaitingApproval = true;
        status = 'Warte auf Bestätigung am anderen Gerät …';
        notifyListeners();
      case 'denied':
        awaitingApproval = false;
        denied = true;
        _wantConnected = false;
        if (msg['reason'] == 'unknown' && _expectHost != null) {
          // Host kennt den Schlüssel nicht mehr → beim nächsten Mal mit Code neu koppeln.
          Store.setHostKey(_expectHost!, null);
          status = 'Dieses Gerät ist dort nicht mehr erlaubt – bitte mit Code neu koppeln';
        } else {
          status = 'Das andere Gerät hat die Verbindung abgelehnt';
        }
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
        hostName = msg['host'] as String? ?? hostName;
        final hd = msg['hostDevice'] as String?;
        // Nur ein ausgewiesener Host (Schlüssel) bzw. ein per Code erlaubter wird gemerkt.
        if (hd != null && hd != _remembered && (!_byKey || hd == _expectHost)) {
          _remembered = hd;
          Store.rememberHost(KnownHost(
            device: hd,
            name: hostName ?? 'Gerät',
            address: hostAddress ?? '',
            port: hostPort ?? defaultPort,
            code: code ?? '',
            viewer: joinedAsViewer,
          ));
        }
        notifyListeners();
        onState?.call(msg);
      case 'share':
        onShare?.call(Map<String, dynamic>.from(msg['pkg'] as Map), msg['from'] as String? ?? 'Anderes Gerät');
      case 'have' || 'syncpkg' || 'syncreq':
        onSync?.call(msg, sendToHost, hostName ?? 'Host');
    }
  }

  /// Gast: zwischen Mitspielen und reiner Anzeige wechseln.
  void setViewerMode(bool viewer) {
    joinedAsViewer = viewer;
    sendToHost({'t': 'mode', 'viewer': viewer});
    final hd = _remembered ?? _expectHost;
    final h = Store.knownHosts.where((x) => x.device == hd).firstOrNull;
    if (h != null) {
      Store.rememberHost(KnownHost(
          device: h.device, name: h.name, address: h.address, port: h.port, code: h.code, viewer: viewer, key: h.key));
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
    if (_udpListen != null) return;
    await _acquireMulticast();
    try {
      _udpListen = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort, reuseAddress: true);
      _udpListen!.broadcastEnabled = true;
      _udpListen!.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final dg = _udpListen?.receive();
        if (dg == null) return;
        try {
          final j = jsonDecode(utf8.decode(dg.data));
          if (j is! Map || j['app'] != 'darts_counter') return;
          if (!includeSelf && j['device'] == Store.deviceId) return;
          _addRoom(dg.address.address, Map<String, dynamic>.from(j), includeSelf: includeSelf);
        } catch (_) {}
      });
    } catch (_) {}
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

  /// Gleichzeitig abgefragte Adressen bei der Netzsuche (mehr überfordert die Nachbar-Tabelle von Android/Router).
  static const scanBatch = 512;

  /// Pause zwischen zwei kompletten Durchläufen.
  static const sweepPause = Duration(seconds: 30);

  /// Bekannte Geräte und gefundene Räume direkt fragen (auf ihrem eigenen Port).
  Future<void> _quickProbe() async {
    if (_quick || _scanTimer == null) return;
    _quick = true;
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 1500);
    try {
      final targets = <(String, int)>{
        for (final h in Store.knownHosts)
          if (h.address.isNotEmpty) (h.address, h.port),
        for (final r in rooms.value) (r.address, r.port),
      };
      await Future.wait([for (final (a, p) in targets) _probe(client, a, _includeSelf, port: p, patient: true)]);
    } finally {
      client.close(force: true);
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
    final out = <(String, int)>[];
    try {
      final r = await _channel.invokeMethod<List<Object?>>('networks');
      for (final e in r ?? const []) {
        final parts = '$e'.split('/');
        if (parts.length == 2 && !parts[0].contains(':')) out.add((parts[0], int.parse(parts[1])));
      }
    } catch (_) {}
    if (out.isEmpty) {
      try {
        final list = await NetworkInterface.list(type: InternetAddressType.IPv4);
        for (final i in list) {
          final n = i.name.toLowerCase();
          if (n.startsWith('rmnet') || n.startsWith('ccmni') || n.contains('dummy') || n.startsWith('tun')) continue;
          for (final a in i.addresses) {
            if (!a.isLoopback && !a.isLinkLocal) out.add((a.address, 24));
          }
        }
      } catch (_) {}
    }
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
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 800);
    try {
      final known = {for (final h in Store.knownHosts) h.address};
      final targets = (await scanTargets()).where((a) => !known.contains(a)).toList();
      scanProgress.value = (0, targets.length);
      for (var i = 0; i < targets.length && _scanTimer != null; i += scanBatch) {
        await Future.wait([
          for (final t in targets.skip(i).take(scanBatch)) _probe(client, t, includeSelf),
        ]);
        scanProgress.value = (min(i + scanBatch, targets.length), targets.length);
      }
    } finally {
      client.close(force: true);
      _scanning = false;
      // Nach einem kompletten Durchlauf erst nach einer Pause wieder (Akku, Router).
      if (_scanTimer != null) {
        _sweepAgain?.cancel();
        _sweepAgain = Timer(sweepPause, () => _scanNetwork(includeSelf: includeSelf));
      }
    }
  }

  Future<void> _probe(HttpClient client, String address, bool includeSelf,
      {int port = defaultPort, bool patient = false}) async {
    try {
      final req = await client
          .get(address, port, '/darts/info')
          .timeout(Duration(milliseconds: patient ? 1800 : 1100));
      final res = await req.close().timeout(const Duration(seconds: 2));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return;
      }
      final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 2));
      final j = jsonDecode(body);
      if (j is Map) _addRoom(address, Map<String, dynamic>.from(j), includeSelf: includeSelf);
    } catch (_) {}
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

  Future<void> stop() async {
    _wantConnected = false;
    _retry?.cancel();
    _announce?.cancel();
    _announce = null;
    _udpSend?.close();
    _udpSend = null;
    for (final p in List.of(_peers)) {
      await p.ws.close();
    }
    _peers.clear();
    await _server?.close(force: true);
    _server = null;
    await _ws?.close();
    _ws = null;
    role = LinkRole.none;
    status = '';
    remoteDevices = 0;
    if (_udpListen == null) await _releaseMulticast();
    notifyListeners();
  }

  static Future<List<String>> localAddresses() async {
    try {
      final list = await NetworkInterface.list(type: InternetAddressType.IPv4);
      return [
        for (final i in list)
          for (final a in i.addresses)
            if (!a.isLoopback) a.address,
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _acquireMulticast() async {
    try {
      await _channel.invokeMethod('acquire');
    } catch (_) {}
  }

  Future<void> _releaseMulticast() async {
    try {
      await _channel.invokeMethod('release');
    } catch (_) {}
  }

  static Map<String, dynamic>? _decode(Object? data) {
    if (data is String && data.length > maxMessage) return null;
    if (data is List<int> && data.length > maxMessage) return null;
    try {
      final j = jsonDecode(data is String ? data : utf8.decode(data as List<int>));
      return j is Map ? Map<String, dynamic>.from(j) : null;
    } catch (_) {
      return null;
    }
  }

  static void _send(WebSocket ws, Map<String, dynamic> msg) {
    try {
      ws.add(jsonEncode(msg));
    } catch (_) {}
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
}

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

  List<String> get peerNames => [for (final p in _approved) p.name];

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
    if (req.uri.queryParameters['code'] != code) {
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
    final peer = _Peer(ws, ip);
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

  Future<void> _onHello(_Peer peer, Map<String, dynamic> msg) async {
    if (peer.helloSeen) return;
    peer.helloSeen = true;
    final device = '${msg['device'] ?? ''}';
    final name = '${msg['name'] ?? 'Gerät'}';
    peer.device = device.length > 64 ? device.substring(0, 64) : device;
    peer.name = name.length > 40 ? name.substring(0, 40) : name;
    var ok = trustAll || Store.isTrustedGuest(peer.device);
    if (!ok) {
      _send(peer.ws, {'t': 'pending'});
      ErrorLog.crumb('Kopplung: ${peer.name} fragt nach Erlaubnis');
      ok = peer.device.isNotEmpty && (await onJoinRequest?.call(peer.device, peer.name) ?? false);
      if (!_peers.contains(peer)) return; // inzwischen getrennt
      if (ok) {
        Store.trustGuest(peer.device, peer.name);
      } else {
        _send(peer.ws, {'t': 'denied'});
        await peer.ws.close();
        return;
      }
    }
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
    // Nicht erlaubte Geräte dürfen nichts tun.
    if (!peer.approved) return;
    switch (msg['t']) {
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
    _lastTour = hostState?.call()['tournament'];
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

  Future<bool> join(String address, int port, String roomCode, {String? name, bool viewer = false}) async {
    await stop();
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
      final ws = await WebSocket.connect('ws://$hostAddress:$hostPort/darts?code=$code')
          .timeout(const Duration(seconds: 5));
      ws.pingInterval = const Duration(seconds: 4);
      _ws = ws;
      status = 'Verbunden';
      _send(ws, {'t': 'hello', 'device': Store.deviceId, 'name': Store.deviceName});
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
      case 'pending':
        awaitingApproval = true;
        status = 'Warte auf Bestätigung am anderen Gerät …';
        notifyListeners();
      case 'denied':
        awaitingApproval = false;
        denied = true;
        _wantConnected = false;
        status = 'Das andere Gerät hat die Verbindung abgelehnt';
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
        if (hd != null && hd != _remembered) {
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
    // Viele Router und manche Handys verwerfen Broadcasts. Darum zusätzlich
    // das eigene WLAN direkt nach einem Raum absuchen.
    _scanTimer = Timer.periodic(const Duration(seconds: 2), (_) => _scanNetwork(includeSelf: includeSelf));
    _scanNetwork(includeSelf: includeSelf);
  }

  Timer? _scanTimer;
  bool _scanning = false;

  /// Gleichzeitig abgefragte Adressen bei der Netzsuche.
  static const scanBatch = 1024;

  /// Fortschritt der Netzsuche (geprüft, gesamt).
  final scanProgress = ValueNotifier<(int, int)>((0, 0));

  void _addRoom(String address, Map<String, dynamic> j, {bool includeSelf = false}) {
    if (j['app'] != 'darts_counter') return;
    if (!includeSelf && j['device'] == Store.deviceId) return;
    final room = Room(
      address: address,
      port: (j['port'] as num).toInt(),
      code: j['code'] as String?,
      name: j['name'] as String? ?? 'Gerät',
      device: j['device'] as String? ?? '',
    );
    rooms.value = rooms.value.where((r) => r.device != room.device).toList()..add(room);
    if (room.device.isNotEmpty) {
      Store.updateHost(room.device, address: room.address, port: room.port);
    }
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
    if (_scanning || _udpListen == null && _scanTimer == null) return;
    _scanning = true;
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 350);
    try {
      // Zuerst bekannte Geräte und schon gefundene Räume (hält sie in der Liste)
      final known = {
        for (final h in Store.knownHosts)
          if (h.address.isNotEmpty) h.address,
        for (final r in rooms.value) r.address,
      }.toList();
      await Future.wait([for (final a in known) _probe(client, a, includeSelf)]);
      final targets = (await scanTargets()).where((a) => !known.contains(a)).toList();
      scanProgress.value = (0, targets.length);
      for (var i = 0; i < targets.length && _scanTimer != null; i += scanBatch) {
        await Future.wait([
          for (final t in targets.skip(i).take(scanBatch)) _probe(client, t, includeSelf),
        ]);
        scanProgress.value = (min(i + scanBatch, targets.length), targets.length);
        // gefundene Räume zwischendurch auffrischen, damit sie nicht wieder verschwinden
        if (i > 0 && i % (scanBatch * 2) == 0) {
          await Future.wait([for (final r in rooms.value) _probe(client, r.address, includeSelf)]);
        }
      }
    } finally {
      client.close(force: true);
      _scanning = false;
    }
  }

  Future<void> _probe(HttpClient client, String address, bool includeSelf) async {
    try {
      final req = await client.get(address, defaultPort, '/darts/info').timeout(const Duration(milliseconds: 500));
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'peer_socket.dart';

/// WLAN-Kopplung mit `dart:io` (nur Android/Desktop/Tests – im Web gibt es `lan_stub.dart`).
///
/// Hier liegt nur die Technik (Sockets, HTTP, UDP, Netz-Infos). Die Regeln
/// (Code, Sperrliste, Freigabe, Schlüssel) stehen weiter in `Link`.

/// WLAN-Kopplung ist auf dieser Plattform möglich.
const lanAvailable = true;

const _channel = MethodChannel('darts/net');

/// Entscheidet über eine eingehende Verbindung: 0 = annehmen, sonst HTTP-Status zum Ablehnen.
typedef LanGate = Future<int> Function(String ip, Map<String, String> query);

/// WebSocket aus `dart:io` als [PeerSocket].
class _IoPeerSocket implements PeerSocket {
  _IoPeerSocket(this._ws, this.remote) {
    _messages = _ws.map((d) => d is String ? d : utf8.decode(d as List<int>, allowMalformed: true));
    _ws.done.whenComplete(() {
      if (!_done.isCompleted) _done.complete();
    });
  }

  final WebSocket _ws;
  late final Stream<String> _messages;
  final _done = Completer<void>();

  @override
  final String remote;

  @override
  Stream<String> get messages => _messages;

  @override
  void send(String data) {
    try {
      _ws.add(data);
    } catch (_) {}
  }

  @override
  Future<void> close() async {
    try {
      await _ws.close();
    } catch (_) {}
  }

  @override
  Future<void> get done => _done.future;
}

/// Kleiner WebSocket-Server des Hosts im WLAN.
class LanServer {
  LanServer._(this._server);
  final HttpServer _server;
  RawDatagramSocket? _udp;

  int get port => _server.port;

  /// Öffnet den Server (bevorzugt auf [preferredPort], sonst ein freier Port).
  ///
  /// [info] liefert die Raum-Info für `/darts/info` (null = nicht anbieten),
  /// [gate] prüft Code/Sperre, [onPeer] bekommt jede angenommene Verbindung.
  static Future<LanServer> bind({
    required int preferredPort,
    required Map<String, dynamic>? Function() info,
    required LanGate gate,
    required void Function(PeerSocket socket, Map<String, String> query) onPeer,
  }) async {
    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.anyIPv4, preferredPort, shared: true);
    } catch (_) {
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    final s = LanServer._(server);
    server.listen((req) => s._onRequest(req, info, gate, onPeer), onError: (_) {});
    try {
      s._udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      s._udp!.broadcastEnabled = true;
    } catch (_) {}
    return s;
  }

  Future<void> _onRequest(HttpRequest req, Map<String, dynamic>? Function() info, LanGate gate,
      void Function(PeerSocket, Map<String, String>) onPeer) async {
    final ip = req.connectionInfo?.remoteAddress.address ?? '?';
    final i = req.uri.path == '/darts/info' ? info() : null;
    if (i != null) {
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(i));
      await req.response.close();
      return;
    }
    if (req.uri.path != '/darts' || !WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final status = await gate(ip, req.uri.queryParameters);
    if (status != 0) {
      req.response.statusCode = status;
      await req.response.close();
      return;
    }
    final ws = await WebSocketTransformer.upgrade(req);
    ws.pingInterval = const Duration(seconds: 4);
    onPeer(_IoPeerSocket(ws, ip), req.uri.queryParameters);
  }

  /// UDP-Ankündigung an alle [targets] (Broadcast-Adressen).
  void announce(List<int> payload, Iterable<String> targets, int port) {
    final s = _udp;
    if (s == null) return;
    for (final t in targets) {
      try {
        s.send(payload, InternetAddress(t), port);
      } catch (_) {}
    }
  }

  Future<void> close() async {
    _udp?.close();
    _udp = null;
    await _server.close(force: true);
  }
}

/// Gast: WebSocket zum Host im WLAN öffnen.
Future<PeerSocket> lanConnect(String address, int port, String query, Duration timeout) async {
  final ws = await WebSocket.connect('ws://$address:$port/darts?$query').timeout(timeout);
  ws.pingInterval = const Duration(seconds: 4);
  return _IoPeerSocket(ws, address);
}

/// Lauscht auf UDP-Ankündigungen anderer Hosts.
class LanListener {
  LanListener._(this._s);
  final RawDatagramSocket _s;

  static Future<LanListener?> bind(int port, void Function(String address, String payload) onMessage) async {
    try {
      final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true);
      s.broadcastEnabled = true;
      s.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final dg = s.receive();
        if (dg == null) return;
        try {
          onMessage(dg.address.address, utf8.decode(dg.data));
        } catch (_) {}
      });
      return LanListener._(s);
    } catch (_) {
      return null;
    }
  }

  void close() => _s.close();
}

/// Fragt Geräte direkt nach `/darts/info` (Netzsuche).
class LanProber {
  LanProber(Duration connectTimeout) : _client = HttpClient()..connectionTimeout = connectTimeout;
  final HttpClient _client;

  Future<Map<String, dynamic>?> info(String address, int port, {bool patient = false}) async {
    try {
      final req = await _client
          .get(address, port, '/darts/info')
          .timeout(Duration(milliseconds: patient ? 1800 : 1100));
      final res = await req.close().timeout(const Duration(seconds: 2));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 2));
      final j = jsonDecode(body);
      return j is Map ? Map<String, dynamic>.from(j) : null;
    } catch (_) {
      return null;
    }
  }

  void close() => _client.close(force: true);
}

/// Eigene Adressen mit Netzgröße (Präfix). Auf Android vom System, sonst /24.
/// Liefert alle IPv4-Adressen (Filter auf private Netze macht `Link`).
Future<List<(String, int)>> lanNetworks() async {
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
  return out;
}

Future<List<String>> lanLocalAddresses() async {
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

/// Android: Multicast-Sperre holen/freigeben (sonst kommen Broadcasts nicht an).
Future<void> lanMulticast(bool acquire) async {
  try {
    await _channel.invokeMethod(acquire ? 'acquire' : 'release');
  } catch (_) {}
}

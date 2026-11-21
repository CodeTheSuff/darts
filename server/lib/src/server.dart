import 'dart:async';
import 'dart:io';

import 'package:darts_protocol/darts_protocol.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'config.dart';
import 'http.dart';
import 'log.dart';
import 'relay.dart';
import 'version_source.dart';
import 'ws_upgrade.dart';

/// Der komplette Server: HTTP (Web-App, /health, /version.json, /apk) + WebSocket-Relais unter [relayPath].
class DartsServer {
  DartsServer._(this.config, this.log, this._http, this.hub, this._app);

  final ServerConfig config;
  final Log log;
  final HttpServer _http;
  final RelayHub hub;
  final HttpApp _app;
  final _started = DateTime.now();
  bool _stopping = false;

  /// Tatsächlicher Port (wichtig bei `port: 0` in Tests).
  int get port => _http.port;

  /// Startet den Server. [log] ersetzt das Standard-Logging (z. B. in Tests).
  static Future<DartsServer> start(ServerConfig config, {Log? log}) async {
    final l = log ?? Log(config.logLevel);
    final versions = VersionSource(config.versionFile, publicUrl: config.publicUrl);
    final hub = RelayHub(config, l, versions);
    late DartsServer server;
    final app = HttpApp(config, l, versions, () => server.healthInfo());
    final http = await HttpServer.bind(config.host, config.port, shared: false);
    http
      ..idleTimeout = const Duration(seconds: 30)
      ..autoCompress = false
      ..serverHeader = null;
    server = DartsServer._(config, l, http, hub, app);
    hub.start();
    http.listen(server._onRequest, onError: (Object e) => l.warn('HTTP-Fehler: ${e.runtimeType}'));
    return server;
  }

  Map<String, Object?> healthInfo() => {
        'ok': true,
        'version': serverVersion,
        'rooms': hub.roomCount,
        'connections': hub.connectionCount,
        'uptimeSeconds': DateTime.now().difference(_started).inSeconds,
      };

  Future<void> _onRequest(HttpRequest request) async {
    try {
      if (request.uri.path == relayPath && WebSocketTransformer.isUpgradeRequest(request)) {
        if (_stopping) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        final ip = clientKey(request);
        final up = await upgradeWebSocket(request, maxMessageBytes: config.maxFrameBytes);
        if (up != null) hub.accept(up, ip);
        return;
      }
      await shelf_io.handleRequest(request, _app.handler, poweredByHeader: null);
    } catch (e) {
      log.warn('Fehler bei Anfrage: ${e.runtimeType}');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  /// Schlüssel für Sperren je Client: IPv4-Adresse bzw. IPv6-/64-Präfix.
  /// Mit `TRUST_PROXY` aus dem letzten Eintrag von `X-Forwarded-For` (vom eigenen Proxy angehängt).
  String clientKey(HttpRequest request) {
    InternetAddress? addr = request.connectionInfo?.remoteAddress;
    if (config.trustProxy) {
      final xff = request.headers['x-forwarded-for'];
      if (xff != null) {
        final parts = xff.join(',').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        if (parts.isNotEmpty) addr = InternetAddress.tryParse(parts.last) ?? addr;
      }
    }
    if (addr == null) return '?';
    if (addr.type == InternetAddressType.IPv6) {
      final raw = addr.rawAddress;
      return [for (var i = 0; i < 8; i++) raw[i].toRadixString(16).padLeft(2, '0')].join();
    }
    return addr.address;
  }

  /// Sauber herunterfahren: keine neuen Verbindungen, alle WebSockets mit 1001 schließen.
  Future<void> stop() async {
    if (_stopping) return;
    _stopping = true;
    await hub.shutdown();
    await _http.close(force: true);
  }
}

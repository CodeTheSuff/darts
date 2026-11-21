import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:darts_protocol/darts_protocol.dart';
import 'package:darts_server/darts_server.dart';
import 'package:test/test.dart';

const wait = Duration(seconds: 3);

/// Test-Konfiguration: kurzer Takt, sonst Standardwerte (einzelne Werte überschreibbar).
ServerConfig testConfig({
  String? webDir,
  String? apkDir,
  String? versionFile,
  String publicUrl = '',
  Duration roomTtl = const Duration(hours: 24),
  int maxRooms = 500,
  int maxPeersPerRoom = 8,
  int minProtocol = relayProtocol,
  bool trustProxy = false,
  int maxFrameBytes = RelayLimits.maxFrameBytes,
  int messagesPerSecond = RelayLimits.messagesPerSecond,
  int burst = RelayLimits.burst,
  int maxBadJoins = RelayLimits.maxBadJoins,
  Duration blockFor = RelayLimits.blockFor,
  Duration helloTimeout = RelayLimits.helloTimeout,
  Duration idleTimeout = RelayLimits.idleTimeout,
}) =>
    ServerConfig(
      port: 0,
      host: '127.0.0.1',
      publicUrl: publicUrl,
      webDir: webDir ?? '${Directory.systemTemp.path}/darts_test_kein_web',
      apkDir: apkDir ?? '${Directory.systemTemp.path}/darts_test_kein_apk',
      versionFile: versionFile ?? '${Directory.systemTemp.path}/darts_test_keine_version.json',
      roomTtl: roomTtl,
      maxRooms: maxRooms,
      maxPeersPerRoom: maxPeersPerRoom,
      minProtocol: minProtocol,
      trustProxy: trustProxy,
      logLevel: LogLevel.off,
      maxFrameBytes: maxFrameBytes,
      messagesPerSecond: messagesPerSecond,
      burst: burst,
      maxBadJoins: maxBadJoins,
      blockFor: blockFor,
      helloTimeout: helloTimeout,
      idleTimeout: idleTimeout,
      tick: const Duration(milliseconds: 25),
    );

/// Startet einen Server und meldet ihn zum Aufräumen an. Log-Zeilen landen in [logLines].
Future<DartsServer> startServer(ServerConfig config, {List<String>? logLines}) async {
  final log = Log(LogLevel.debug, sink: (l) => logLines?.add(l));
  final s = await DartsServer.start(config, log: log);
  addTearDown(s.stop);
  return s;
}

/// Echter WebSocket-Client gegen den Test-Server.
class Client {
  Client._(this.ws) : _q = StreamQueue<Object?>(ws);

  final WebSocket ws;
  final StreamQueue<Object?> _q;

  static Future<Client> connect(DartsServer s, {Map<String, dynamic>? headers}) async {
    final ws = await WebSocket.connect('ws://127.0.0.1:${s.port}$relayPath', headers: headers);
    final c = Client._(ws);
    addTearDown(() => ws.close().catchError((_) {}));
    return c;
  }

  void send(RelayFrame f) => ws.add(f.encode());
  void sendRaw(Object data) => ws.add(data);

  /// Nächster Frame (Fehler, wenn stattdessen getrennt wird).
  Future<RelayFrame> next() async {
    final raw = await _q.next.timeout(wait);
    final f = RelayFrame.decode(raw);
    expect(f, isNotNull, reason: 'Server sendet gültige Frames');
    return f!;
  }

  /// Nächster Frame muss vom Typ [type] sein.
  Future<RelayFrame> expectFrame(String type) async {
    final f = await next();
    expect(f.type, type, reason: 'erwartet $type, bekam ${f.type} ${f.fields}');
    return f;
  }

  Future<RelayFrame> expectError(RelayError code) async {
    final f = await expectFrame('error');
    expect(f.str('code'), code.name);
    return f;
  }

  /// Wartet, bis der Server trennt; liefert den Close-Code.
  Future<int?> expectClosed() async {
    while (await _q.hasNext.timeout(wait)) {
      final raw = await _q.next;
      fail('Statt Trennung kam noch: $raw');
    }
    return ws.closeCode;
  }

  /// In [d] kommt nichts an.
  Future<void> expectSilence([Duration d = const Duration(milliseconds: 200)]) async {
    final has = await _q.hasNext.timeout(d, onTimeout: () => false);
    if (has) fail('Unerwartet: ${await _q.next}');
  }

  Future<void> close([int? code]) => ws.close(code);
}

/// Host öffnet einen Raum.
Future<({Client host, String room, String token})> openRoom(DartsServer s) async {
  final host = await Client.connect(s);
  host.send(RelayFrame.host(app: 'test'));
  final f = await host.expectFrame('hosted');
  return (host: host, room: f.str('room')!, token: f.str('token')!);
}

/// Gast tritt bei; liefert Client und Gast-ID.
Future<({Client guest, String peer})> joinRoom(DartsServer s, String room, {bool hostOnline = true}) async {
  final g = await Client.connect(s);
  g.send(RelayFrame.join(app: 'test', room: room));
  final f = await g.expectFrame('joined');
  expect(f.flag('hostOnline'), hostOnline);
  return (guest: g, peer: f.str('peer')!);
}

/// Wartet, bis [cond] stimmt (höchstens [wait]).
Future<void> eventually(bool Function() cond) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsed > wait) fail('Bedingung nicht erfüllt');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// HTTP-GET gegen den Server.
Future<({int status, Map<String, String> headers, List<int> body})> httpGet(DartsServer s, String path,
    {String method = 'GET'}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, Uri.parse('http://127.0.0.1:${s.port}$path'));
    final res = await req.close();
    final body = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    final headers = <String, String>{};
    res.headers.forEach((k, v) => headers[k.toLowerCase()] = v.join(','));
    return (status: res.statusCode, headers: headers, body: body);
  } finally {
    client.close(force: true);
  }
}

/// Rohe HTTP-Anfrage (ohne Normalisierung des Pfads) – für Pfad-Traversal-Tests.
Future<String> rawGet(DartsServer s, String rawPath) async {
  final sock = await Socket.connect('127.0.0.1', s.port);
  sock.write('GET $rawPath HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n');
  await sock.flush();
  final bytes = await sock.fold<List<int>>(<int>[], (a, b) => a..addAll(b)).timeout(wait);
  sock.destroy();
  return String.fromCharCodes(bytes);
}

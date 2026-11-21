/// Hilfen für den Ende-zu-Ende-Test des Vermittlungs-Servers:
/// - [ServerUnderTest] startet `server/bin/server.dart` mit eigenem Port und Test-Dateien
///   (oder nutzt einen schon laufenden Server über `DARTS_E2E_URL`).
/// - [RelayClient] ist ein reiner Protokoll-Client (WebSocket + [RelayFrame]), der eingehende
///   Frames puffert, damit der Test gezielt auf bestimmte Frames warten kann.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:darts_protocol/darts_protocol.dart';

export 'package:darts_protocol/darts_protocol.dart';

/// Inhalt der Test-`version.json`.
const testVersion = VersionInfo(
  version: '3.0.0',
  build: 19,
  minProtocol: 3,
  apkUrl: '/apk/Darts_3.0.0.apk',
  notes: ['E2E-Test'],
);

/// Bytes der Schein-APK.
final testApkBytes = utf8.encode('PK-schein-apk-fuer-den-e2e-test');

const testIndexHtml = '<!doctype html><title>Darts E2E</title><p>web-ok</p>';

/// Link-Nachricht (wie bei der WLAN-Kopplung) als JSON-String für das Feld `d`.
String link(Map<String, Object?> msg) => jsonEncode(msg);

Map<String, dynamic> unlink(RelayFrame f) => Map<String, dynamic>.from(jsonDecode(f.str('d')!) as Map);

/// Wo der Server-Code liegt (Standard: ../../server von tool/e2e aus).
Directory serverDirectory() {
  final override = Platform.environment['DARTS_SERVER_DIR'];
  if (override != null && override.isNotEmpty) return Directory(override).absolute;
  return Directory('${Directory.current.path}${Platform.pathSeparator}..${Platform.pathSeparator}..'
          '${Platform.pathSeparator}server')
      .absolute;
}

/// Grund zum Überspringen – oder null, wenn getestet werden kann.
String? skipReason() {
  final external = Platform.environment['DARTS_E2E_URL'];
  if (external != null && external.isNotEmpty) return null;
  final dir = serverDirectory();
  final entry = File('${dir.path}${Platform.pathSeparator}bin${Platform.pathSeparator}server.dart');
  if (!entry.existsSync()) {
    return 'Server-Code fehlt (${entry.path}) – E2E-Test übersprungen. '
        'Läuft in Phase 3 gegen den echten Server (oder DARTS_E2E_URL setzen).';
  }
  return null;
}

class ServerUnderTest {
  ServerUnderTest._(this.base, this._process, this._temp);

  /// z. B. http://127.0.0.1:53211
  final Uri base;
  final Process? _process;
  final Directory? _temp;
  final StringBuffer output = StringBuffer();

  /// Läuft der Server unter unserer Kontrolle (dann sind auch Logs und Test-Dateien bekannt)?
  bool get local => _process != null;

  Uri get wsUri => base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws', path: relayPath);

  static Future<ServerUnderTest> start() async {
    final external = Platform.environment['DARTS_E2E_URL'];
    if (external != null && external.isNotEmpty) {
      final s = ServerUnderTest._(Uri.parse(external.replaceAll(RegExp(r'/+$'), '')), null, null);
      await s._waitHealthy(const Duration(seconds: 15));
      return s;
    }

    final dir = serverDirectory();
    final dart = Platform.resolvedExecutable;

    // Abhängigkeiten des Servers holen (nur beim ersten Mal wirklich nötig).
    final pub = await Process.run(dart, ['pub', 'get'], workingDirectory: dir.path, runInShell: false);
    if (pub.exitCode != 0) {
      throw StateError('dart pub get in ${dir.path} fehlgeschlagen:\n${pub.stdout}\n${pub.stderr}');
    }

    // Test-Dateien: Web-App, APK, version.json
    final temp = await Directory.systemTemp.createTemp('darts_e2e_');
    final sep = Platform.pathSeparator;
    final web = Directory('${temp.path}${sep}web')..createSync();
    final apk = Directory('${temp.path}${sep}apk')..createSync();
    File('${web.path}${sep}index.html').writeAsStringSync(testIndexHtml);
    File('${apk.path}${sep}Darts_3.0.0.apk').writeAsBytesSync(testApkBytes);
    final versionFile = File('${temp.path}${sep}version.json')
      ..writeAsStringSync(jsonEncode(testVersion.toJson()));

    final port = await _freePort();
    final env = {
      'PORT': '$port',
      'HOST': '127.0.0.1',
      'PUBLIC_URL': 'http://127.0.0.1:$port',
      'WEB_DIR': web.path,
      'APK_DIR': apk.path,
      'VERSION_FILE': versionFile.path,
      'ROOM_TTL_HOURS': '24',
      'MAX_ROOMS': '50',
      'MAX_PEERS_PER_ROOM': '8',
      'MIN_PROTOCOL': '3',
      'TRUST_PROXY': 'false',
      // Absichtlich ausführlich: auch dann dürfen keine Namen/Inhalte in den Logs stehen.
      'LOG_LEVEL': 'debug',
    };
    // "dart bin/server.dart" statt "dart run …": läuft im selben Prozess, lässt sich daher
    // auch unter Windows sauber beenden (kein verwaister Kind-Prozess, der den Port hält).
    final process = await Process.start(dart, ['bin/server.dart'],
        workingDirectory: dir.path, environment: env, includeParentEnvironment: true);
    final s = ServerUnderTest._(Uri.parse('http://127.0.0.1:$port'), process, temp);
    process.stdout.transform(utf8.decoder).listen(s.output.write);
    process.stderr.transform(utf8.decoder).listen(s.output.write);
    var exited = false;
    unawaited(process.exitCode.then((_) => exited = true));
    try {
      await s._waitHealthy(const Duration(seconds: 90), exited: () => exited);
    } catch (_) {
      await s.stop();
      rethrow;
    }
    return s;
  }

  static Future<int> _freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<void> _waitHealthy(Duration max, {bool Function()? exited}) async {
    final end = DateTime.now().add(max);
    Object? last;
    while (DateTime.now().isBefore(end)) {
      if (exited != null && exited()) {
        throw StateError('Server hat sich beendet:\n$output');
      }
      try {
        final r = await get('/health');
        if (r.status == 200) return;
        last = 'HTTP ${r.status}';
      } catch (e) {
        last = e;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    throw TimeoutException('Server nicht gesund nach $max (zuletzt: $last)\n$output');
  }

  Future<({int status, List<int> body, String? contentType})> get(String path) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client.getUrl(base.replace(path: path));
      final res = await req.close().timeout(const Duration(seconds: 10));
      final body = <int>[];
      await for (final chunk in res) {
        body.addAll(chunk);
      }
      return (status: res.statusCode, body: body, contentType: res.headers.contentType?.mimeType);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> stop() async {
    final p = _process;
    if (p != null) {
      p.kill();
      await p.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
        p.kill(ProcessSignal.sigkill);
        return -1;
      });
    }
    try {
      await _temp?.delete(recursive: true);
    } catch (_) {}
  }
}

class _Waiter {
  _Waiter(this.match);
  final bool Function(RelayFrame) match;
  final completer = Completer<RelayFrame>();
}

/// Reiner Protokoll-Client.
class RelayClient {
  RelayClient._(this.label, this._ws) {
    _ws.listen(
      (data) {
        final f = RelayFrame.decode(data);
        if (f == null) {
          log.add('$label: unlesbarer Frame');
          return;
        }
        log.add('$label <- ${f.type} ${f.fields}');
        for (final w in _waiters) {
          if (!w.completer.isCompleted && w.match(f)) {
            _waiters.remove(w);
            w.completer.complete(f);
            return;
          }
        }
        inbox.add(f);
      },
      onDone: () {
        closeCode = _ws.closeCode;
        if (!_done.isCompleted) _done.complete();
      },
      onError: (Object e) {
        log.add('$label: Fehler $e');
        if (!_done.isCompleted) _done.complete();
      },
      cancelOnError: true,
    );
  }

  final String label;
  final WebSocket _ws;

  /// Noch nicht abgeholte Frames.
  final inbox = <RelayFrame>[];
  final _waiters = <_Waiter>[];
  final _done = Completer<void>();
  int? closeCode;

  /// Gemeinsames Protokoll aller Clients (für Fehlermeldungen).
  static final log = <String>[];

  bool get isClosed => _done.isCompleted;
  Future<void> get done => _done.future;

  static Future<RelayClient> connect(Uri ws, String label) async {
    final socket = await WebSocket.connect(ws.toString()).timeout(const Duration(seconds: 10));
    return RelayClient._(label, socket);
  }

  void send(RelayFrame f) {
    log.add('$label -> ${f.type} ${f.fields}');
    _ws.add(f.encode());
  }

  void sendRaw(String raw) => _ws.add(raw);

  /// Wartet auf den ersten Frame vom Typ [type] (optional mit Bedingung). Andere Frames bleiben im Puffer.
  Future<RelayFrame> expect(String type,
      {bool Function(RelayFrame f)? where, Duration timeout = const Duration(seconds: 5)}) {
    bool match(RelayFrame f) => f.type == type && (where == null || where(f));
    for (final f in inbox) {
      if (match(f)) {
        inbox.remove(f);
        return Future.value(f);
      }
    }
    final w = _Waiter(match);
    _waiters.add(w);
    return w.completer.future.timeout(timeout, onTimeout: () {
      _waiters.remove(w);
      throw TimeoutException(
          '$label: kein "$type" innerhalb $timeout. Puffer: ${inbox.map((f) => '${f.type} ${f.fields}').toList()}\n'
          'Verlauf (Ende):\n${log.skip(log.length > 40 ? log.length - 40 : 0).join('\n')}');
    });
  }

  /// Host: wartet auf eine Link-Nachricht [t] von Gast [peer] (Frame `from`).
  Future<Map<String, dynamic>> expectFrom(String peer, String t, {Duration timeout = const Duration(seconds: 5)}) async {
    final f = await expect('from', where: (f) => f.str('peer') == peer && _linkType(f) == t, timeout: timeout);
    return unlink(f);
  }

  /// Gast: wartet auf eine Link-Nachricht [t] vom Host (Frame `d`).
  Future<Map<String, dynamic>> expectLink(String t, {Duration timeout = const Duration(seconds: 5)}) async {
    final f = await expect('d', where: (f) => _linkType(f) == t, timeout: timeout);
    return unlink(f);
  }

  /// Prüft, dass innerhalb von [wait] KEIN passender Frame kommt.
  Future<bool> receivesNothing(bool Function(RelayFrame f) match, {Duration wait = const Duration(milliseconds: 500)}) async {
    await Future<void>.delayed(wait);
    return !inbox.any(match);
  }

  static String? _linkType(RelayFrame f) {
    try {
      final j = jsonDecode(f.str('d') ?? '');
      return j is Map ? j['t'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> close([int? code, String? reason]) async {
    await _ws.close(code, reason);
    await done.timeout(const Duration(seconds: 5), onTimeout: () {});
  }
}

import 'package:darts_protocol/darts_protocol.dart';

import 'log.dart';

/// Server-Version (für /health und Logs).
const serverVersion = '3.0.0';

/// Konfiguration des Servers.
///
/// Im Betrieb kommt sie aus Umgebungsvariablen ([ServerConfig.fromEnvironment]),
/// optional überschrieben durch Kommandozeilen-Argumente (`--port=8080`, `--web-dir=./web` …).
/// Die Zeit- und Grenzwerte ohne Umgebungsvariable sind nur für Tests einstellbar.
class ServerConfig {
  ServerConfig({
    this.port = 8080,
    this.host = '0.0.0.0',
    this.publicUrl = '',
    this.webDir = './web',
    this.apkDir = './apk',
    this.versionFile = './version.json',
    this.roomTtl = const Duration(hours: 24),
    this.maxRooms = 500,
    this.maxPeersPerRoom = RelayLimits.maxPeersPerRoom,
    this.minProtocol = relayProtocol,
    this.trustProxy = false,
    this.logLevel = LogLevel.info,
    // ---- ohne Umgebungsvariable (Tests)
    this.maxFrameBytes = RelayLimits.maxFrameBytes,
    this.messagesPerSecond = RelayLimits.messagesPerSecond,
    this.burst = RelayLimits.burst,
    this.maxBadJoins = RelayLimits.maxBadJoins,
    this.blockFor = RelayLimits.blockFor,
    this.helloTimeout = RelayLimits.helloTimeout,
    this.idleTimeout = RelayLimits.idleTimeout,
    this.tick = const Duration(seconds: 1),
  });

  final int port;
  final String host;

  /// Öffentliche Adresse (z. B. `https://darts.example.org`) – macht relative APK-Links absolut.
  final String publicUrl;
  final String webDir;
  final String apkDir;
  final String versionFile;
  final Duration roomTtl;
  final int maxRooms;
  final int maxPeersPerRoom;
  final int minProtocol;

  /// Hinter einem Reverse-Proxy: Client-IP aus `X-Forwarded-For` (letzter Eintrag).
  final bool trustProxy;
  final LogLevel logLevel;

  final int maxFrameBytes;
  final int messagesPerSecond;
  final int burst;
  final int maxBadJoins;
  final Duration blockFor;
  final Duration helloTimeout;
  final Duration idleTimeout;

  /// Takt für Timeouts, TTL-Aufräumen und Sperrlisten-Pflege.
  final Duration tick;

  /// Namen der Umgebungsvariablen (Agent D / deploy nutzt genau diese).
  static const envNames = [
    'PORT',
    'HOST',
    'PUBLIC_URL',
    'WEB_DIR',
    'APK_DIR',
    'VERSION_FILE',
    'ROOM_TTL_HOURS',
    'MAX_ROOMS',
    'MAX_PEERS_PER_ROOM',
    'MIN_PROTOCOL',
    'TRUST_PROXY',
    'LOG_LEVEL',
  ];

  /// Liest die Konfiguration aus [env]; [args] (`--port=9000`, `--web-dir=build/web`)
  /// überschreiben einzelne Werte. Ungültige Werte führen zu einer [FormatException].
  factory ServerConfig.fromEnvironment(Map<String, String> env, [List<String> args = const []]) {
    final values = <String, String>{
      for (final name in envNames)
        if (env[name] != null && env[name]!.trim().isNotEmpty) name: env[name]!.trim(),
    };
    for (final a in args) {
      final m = RegExp(r'^--([a-z][a-z0-9-]*)=(.*)$').firstMatch(a);
      final name = m?.group(1)?.toUpperCase().replaceAll('-', '_');
      if (m == null || !envNames.contains(name)) {
        throw FormatException('Unbekanntes Argument: $a');
      }
      values[name!] = m.group(2)!.trim();
    }

    int intOf(String name, int def, {int min = 0, int max = 1 << 31}) {
      final v = values[name];
      if (v == null) return def;
      final n = int.tryParse(v);
      if (n == null || n < min || n > max) throw FormatException('$name: ungültiger Wert "$v"');
      return n;
    }

    bool boolOf(String name) {
      final v = values[name]?.toLowerCase();
      if (v == null) return false;
      if (const ['1', 'true', 'yes', 'ja', 'on'].contains(v)) return true;
      if (const ['0', 'false', 'no', 'nein', 'off'].contains(v)) return false;
      throw FormatException('$name: ungültiger Wert "$v"');
    }

    Duration ttl = const Duration(hours: 24);
    final ttlRaw = values['ROOM_TTL_HOURS'];
    if (ttlRaw != null) {
      final h = double.tryParse(ttlRaw.replaceAll(',', '.'));
      if (h == null || h <= 0 || h > 24 * 365) {
        throw FormatException('ROOM_TTL_HOURS: ungültiger Wert "$ttlRaw"');
      }
      ttl = Duration(milliseconds: (h * 3600 * 1000).round());
    }

    final levelRaw = values['LOG_LEVEL']?.toLowerCase();
    final level = levelRaw == null
        ? LogLevel.info
        : LogLevel.values.firstWhere(
            (l) => l.name == levelRaw,
            orElse: () => throw FormatException('LOG_LEVEL: ungültiger Wert "$levelRaw"'),
          );

    final publicUrl = values['PUBLIC_URL'] ?? '';
    if (publicUrl.isNotEmpty) {
      final u = Uri.tryParse(publicUrl);
      if (u == null || !(u.isScheme('http') || u.isScheme('https')) || u.host.isEmpty) {
        throw FormatException('PUBLIC_URL: ungültige Adresse "$publicUrl"');
      }
    }

    return ServerConfig(
      port: intOf('PORT', 8080, max: 65535),
      host: values['HOST'] ?? '0.0.0.0',
      publicUrl: publicUrl,
      webDir: values['WEB_DIR'] ?? './web',
      apkDir: values['APK_DIR'] ?? './apk',
      versionFile: values['VERSION_FILE'] ?? './version.json',
      roomTtl: ttl,
      maxRooms: intOf('MAX_ROOMS', 500, min: 1, max: 1000000),
      maxPeersPerRoom: intOf('MAX_PEERS_PER_ROOM', RelayLimits.maxPeersPerRoom, min: 1, max: 1000),
      minProtocol: intOf('MIN_PROTOCOL', relayProtocol),
      trustProxy: boolOf('TRUST_PROXY'),
      logLevel: level,
    );
  }

  /// Kurzbeschreibung für das Start-Log (ohne Geheimnisse – es gibt keine).
  String describe() => 'host=$host port=$port publicUrl=${publicUrl.isEmpty ? '-' : publicUrl} '
      'webDir=$webDir apkDir=$apkDir versionFile=$versionFile '
      'ttl=${roomTtl.inMinutes}min maxRooms=$maxRooms maxPeers=$maxPeersPerRoom '
      'minProtocol=$minProtocol trustProxy=$trustProxy logLevel=${logLevel.name}';

  static const usage = '''
Darts-Server $serverVersion – Relais + Web-App + APK-Download

Konfiguration über Umgebungsvariablen (oder --name=wert, z. B. --port=9000, --web-dir=build/web):
  PORT                (8080)
  HOST                (0.0.0.0)
  PUBLIC_URL          (leer)  öffentliche Adresse, z. B. https://darts.example.org
  WEB_DIR             (./web) Flutter-Web-Build
  APK_DIR             (./apk)
  VERSION_FILE        (./version.json)
  ROOM_TTL_HOURS      (24)
  MAX_ROOMS           (500)
  MAX_PEERS_PER_ROOM  (8)
  MIN_PROTOCOL        (3)
  TRUST_PROXY         (false) Client-IP aus X-Forwarded-For (nur hinter Reverse-Proxy!)
  LOG_LEVEL           (info)  debug | info | warn | error | off
''';
}

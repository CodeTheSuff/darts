import 'dart:async';
import 'dart:io';

import 'package:darts_server/darts_server.dart';

/// Einstieg: `dart run bin/server.dart` bzw. kompiliert `./server`.
/// Konfiguration über Umgebungsvariablen (siehe README) oder `--name=wert`.
Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.write(ServerConfig.usage);
    return;
  }
  final ServerConfig config;
  try {
    config = ServerConfig.fromEnvironment(Platform.environment, args);
  } on FormatException catch (e) {
    stderr.writeln('Konfigurationsfehler: ${e.message}');
    stderr.write(ServerConfig.usage);
    exitCode = 64;
    return;
  }

  final log = Log(config.logLevel);
  final DartsServer server;
  try {
    server = await DartsServer.start(config, log: log);
  } on SocketException catch (e) {
    log.error('Port ${config.port} auf ${config.host} nicht verfügbar: ${e.osError?.message ?? e.message}');
    exitCode = 1;
    return;
  }
  log.info('Darts-Server $serverVersion läuft auf ${config.host}:${server.port} (${config.describe()})');
  if (!Directory(config.webDir).existsSync()) log.warn('WEB_DIR nicht gefunden – keine Web-App');
  if (!File(config.versionFile).existsSync()) log.warn('VERSION_FILE nicht gefunden – /version.json liefert 404');

  var stopping = false;
  Future<void> onSignal(ProcessSignal s) async {
    if (stopping) exit(1); // zweites Signal: sofort beenden
    stopping = true;
    log.info('${s.name} empfangen – fahre herunter');
    await server.stop().timeout(const Duration(seconds: 5), onTimeout: () {});
    log.info('Beendet');
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(onSignal);
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(onSignal);
}

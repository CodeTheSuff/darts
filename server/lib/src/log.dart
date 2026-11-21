import 'dart:io';

enum LogLevel { debug, info, warn, error, off }

/// Minimales Logging auf stdout/stderr.
///
/// Regel: **keine Inhalte und keine Namen** loggen – nur Ereignisse und Zähler.
/// Raum-Codes höchstens gekürzt ([Log.code]), keine IP-Adressen.
class Log {
  Log(this.level, {void Function(String line)? sink}) : _sink = sink;

  final LogLevel level;
  final void Function(String line)? _sink;

  bool enabled(LogLevel l) => l != LogLevel.off && l.index >= level.index;

  void debug(String msg) => _write(LogLevel.debug, msg);
  void info(String msg) => _write(LogLevel.info, msg);
  void warn(String msg) => _write(LogLevel.warn, msg);
  void error(String msg) => _write(LogLevel.error, msg);

  void _write(LogLevel l, String msg) {
    if (!enabled(l)) return;
    final line = '${DateTime.now().toUtc().toIso8601String()} ${l.name.toUpperCase().padRight(5)} $msg';
    final sink = _sink;
    if (sink != null) {
      sink(line);
    } else if (l.index >= LogLevel.warn.index) {
      stderr.writeln(line);
    } else {
      stdout.writeln(line);
    }
  }

  /// Raum-Code gekürzt für Logs: "K7M2QX" → "K7…".
  static String code(String? c) => c == null || c.length < 2 ? '…' : '${c.substring(0, 2)}…';
}

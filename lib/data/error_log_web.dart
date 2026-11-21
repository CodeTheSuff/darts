import 'package:web/web.dart' as web;

import '../platform/web_rules.dart';
import 'error_log.dart';

LogBackend createLogBackend() => WebLogBackend();

/// Browser: Protokoll in localStorage, damit es einen Neustart übersteht.
/// Begrenzt auf [maxChars] Zeichen (ältere Einträge fallen weg), weil localStorage
/// nur wenige MB fasst und die Spieldaten Vorrang haben. Kein Hänger-Wächter
/// (im Browser gibt es keine Isolates).
class WebLogBackend implements LogBackend {
  static const key = 'darts_errorlog';
  static const maxChars = 120000;

  @override
  Future<bool> open() async {
    try {
      web.window.localStorage.length;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  List<String> readLines() {
    try {
      final raw = web.window.localStorage.getItem(key);
      if (raw == null || raw.isEmpty) return const [];
      return raw.split('\n');
    } catch (_) {
      return const [];
    }
  }

  @override
  void writeLines(List<String> lines) {
    try {
      final keep = trimToLimit(lines, maxChars);
      if (keep.isEmpty) {
        web.window.localStorage.removeItem(key);
      } else {
        web.window.localStorage.setItem(key, keep.join('\n'));
      }
    } catch (_) {
      // Speicher voll oder gesperrt (privates Surfen): Protokoll bleibt nur im Speicher.
    }
  }

  @override
  String? takeKilledHang() => null;

  @override
  Future<void Function(List<Object?>)?> startWatchdog(
          int limitMs, int maxCrumbs, void Function(List<Object?>) onHang) async =>
      null;
}

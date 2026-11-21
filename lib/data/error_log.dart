import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'error_log_web.dart' if (dart.library.io) 'error_log_io.dart' as backend;

/// Ein Eintrag im Fehlerprotokoll.
class LogItem {
  LogItem({
    required this.t,
    required this.kind,
    required this.message,
    this.stack = '',
    this.crumbs = const [],
    this.situation = '',
    this.version = '',
  });

  /// Zeitpunkt (ms seit 1970).
  final int t;

  /// 'error', 'hang', 'hangKilled' oder 'stall'.
  final String kind;
  final String message;
  final String stack;
  final List<String> crumbs;
  final String situation;
  final String version;

  String get title => switch (kind) {
        'hang' => 'Hänger',
        'hangKilled' => 'Hänger – App wurde beendet',
        'stall' => 'Ruckler',
        _ => 'Fehler',
      };

  Map<String, dynamic> toJson() => {
        't': t,
        'kind': kind,
        'message': message,
        'stack': stack,
        'crumbs': crumbs,
        'situation': situation,
        'version': version,
      };

  factory LogItem.fromJson(Map<String, dynamic> j) => LogItem(
        t: (j['t'] as num).toInt(),
        kind: j['kind'] as String? ?? 'error',
        message: j['message'] as String? ?? '',
        stack: j['stack'] as String? ?? '',
        crumbs: [for (final c in (j['crumbs'] as List? ?? const [])) '$c'],
        situation: j['situation'] as String? ?? '',
        version: j['version'] as String? ?? '',
      );

  String toText() {
    final d = DateTime.fromMillisecondsSinceEpoch(t);
    final b = StringBuffer()
      ..writeln('=== $title · ${d.toIso8601String()} · Version $version')
      ..writeln(message);
    if (situation.isNotEmpty) b.writeln('Situation: $situation');
    if (crumbs.isNotEmpty) {
      b.writeln('Letzte Aktionen:');
      for (final c in crumbs) {
        b.writeln('  $c');
      }
    }
    if (stack.isNotEmpty) {
      b
        ..writeln('Stack:')
        ..writeln(stack);
    }
    return b.toString();
  }
}

/// Wo das Protokoll liegt: Android in Dateien (mit Hänger-Wächter im eigenen Isolate),
/// im Browser in localStorage (begrenzt, ohne Wächter). Siehe `error_log_io.dart` / `error_log_web.dart`.
abstract class LogBackend {
  /// Vorbereiten. Liefert `false`, wenn nichts gespeichert werden kann.
  Future<bool> open();

  /// Gespeicherte Einträge (je Zeile ein JSON-Objekt).
  List<String> readLines();

  /// Alle Einträge ersetzen (älteste zuerst).
  void writeLines(List<String> lines);

  /// Daten eines Hängers, bei dem die App beendet wurde (wird beim Lesen gelöscht).
  String? takeKilledHang();

  /// Startet den Hänger-Wächter. Liefert die Funktion, mit der die Oberfläche ihm
  /// Nachrichten schickt (`['beat']`, `['crumb', text]`, `['pause']`, `['resume']`, `['stop']`),
  /// oder `null`, wenn es keinen Wächter gibt (Browser).
  /// [onHang] bekommt `[seit, dauerMs, crumbs]`, sobald die Oberfläche wieder reagiert.
  Future<void Function(List<Object?>)?> startWatchdog(
      int limitMs, int maxCrumbs, void Function(List<Object?>) onHang);
}

/// Fehlerprotokoll: speichert Fehler, Ruckler und Hänger auf dem Gerät.
///
/// Hänger erkennt ein eigener Hintergrund-Isolate: Die Oberfläche meldet sich
/// alle 500 ms. Bleibt die Meldung länger als [hangAfter] aus, schreibt der
/// Wächter einen Eintrag – auch wenn die App danach gar nicht mehr reagiert.
/// Im Browser gibt es keinen Wächter; Fehler und Ruckler werden trotzdem erfasst.
class ErrorLog {
  ErrorLog._();

  static const maxEntries = 50;
  static const maxCrumbs = 40;
  static const hangAfter = Duration(seconds: 4);

  static String version = '';

  /// Liefert eine kurze Beschreibung der aktuellen Lage (Bildschirm, Kopplung, Spiel).
  static String Function()? situation;

  static final entries = ValueNotifier<List<LogItem>>([]);
  static final _crumbs = <String>[];

  /// Wird gesetzt, wenn die App beim letzten Mal eingefroren war und beendet wurde.
  static LogItem? pendingNotice;

  static LogBackend _store = backend.createLogBackend();
  static bool _stored = false;
  static void Function(List<Object?>)? _dog;
  static bool _ready = false;

  /// Speicherort ersetzen (Tests).
  @visibleForTesting
  static set backendForTest(LogBackend b) {
    _store = b;
    _stored = false;
    _ready = false;
  }

  static Future<void> init({required String appVersion}) async {
    if (_ready) return;
    _ready = true;
    version = appVersion;
    try {
      _stored = await _store.open();
      if (_stored) {
        _load();
        _checkKilledHang();
      }
    } catch (_) {
      _stored = false;
    }

    final prevFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      record('error', details.exceptionAsString(), details.stack);
      prevFlutter?.call(details);
    };
    final prevPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (e, s) {
      record('error', '$e', s);
      return prevPlatform?.call(e, s) ?? true;
    };
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    await _startWatchdog();
  }

  // ------------------------------------------------------------ Aktionen

  /// Merkt sich eine Aktion (für den Verlauf vor einem Fehler oder Hänger).
  static void crumb(String text) {
    final d = DateTime.now();
    final line = '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}.${(d.millisecond ~/ 100)} $text';
    _crumbs.add(line);
    if (_crumbs.length > maxCrumbs) _crumbs.removeAt(0);
    _dog?.call(['crumb', line]);
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _situation() {
    try {
      return situation?.call() ?? '';
    } catch (_) {
      return '';
    }
  }

  // ------------------------------------------------------------ Einträge

  static void record(String kind, String message, [StackTrace? stack, List<String>? crumbs, int? at]) {
    final item = LogItem(
      t: at ?? DateTime.now().millisecondsSinceEpoch,
      kind: kind,
      message: message.length > 2000 ? '${message.substring(0, 2000)} …' : message,
      stack: _shortStack(stack),
      crumbs: crumbs ?? List.of(_crumbs),
      situation: _situation(),
      version: version,
    );
    final list = [item, ...entries.value];
    entries.value = list.take(maxEntries).toList();
    _save();
  }

  static String _shortStack(StackTrace? s) {
    if (s == null) return '';
    final lines = s.toString().split('\n').where((l) => l.trim().isNotEmpty).take(25);
    return lines.join('\n');
  }

  static void clear() {
    entries.value = [];
    _save();
  }

  /// Alles als Text (zum Teilen).
  static String exportText() {
    final b = StringBuffer('Darts – Fehlerprotokoll (${entries.value.length} Einträge)\n\n');
    for (final e in entries.value) {
      b
        ..writeln(e.toText())
        ..writeln();
    }
    return b.toString();
  }

  /// Dateiname für den Export (`darts-fehlerprotokoll-JJJJ-MM-TT.txt`).
  static String exportFileName([DateTime? now]) {
    final d = now ?? DateTime.now();
    return 'darts-fehlerprotokoll-${d.year}-${_two(d.month)}-${_two(d.day)}.txt';
  }

  static void _load() {
    final out = <LogItem>[];
    for (final line in _store.readLines()) {
      if (line.trim().isEmpty) continue;
      try {
        out.add(LogItem.fromJson(Map<String, dynamic>.from(jsonDecode(line) as Map)));
      } catch (_) {}
    }
    out.sort((a, b) => b.t.compareTo(a.t));
    entries.value = out.take(maxEntries).toList();
  }

  static void _save() {
    if (!_stored) return;
    try {
      _store.writeLines([for (final e in entries.value.reversed) jsonEncode(e.toJson())]);
    } catch (_) {}
  }

  // ------------------------------------------------------------ Ruckler

  static void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final ms = t.totalSpan.inMilliseconds;
      if (ms >= 1500) {
        record('stall', 'Ein Bild hat $ms ms gebraucht '
            '(Aufbau ${t.buildDuration.inMilliseconds} ms, Zeichnen ${t.rasterDuration.inMilliseconds} ms)');
      }
    }
  }

  // ------------------------------------------------------------ Hänger

  /// App war eingefroren und wurde beendet, bevor sie wieder reagierte.
  static void _checkKilledHang() {
    final raw = _store.takeKilledHang();
    if (raw == null) return;
    try {
      final j = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final crumbs = [for (final c in (j['crumbs'] as List? ?? const [])) '$c'];
      record('hangKilled', 'Die App reagierte nicht mehr und wurde beendet.', null, crumbs,
          (j['since'] as num?)?.toInt());
      pendingNotice = entries.value.first;
    } catch (_) {}
  }

  static Future<void> _startWatchdog() async {
    if (!_stored) return;
    try {
      _dog = await _store.startWatchdog(hangAfter.inMilliseconds, maxCrumbs, (msg) {
        // Oberfläche reagiert wieder: Hänger protokollieren
        final crumbs = [for (final c in msg[2] as List) '$c'];
        record('hang', 'Die Oberfläche reagierte ${(msg[1] as int) ~/ 1000} s lang nicht.', null, crumbs,
            msg[0] as int);
      });
    } catch (_) {
      _dog = null;
    }
    final dog = _dog;
    if (dog == null) return;
    for (final c in _crumbs) {
      dog(['crumb', c]);
    }
  }

  /// App geht in den Hintergrund / kommt zurück (dann keine Hänger melden).
  static void setActive(bool active) => _dog?.call([active ? 'resume' : 'pause']);

  @visibleForTesting
  static void stopForTest() {
    _dog?.call(['stop']);
  }
}

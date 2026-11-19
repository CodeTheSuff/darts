import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';

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

/// Fehlerprotokoll: speichert Fehler, Ruckler und Hänger auf dem Gerät.
///
/// Hänger erkennt ein eigener Hintergrund-Isolate: Die Oberfläche meldet sich
/// alle 500 ms. Bleibt die Meldung länger als [hangAfter] aus, schreibt der
/// Wächter einen Eintrag – auch wenn die App danach gar nicht mehr reagiert.
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

  static File? _file;
  static File? _hangFile;
  static SendPort? _dog;
  static Timer? _beat;
  static bool _ready = false;

  static Future<void> init({required String appVersion}) async {
    if (_ready) return;
    _ready = true;
    version = appVersion;
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}/errors.jsonl');
      _hangFile = File('${dir.path}/hang.json');
      _load();
      _checkKilledHang();
    } catch (_) {}

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
    _dog?.send(['crumb', line]);
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

  static void _load() {
    final f = _file;
    if (f == null || !f.existsSync()) return;
    final out = <LogItem>[];
    for (final line in f.readAsLinesSync()) {
      try {
        out.add(LogItem.fromJson(Map<String, dynamic>.from(jsonDecode(line) as Map)));
      } catch (_) {}
    }
    out.sort((a, b) => b.t.compareTo(a.t));
    entries.value = out.take(maxEntries).toList();
  }

  static void _save() {
    final f = _file;
    if (f == null) return;
    try {
      f.writeAsStringSync(entries.value.reversed.map((e) => jsonEncode(e.toJson())).join('\n'));
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
    final f = _hangFile;
    if (f == null || !f.existsSync()) return;
    try {
      final j = Map<String, dynamic>.from(jsonDecode(f.readAsStringSync()) as Map);
      final crumbs = [for (final c in (j['crumbs'] as List? ?? const [])) '$c'];
      record('hangKilled', 'Die App reagierte nicht mehr und wurde beendet.', null, crumbs,
          (j['since'] as num?)?.toInt());
      pendingNotice = entries.value.first;
    } catch (_) {}
    try {
      f.deleteSync();
    } catch (_) {}
  }

  static Future<void> _startWatchdog() async {
    final hangPath = _hangFile?.path;
    if (hangPath == null) return;
    final back = ReceivePort();
    try {
      await Isolate.spawn(_watchdog, [back.sendPort, hangPath, hangAfter.inMilliseconds]);
    } catch (_) {
      return;
    }
    back.listen((msg) {
      if (msg is SendPort) {
        _dog = msg;
        for (final c in _crumbs) {
          msg.send(['crumb', c]);
        }
      } else if (msg is List && msg.first == 'hang') {
        // Oberfläche reagiert wieder: Hänger protokollieren
        final crumbs = [for (final c in msg[3] as List) '$c'];
        record('hang', 'Die Oberfläche reagierte ${(msg[2] as int) ~/ 1000} s lang nicht.', null, crumbs,
            msg[1] as int);
      }
    });
    _beat = Timer.periodic(const Duration(milliseconds: 500), (_) => _dog?.send(['beat']));
  }

  /// App geht in den Hintergrund / kommt zurück (dann keine Hänger melden).
  static void setActive(bool active) => _dog?.send([active ? 'resume' : 'pause']);

  @visibleForTesting
  static void stopForTest() {
    _beat?.cancel();
    _dog?.send(['stop']);
  }

  static void _watchdog(List<Object?> args) {
    final back = args[0] as SendPort;
    final path = args[1] as String;
    final limit = args[2] as int;
    final port = ReceivePort();
    back.send(port.sendPort);
    final crumbs = <String>[];
    var last = DateTime.now().millisecondsSinceEpoch;
    var paused = false;
    int? hangSince;
    final file = File(path);
    late final Timer timer;
    port.listen((msg) {
      if (msg is! List) return;
      switch (msg.first) {
        case 'beat':
          final now = DateTime.now().millisecondsSinceEpoch;
          if (hangSince != null) {
            back.send(['hang', hangSince, now - hangSince!, List.of(crumbs)]);
            hangSince = null;
            try {
              file.deleteSync();
            } catch (_) {}
          }
          last = now;
        case 'crumb':
          crumbs.add(msg[1] as String);
          if (crumbs.length > maxCrumbs) crumbs.removeAt(0);
        case 'pause':
          paused = true;
        case 'resume':
          paused = false;
          last = DateTime.now().millisecondsSinceEpoch;
        case 'stop':
          timer.cancel();
          port.close();
      }
    });
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (paused || hangSince != null || now - last < limit) return;
      hangSince = last;
      try {
        file.writeAsStringSync(jsonEncode({'since': last, 'crumbs': crumbs}));
      } catch (_) {}
    });
  }
}

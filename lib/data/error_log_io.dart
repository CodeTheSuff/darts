import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import 'error_log.dart';

LogBackend createLogBackend() => IoLogBackend();

/// Android: Protokoll als Datei (`errors.jsonl`) im App-Ordner, Hänger-Wächter im eigenen Isolate.
class IoLogBackend implements LogBackend {
  File? _file;
  File? _hangFile;
  Timer? _beat;

  @override
  Future<bool> open() async {
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/errors.jsonl');
    _hangFile = File('${dir.path}/hang.json');
    return true;
  }

  @override
  List<String> readLines() {
    final f = _file;
    if (f == null || !f.existsSync()) return const [];
    return f.readAsLinesSync();
  }

  @override
  void writeLines(List<String> lines) => _file?.writeAsStringSync(lines.join('\n'));

  @override
  String? takeKilledHang() {
    final f = _hangFile;
    if (f == null || !f.existsSync()) return null;
    String? raw;
    try {
      raw = f.readAsStringSync();
    } catch (_) {}
    try {
      f.deleteSync();
    } catch (_) {}
    return raw;
  }

  @override
  Future<void Function(List<Object?>)?> startWatchdog(
      int limitMs, int maxCrumbs, void Function(List<Object?>) onHang) async {
    final hangPath = _hangFile?.path;
    if (hangPath == null) return null;
    final back = ReceivePort();
    try {
      await Isolate.spawn(_watchdog, [back.sendPort, hangPath, limitMs, maxCrumbs]);
    } catch (_) {
      back.close();
      return null;
    }
    SendPort? dog;
    final pending = <List<Object?>>[];
    back.listen((msg) {
      if (msg is SendPort) {
        dog = msg;
        for (final m in pending) {
          msg.send(m);
        }
        pending.clear();
      } else if (msg is List && msg.first == 'hang') {
        onHang([msg[1], msg[2], msg[3]]);
      }
    });
    _beat = Timer.periodic(const Duration(milliseconds: 500), (_) => dog?.send(['beat']));
    return (m) {
      if (m.first == 'stop') _beat?.cancel();
      final d = dog;
      if (d != null) {
        d.send(m);
      } else if (m.first == 'crumb') {
        pending.add(m);
      }
    };
  }

  static void _watchdog(List<Object?> args) {
    final back = args[0] as SendPort;
    final path = args[1] as String;
    final limit = args[2] as int;
    final maxCrumbs = args[3] as int;
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

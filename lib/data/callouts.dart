import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../games/engine.dart';
import '../games/x01.dart';
import '../models/dart.dart';
import '../net/link.dart';
import 'error_log.dart';
import 'storage.dart';

/// Ansagen mit den eigenen Sounds (assets/callouts):
/// - „bullseye“ bei jedem Pfeil ins Bullseye (50)
/// - „1“, wenn alle drei Pfeile einer Aufnahme im Bereich der 1 landen
/// - „80“ … „180“ für die Punkte einer X01-Aufnahme (auch beim Checkout)
/// - „you_win“ am Ende eines Matches
///
/// Ist ein Tablet als Anzeige verbunden, spielt nur die Anzeige die Ansagen.
class Callouts {
  Callouts._();

  static const minScore = 80;
  static const maxScore = 180;

  /// Dieses Gerät ist gerade die Anzeige (Punktetafel).
  static bool isDisplay = false;

  /// Abspielen (in Tests ersetzbar). Erhält den Dateinamen ohne Endung.
  @visibleForTesting
  static Future<void> Function(String name) player = _play;

  static AudioPlayer? _p;
  static Future<void> _queue = Future.value();
  static int _errors = 0;

  /// Ansagen sind an und dieses Gerät ist das richtige zum Abspielen.
  static bool get active {
    if (!Store.announce || !Store.soundOn) return false;
    if (isDisplay) return true;
    // Eingabegerät: still, wenn irgendwo eine Anzeige verbunden ist
    return !Link.I.hasViewer;
  }

  /// Ersetzen die Ansagen die alten Jubel-Töne (Ton+, 140+, 180, Sieg)?
  static bool get replacesCheers => Store.announce;

  /// Welche Sounds zu diesem Wurf gehören (in Reihenfolge).
  static List<String> soundsFor(ThrowEvent ev, GameEngine e) {
    if (ev.control) return const [];
    final d = ev.turnEnded ? (ev.turnDarts.isEmpty ? null : ev.turnDarts.last) : (e.turn.isEmpty ? null : e.turn.last);
    if (d == null) return const [];
    final out = <String>[];
    if (d.field == 25 && d.mult == 2) out.add('bullseye');
    if (ev.turnEnded) {
      final darts = ev.turnDarts;
      // „1“ nur im X01-Match bzw. Turnierspiel, nicht in Trainings und Minispielen.
      if (e is X01Game && darts.length == 3 && darts.every((x) => x.field == 1)) {
        out.add('1');
      } else if (e is X01Game && !ev.bust) {
        final score = sumOf(darts);
        if (score >= minScore && score <= maxScore) out.add('$score');
      }
      if (ev.gameOver) out.add('you_win');
    }
    return out;
  }

  /// Nach jedem eingetragenen Pfeil aufrufen.
  static void onThrow(ThrowEvent ev, GameEngine e) {
    if (!active) return;
    for (final s in soundsFor(ev, e)) {
      _queue = _queue.then((_) => player(s)).catchError((Object err) => _failed(err));
    }
  }

  static Future<void> _play(String name) async {
    final p = _p ??= AudioPlayer();
    final done = p.onPlayerComplete.first;
    await p.play(AssetSource('callouts/$name.wav'), volume: Store.volume.clamp(0.0, 1.0));
    // Höchstdauer: eine Ansage darf die nächste nie blockieren.
    await done.timeout(const Duration(seconds: 6), onTimeout: () => p.stop());
  }

  static void _failed(Object e) {
    if (_errors++ < 3) ErrorLog.record('error', 'Ansage konnte nicht abgespielt werden: $e');
  }
}

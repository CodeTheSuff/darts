import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import 'storage.dart';

/// Kurze Soundeffekte (abschaltbar und mit Lautstärke in den Einstellungen).
class Sound {
  Sound._();

  static Future<void> play(String name, {double volume = 1}) async {
    if (!Store.soundOn) return;
    final v = (volume * Store.volume).clamp(0.0, 1.0);
    if (v <= 0) return;
    try {
      final p = AudioPlayer();
      await p.setReleaseMode(ReleaseMode.release);
      p.onPlayerComplete.listen((_) => p.dispose());
      await p.play(AssetSource('sounds/$name.wav'), volume: v);
    } catch (_) {
      // Sound ist nur Beiwerk – Fehler ignorieren.
    }
  }
}

/// Vibration (abschaltbar in den Einstellungen).
class Haptics {
  Haptics._();
  static void selection() {
    if (Store.vibration) HapticFeedback.selectionClick();
  }

  static void light() {
    if (Store.vibration) HapticFeedback.lightImpact();
  }

  static void medium() {
    if (Store.vibration) HapticFeedback.mediumImpact();
  }

  static void heavy() {
    if (Store.vibration) HapticFeedback.heavyImpact();
  }
}

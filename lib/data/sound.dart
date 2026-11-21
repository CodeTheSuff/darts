import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../platform/platform_env.dart';
import '../platform/web_audio.dart';
import 'error_log.dart';
import 'storage.dart';

/// Ein abspielbarer Ton (austauschbar für Tests).
abstract class SoundVoice {
  Future<void> load(String asset);
  Future<void> play(double volume);
  Future<void> dispose();
}

/// Echte Wiedergabe über Androids SoundPool (Low-Latency-Modus): einmal laden, beliebig oft abspielen.
class _PlayerVoice implements SoundVoice {
  final AudioPlayer _p = AudioPlayer();
  StreamSubscription<void>? _errors;

  @override
  Future<void> load(String asset) async {
    // Fehler der Wiedergabe kommen als Stream-Ereignis – abfangen, damit sie nicht als
    // unbehandelte Ausnahme durchschlagen.
    _errors = _p.eventStream.listen((_) {}, onError: (Object e) => Sound._failed(e));
    await _p.setPlayerMode(PlayerMode.lowLatency);
    await _p.setReleaseMode(ReleaseMode.stop);
    await _p.setSource(AssetSource(asset));
  }

  @override
  Future<void> play(double volume) async {
    await _p.stop();
    await _p.setVolume(volume);
    await _p.resume();
  }

  @override
  Future<void> dispose() async {
    await _errors?.cancel();
    await _p.dispose();
  }
}

/// Browser: Wiedergabe über die gemeinsame Web-Audio-Ausgabe (iOS-tauglich, siehe [WebAudio]).
class _WebVoice implements SoundVoice {
  String? _asset;

  @override
  Future<void> load(String asset) async {
    _asset = 'assets/$asset';
    await WebAudio.load(_asset!);
  }

  @override
  Future<void> play(double volume) async {
    final a = _asset;
    if (a != null) await WebAudio.play(a, volume);
  }

  @override
  Future<void> dispose() async {}
}

/// Kurze Soundeffekte (abschaltbar und mit Lautstärke in den Einstellungen).
///
/// Früher wurde für jeden Ton ein neuer Player angelegt und bei Fehlern nie freigegeben.
/// Android gingen dadurch die Player aus (MEDIA_ERROR_UNKNOWN, extra -19), und das Anlegen
/// blockierte jedes Mal kurz die Oberfläche. Jetzt: je Ton ein kleiner, fester Vorrat an
/// vorgeladenen Playern, die reihum wiederverwendet werden.
class Sound {
  Sound._();

  static const names = ['thunk', 'bust', 'ton', 'ton40', 'max180', 'finish', 'leg', 'win'];

  /// Wie viele Töne einer Sorte gleichzeitig klingen können.
  static int voicesFor(String name) => name == 'thunk' ? 4 : 2;

  /// Erzeugt einen Player (in Tests austauschbar).
  @visibleForTesting
  static SoundVoice Function() createVoice = WebAudio.supported ? _WebVoice.new : _PlayerVoice.new;

  static final Map<String, List<SoundVoice>> _pool = {};
  static final Map<String, int> _next = {};
  static Future<void>? _loading;
  static int _errors = 0;

  /// Anzahl angelegter Player (für Tests).
  @visibleForTesting
  static int get voiceCount => _pool.values.fold(0, (a, l) => a + l.length);

  /// Lädt alle Töne einmal vor (beim App-Start im Hintergrund).
  static Future<void> preload() => _loading ??= _load();

  static Future<void> _load() async {
    for (final n in names) {
      final list = <SoundVoice>[];
      for (var i = 0; i < voicesFor(n); i++) {
        try {
          final v = createVoice();
          await v.load('sounds/$n.wav');
          list.add(v);
        } catch (e) {
          _failed(e);
        }
      }
      _pool[n] = list;
    }
  }

  static void _failed(Object e) {
    // Nur die ersten Fehler protokollieren – Töne sind Beiwerk.
    if (_errors++ < 3) ErrorLog.record('error', 'Ton konnte nicht abgespielt werden: $e');
  }

  static Future<void> play(String name, {double volume = 1}) async {
    if (!Store.soundOn) return;
    final v = (volume * Store.volume).clamp(0.0, 1.0);
    if (v <= 0) return;
    try {
      await preload();
      final list = _pool[name];
      if (list == null || list.isEmpty) return;
      final i = _next[name] = ((_next[name] ?? -1) + 1) % list.length;
      await list[i].play(v);
    } catch (e) {
      _failed(e);
    }
  }

  @visibleForTesting
  static Future<void> resetForTest() async {
    for (final l in _pool.values) {
      for (final v in l) {
        await v.dispose();
      }
    }
    _pool.clear();
    _next.clear();
    _loading = null;
    _errors = 0;
  }
}

/// Vibration (abschaltbar in den Einstellungen). Im Browser ohne Vibration (iPhone) still ignoriert.
class Haptics {
  Haptics._();

  static bool get _on => Store.vibration && Plat.I.canVibrate;

  static void selection() {
    if (_on) HapticFeedback.selectionClick();
  }

  static void light() {
    if (_on) HapticFeedback.lightImpact();
  }

  static void medium() {
    if (_on) HapticFeedback.mediumImpact();
  }

  static void heavy() {
    if (_on) HapticFeedback.heavyImpact();
  }
}

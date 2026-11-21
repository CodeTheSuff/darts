import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

/// Web-Audio-Wiedergabe (siehe `web_audio.dart`).
class WebAudio {
  WebAudio._();

  static bool get supported => true;

  static web.AudioContext? _ctx;
  static final Map<String, Future<web.AudioBuffer?>> _buffers = {};

  /// Zuletzt benutzte Ansagen (nur so viele dekodiert im Speicher halten).
  static final List<String> _recent = [];
  static const _keepDecoded = 40;
  static bool _listening = false;

  /// Zustand der AudioContext ('running', 'suspended', 'interrupted' …) – für Tests/Protokoll.
  static String get state => _ctx?.state ?? 'none';

  static web.AudioContext? get _context {
    try {
      return _ctx ??= web.AudioContext();
    } catch (_) {
      return null;
    }
  }

  /// Schaltet den Ton beim ersten Tippen frei (iOS erlaubt Ton erst nach einer Nutzer-Geste)
  /// und weckt ihn nach einer Unterbrechung (Anruf, App im Hintergrund) wieder auf.
  static void installUnlock() {
    if (_listening) return;
    _listening = true;
    final opts = web.AddEventListenerOptions(capture: true, passive: true);
    final handler = ((web.Event _) => _unlock()).toJS;
    for (final type in const ['pointerdown', 'pointerup', 'touchend', 'mousedown', 'keydown', 'click']) {
      web.window.addEventListener(type, handler, opts);
    }
    web.document.addEventListener(
      'visibilitychange',
      ((web.Event _) {
        if (web.document.visibilityState == 'visible') _resume();
      }).toJS,
    );
  }

  static void _unlock() {
    final c = _context;
    if (c == null || c.state == 'running') return;
    _resume();
    try {
      // Ein stiller, winziger Ton innerhalb der Geste – ältere iOS-Versionen brauchen das.
      final b = c.createBuffer(1, 1, 22050);
      final s = c.createBufferSource()..buffer = b;
      s.connect(c.destination);
      s.start();
    } catch (_) {}
  }

  static void _resume() {
    final c = _ctx;
    if (c == null || c.state == 'running' || c.state == 'closed') return;
    try {
      c.resume().toDart.catchError((Object _) => null);
    } catch (_) {}
  }

  /// Lädt und dekodiert einen Ton (Asset-Schlüssel, z. B. `assets/sounds/thunk.wav`).
  static Future<void> load(String asset) async {
    await _buffer(asset);
  }

  static Future<web.AudioBuffer?> _buffer(String asset) {
    _recent
      ..remove(asset)
      ..add(asset);
    if (_recent.length > _keepDecoded) {
      final old = _recent.removeAt(0);
      // Effekte (assets/sounds) bleiben immer, nur Ansagen fliegen raus.
      if (!old.startsWith('assets/sounds/')) _buffers.remove(old);
    }
    return _buffers[asset] ??= _decode(asset).then((b) {
      if (b == null) _buffers.remove(asset);
      return b;
    });
  }

  static Future<web.AudioBuffer?> _decode(String asset) async {
    final c = _context;
    if (c == null) return null;
    final data = await rootBundle.load(asset);
    // Kopie: decodeAudioData übernimmt (und leert) den Puffer.
    final copy = Uint8List.fromList(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    return c.decodeAudioData(copy.buffer.toJS).toDart;
  }

  /// Spielt einen Ton. Mit [waitForEnd] endet das Future erst, wenn der Ton fertig ist
  /// (für die Ansagen-Warteschlange).
  static Future<void> play(String asset, double volume, {bool waitForEnd = false}) async {
    final buf = await _buffer(asset);
    final c = _ctx;
    if (buf == null || c == null) return;
    if (c.state != 'running') {
      // Noch nicht freigeschaltet: lieber still als später ein Schwall alter Töne.
      _resume();
      return;
    }
    final gain = c.createGain();
    gain.gain.value = volume.clamp(0.0, 1.0);
    gain.connect(c.destination);
    final src = c.createBufferSource()..buffer = buf;
    src.connect(gain);
    final done = Completer<void>();
    src.addEventListener(
      'ended',
      ((web.Event _) {
        try {
          gain.disconnect();
        } catch (_) {}
        if (!done.isCompleted) done.complete();
      }).toJS,
    );
    src.start();
    if (waitForEnd) {
      final ms = (buf.duration * 1000).ceil() + 300;
      await done.future.timeout(Duration(milliseconds: ms.clamp(300, 6000)), onTimeout: () {});
    }
  }
}

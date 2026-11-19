import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

import 'error_log.dart';
import 'storage.dart';

/// Eine Stimme der Android-Sprachausgabe.
class CallerVoice {
  const CallerVoice(this.name, this.locale, this.label, {this.male, this.online = false});
  final String name;
  final String locale;
  final String label;

  /// true = männlich, false = weiblich, null = unbekannt.
  final bool? male;
  final bool online;
}

/// Caller-Ansage wie im TV über die Sprachausgabe des Handys (offline).
/// Wählt automatisch eine tiefe Männerstimme und spricht langsam und betont.
class Caller {
  Caller._();

  static FlutterTts? _tts;
  static String? _key;
  static bool _maleFound = false;
  static Future<void> _queue = Future.value();

  /// Bekannte Männerstimmen der Google-Sprachausgabe.
  static const _googleMale = {'gbb', 'gbd', 'rjs', 'deb', 'deg', 'iom', 'iol', 'tpd', 'tpf'};
  static const _googleFemale = {'gba', 'gbc', 'gbg', 'dea', 'nfh', 'iob', 'iog', 'tpc', 'sfg'};

  /// Geschlecht aus dem Stimmennamen schätzen.
  static bool? guessMale(String name) {
    final n = name.toLowerCase();
    if (n.contains('female') || n.contains('woman')) return false;
    if (n.contains('male') || n.contains('#man')) return true;
    final m = RegExp(r'-x-([a-z]{3})').firstMatch(n);
    if (m != null) {
      if (_googleMale.contains(m.group(1))) return true;
      if (_googleFemale.contains(m.group(1))) return false;
    }
    // Samsung: SMTm.. = männlich, SMTf.. / SMTl.. = weiblich
    final s = RegExp(r'smt([a-z])\d').firstMatch(n);
    if (s != null) return s.group(1) == 'm';
    return null;
  }

  static String _locale(String lang) => lang == 'de' ? 'de-DE' : 'en-GB';

  static Future<void> _preferGoogle(FlutterTts t) async {
    try {
      final engines = (await t.getEngines as List?)?.map((e) => '$e').toList() ?? [];
      if (engines.contains('com.google.android.tts')) await t.setEngine('com.google.android.tts');
    } catch (_) {}
  }

  /// Alle Stimmen für [lang], Männerstimmen zuerst, Offline-Stimmen vor Online-Stimmen.
  static Future<List<CallerVoice>> voices(String lang) async {
    try {
      final t = _tts ??= FlutterTts();
      if (_key == null) await _preferGoogle(t);
      final want = _locale(lang).toLowerCase();
      final raw = (await t.getVoices as List?) ?? [];
      final list = <CallerVoice>[];
      for (final v in raw) {
        final m = Map<String, dynamic>.from(v as Map);
        final name = '${m['name']}';
        final loc = '${m['locale']}';
        if (loc.toLowerCase().replaceAll('_', '-') != want) continue;
        final online = '${m['network_required']}' == '1' || name.contains('network');
        list.add(CallerVoice(name, loc, '', male: guessMale(name), online: online));
      }
      int rank(CallerVoice v) => (v.male == true ? 0 : v.male == null ? 1 : 2) * 2 + (v.online ? 1 : 0);
      list.sort((a, b) => rank(a).compareTo(rank(b)) != 0 ? rank(a).compareTo(rank(b)) : a.name.compareTo(b.name));
      final count = <String, int>{};
      return [
        for (final v in list)
          () {
            final kind = v.male == true ? 'Männlich' : v.male == false ? 'Weiblich' : 'Stimme';
            final i = count[kind] = (count[kind] ?? 0) + 1;
            return CallerVoice(v.name, v.locale, '$kind $i${v.online ? ' (online)' : ''}',
                male: v.male, online: v.online);
          }(),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<FlutterTts?> _engine() async {
    try {
      final t = _tts ??= FlutterTts();
      final lang = Store.callerLang;
      final chosen = Store.callerVoice(lang);
      final key = '$lang|$chosen';
      if (_key != key) {
        if (_key == null) await _preferGoogle(t);
        await t.setLanguage(_locale(lang));
        final all = await voices(lang);
        CallerVoice? v;
        for (final x in all) {
          if (x.name == chosen) v = x;
        }
        // automatisch: erste Offline-Männerstimme
        v ??= all.where((x) => x.male == true && !x.online).firstOrNull ?? all.where((x) => x.male == true).firstOrNull;
        if (v != null) await t.setVoice({'name': v.name, 'locale': v.locale});
        _maleFound = v?.male == true;
        await t.awaitSpeakCompletion(true);
        _key = key;
      }
      await t.setVolume(Store.soundOn ? Store.volume.clamp(0.5, 1.0) : 0);
      return t;
    } catch (_) {
      return null; // keine Sprachausgabe verfügbar (z. B. in Tests)
    }
  }

  /// Tonhöhe: Männerstimme etwas tiefer, sonst deutlich tiefer gedreht.
  static double get _pitch => _maleFound ? 0.86 : 0.7;

  // ------------------------------------------------------------ Wiedergabe
  //
  // Android 16 schaltet die Wiedergabe des Sprachdienstes stumm, weil er als Hintergrund-App
  // gilt („AudioHardening … muted for com.google.android.tts“). Darum lässt die App den Text
  // nur in eine Datei sprechen und spielt diese selbst ab. Fertige Ansagen werden behalten.

  static AudioPlayer? _player;
  static Directory? _dir;
  static int _errors = 0;

  /// Höchstdauer je Schritt – danach geht es mit der nächsten Ansage weiter.
  static const stepTimeout = Duration(seconds: 6);

  /// Wartezeit, nach der eine nicht endende Ansage abgebrochen wird (in Tests kürzer).
  @visibleForTesting
  static Duration queueTimeout = const Duration(seconds: 20);

  static void _failed(String what, Object e) {
    if (_errors++ < 5) ErrorLog.record('error', 'Caller: $what – $e');
  }

  /// Stabiler Dateiname für eine Ansage (gleich auf allen Starts).
  static String _fileKey(String text) {
    var h = 0x811c9dc5;
    for (final c in '$_key|$_pitch|$text'.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16);
  }

  /// Spricht einen Teil in eine Datei (oder nimmt die vorhandene). Liefert null bei Fehler.
  static Future<File?> _render(FlutterTts t, String text, double pitch, double rate) async {
    try {
      _dir ??= Directory('${(await getApplicationSupportDirectory()).path}/caller');
      await _dir!.create(recursive: true);
      final f = File('${_dir!.path}/${_fileKey('$text|$pitch|$rate')}.wav');
      if (await f.exists() && await f.length() > 2000) return f;
      await t.awaitSynthCompletion(true);
      await t.setPitch(pitch);
      await t.setSpeechRate(rate);
      await t.synthesizeToFile(text, f.path, true).timeout(stepTimeout);
      if (await f.exists() && await f.length() > 2000) return f;
    } catch (e) {
      _failed('Sprachdatei', e);
    }
    return null;
  }

  static Future<void> _playFile(File f) async {
    final p = _player ??= AudioPlayer();
    final done = p.onPlayerComplete.first;
    await p.play(DeviceFileSource(f.path), volume: Store.volume.clamp(0.5, 1.0));
    await done.timeout(stepTimeout, onTimeout: () => p.stop());
  }

  /// Ein Teil der Ansage: als Datei abspielen, sonst notfalls direkt sprechen lassen.
  static Future<void> _part(FlutterTts t, String text, double pitchDelta, double rate) async {
    final pitch = (_pitch + pitchDelta).clamp(0.5, 2.0);
    final f = await _render(t, text, pitch, rate);
    if (f != null) {
      try {
        await _playFile(f);
        return;
      } catch (e) {
        _failed('Wiedergabe', e);
      }
    }
    try {
      await t.setPitch(pitch);
      await t.setSpeechRate(rate);
      await t.speak(text).timeout(stepTimeout, onTimeout: () => t.stop());
    } catch (e) {
      _failed('Sprachausgabe', e);
    }
  }

  /// Spricht nacheinander Teile mit eigener Tonhöhe/Geschwindigkeit (für betonte Ansagen).
  static void _sayParts(List<(String, double, double)> parts) {
    if (!Store.caller || !Store.soundOn) return;
    _queue = _queue.then((_) async {
      final t = await _engine();
      if (t == null) return; // keine Sprachausgabe (z. B. in Tests)
      Future<void> all() async {
        for (final (text, pitchDelta, rate) in parts) {
          await _part(t, text, pitchDelta, rate);
        }
      }

      // Eine hängende Ansage darf nie alle folgenden blockieren.
      await all().timeout(queueTimeout,
          onTimeout: () => _failed('Ansage hing', 'nach ${queueTimeout.inSeconds} s abgebrochen'));
    }).catchError((Object e) => _failed('Ansage', e));
  }

  /// Test: eine Ansage, die nie fertig wird, darf die Warteschlange nicht blockieren.
  @visibleForTesting
  static Future<void> enqueueForTest(Future<void> Function() job) {
    _queue = _queue.then((_) => job()).timeout(queueTimeout, onTimeout: () {}).catchError((Object _) {});
    return _queue;
  }

  static void _say(String text) => _sayParts([(text, 0, 0.42)]);

  /// Die 180 wie im Fernsehen: lang gezogen, zum Ende hin höher.
  static void _oneEighty() => _sayParts(_de
      ? [('Hundert', 0, 0.38), ('achtzig!', 0.14, 0.3)]
      : [('One hundred', 0, 0.38), ('and eighty!', 0.14, 0.3)]);

  static bool get _de => Store.callerLang == 'de';

  /// Punkte einer Aufnahme. [bust] = überworfen.
  static void visit(int score, {bool bust = false}) {
    if (bust || score == 0) {
      _say(_de ? 'Kein Score' : 'No score');
    } else if (score == 180) {
      _oneEighty();
    } else {
      _say('$score');
    }
  }

  /// Restpunkte, wenn ein Finish möglich ist.
  static void require(String name, int rest) => _say(_de ? '$name, noch $rest' : '$name, you require $rest');

  /// Probeansage beim Einschalten.
  static void test() => _oneEighty();

  /// Text für Tests und Anzeige.
  static String phraseFor(int score, {bool bust = false, String lang = 'en'}) {
    final de = lang == 'de';
    if (bust || score == 0) return de ? 'Kein Score' : 'No score';
    if (score == 180) return de ? 'Hundertachtzig!' : 'One hundred and eighty!';
    return '$score';
  }
}

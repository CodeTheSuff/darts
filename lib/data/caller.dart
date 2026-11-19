import 'package:flutter_tts/flutter_tts.dart';

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

  /// Spricht nacheinander Teile mit eigener Tonhöhe/Geschwindigkeit (für betonte Ansagen).
  static void _sayParts(List<(String, double, double)> parts) {
    if (!Store.caller || !Store.soundOn) return;
    _queue = _queue.then((_) async {
      final t = await _engine();
      if (t == null) return;
      try {
        for (final (text, pitchDelta, rate) in parts) {
          await t.setPitch((_pitch + pitchDelta).clamp(0.5, 2.0));
          await t.setSpeechRate(rate);
          await t.speak(text);
        }
      } catch (_) {}
    });
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

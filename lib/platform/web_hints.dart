import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/callouts.dart';
import '../data/storage.dart';
import 'platform_env.dart';
import 'web_audio.dart';
import 'web_rules.dart';

/// Merkt sich, wann zuletzt gesichert wurde und welche Web-Hinweise weggeklickt sind,
/// und erledigt die Web-Vorbereitungen beim Start.
class WebHints {
  WebHints._();

  static const _kLastBackup = 'web_lastBackup';
  static const _kFirstData = 'web_firstData';
  static const _kSnooze = 'web_backupSnooze';
  static const _kInstallHidden = 'web_installHintHidden';

  static SharedPreferences? _p;

  /// Ändert sich, wenn ein Hinweis weggeklickt oder ein Backup gemacht wurde.
  static final tick = ValueNotifier<int>(0);

  /// Speicher ist vor dem automatischen Löschen geschützt (`navigator.storage.persist()`).
  static bool? persisted;

  /// Beim App-Start nach `Store.init()` aufrufen.
  static Future<void> init() async {
    try {
      _p = await SharedPreferences.getInstance();
    } catch (_) {}
    final env = Plat.I;
    if (!env.isWeb) return;
    if (WebAudio.supported) {
      // Ton erst nach dem ersten Tippen (iOS), Ansagen über dieselbe Web-Audio-Ausgabe.
      WebAudio.installUnlock();
      // ignore: invalid_use_of_visible_for_testing_member
      Callouts.player = (name) =>
          WebAudio.play('assets/callouts/$name.wav', Store.volume.clamp(0.0, 1.0), waitForEnd: true);
    }
    unawaited(env.requestPersistentStorage().then((v) => persisted = v));
    noteData();
  }

  static DateTime? _get(String k) {
    final v = _p?.getInt(k);
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
  }

  static void _set(String k, DateTime? v) {
    final p = _p;
    if (p == null) return;
    if (v == null) {
      p.remove(k);
    } else {
      p.setInt(k, v.millisecondsSinceEpoch);
    }
    tick.value++;
  }

  static DateTime? get lastBackup => _get(_kLastBackup);

  /// Es gibt Spieldaten, die verloren gehen könnten.
  static bool get hasData {
    try {
      return Store.log.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Merkt sich, seit wann es Spieldaten gibt (Start der Backup-Erinnerung).
  static void noteData() {
    if (_get(_kFirstData) == null && hasData) _set(_kFirstData, DateTime.now());
  }

  static bool get showInstallHint {
    final env = Plat.I;
    return WebRules.showInstallHint(
      isWeb: env.isWeb,
      isIos: env.isIos,
      standalone: env.isStandalone,
      dismissedAt: _get(_kInstallHidden),
      now: DateTime.now(),
    );
  }

  static void hideInstallHint() => _set(_kInstallHidden, DateTime.now());

  static bool get backupDue {
    noteData();
    return WebRules.backupDue(
      isWeb: Plat.I.isWeb,
      hasData: hasData,
      lastBackup: lastBackup,
      firstData: _get(_kFirstData),
      snoozedAt: _get(_kSnooze),
      now: DateTime.now(),
    );
  }

  static void snoozeBackup() => _set(_kSnooze, DateTime.now());

  static String get lastBackupLabel => WebRules.lastBackupLabel(lastBackup, DateTime.now());

  /// Komplettes Backup als Datei speichern (Web: Download bzw. Teilen auf iPhone/iPad,
  /// Android: Teilen-Dialog). Liefert `false`, wenn abgebrochen.
  static Future<bool> exportBackup() async {
    final json = Store.exportBackup();
    final ok = await Plat.I.saveFile(
      Uint8List.fromList(utf8.encode(json)),
      name: WebRules.backupFileName(DateTime.now()),
      mime: 'application/json',
      subject: 'Darts – Backup',
    );
    if (ok) _set(_kLastBackup, DateTime.now());
    return ok;
  }
}

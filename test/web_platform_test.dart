import 'dart:ui';

import 'package:darts_counter/data/error_log.dart';
import 'package:darts_counter/data/sound.dart';
import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/platform/platform_env.dart';
import 'package:darts_counter/platform/web_hints.dart';
import 'package:darts_counter/platform/web_notices.dart';
import 'package:darts_counter/platform/web_rules.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Attrappe für die Plattform-Weiche (Browser/iPhone ohne echten Browser).
class FakeEnv implements PlatformEnv {
  FakeEnv({this.isWeb = true, this.isIos = true, this.isStandalone = false, this.canVibrate = false});

  @override
  final bool isWeb;
  @override
  final bool isIos;
  @override
  final bool isStandalone;
  @override
  final bool canVibrate;

  final saved = <(String, String, int)>[];
  bool cancel = false;
  int persistCalls = 0;

  @override
  Future<bool> requestPersistentStorage() async {
    persistCalls++;
    return true;
  }

  @override
  Future<bool> saveFile(Uint8List bytes, {required String name, required String mime, String? subject}) async {
    if (cancel) return false;
    saved.add((name, mime, bytes.length));
    return true;
  }

  @override
  bool get fullscreenSupported => false;
  @override
  bool get isFullscreen => false;
  @override
  Future<void> setFullscreen(bool on) async {}
  @override
  void reload() {}
}

/// Speicher-Attrappe für das Fehlerprotokoll.
class MemoryBackend implements LogBackend {
  MemoryBackend([List<String>? lines]) : lines = lines ?? [];
  List<String> lines;
  int writes = 0;

  @override
  Future<bool> open() async => true;
  @override
  List<String> readLines() => lines;
  @override
  void writeLines(List<String> l) {
    writes++;
    lines = List.of(l);
  }

  @override
  String? takeKilledHang() => null;
  @override
  Future<void Function(List<Object?>)?> startWatchdog(int a, int b, void Function(List<Object?>) c) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 21, 12);

  group('Regeln', () {
    test('Home-Bildschirm-Hinweis nur Safari iOS ohne Installation', () {
      bool show({bool web = true, bool ios = true, bool sa = false, DateTime? hidden}) => WebRules.showInstallHint(
          isWeb: web, isIos: ios, standalone: sa, dismissedAt: hidden, now: now);
      expect(show(), isTrue);
      expect(show(web: false), isFalse, reason: 'APK');
      expect(show(ios: false), isFalse, reason: 'Android-Chrome/Desktop');
      expect(show(sa: true), isFalse, reason: 'schon installiert');
      expect(show(hidden: now.subtract(const Duration(days: 3))), isFalse);
      expect(show(hidden: now.subtract(const Duration(days: 31))), isTrue, reason: 'kommt nach 30 Tagen wieder');
    });

    test('Backup-Erinnerung nach 14 Tagen, „Später“ pausiert 7 Tage', () {
      bool due({bool web = true, bool data = true, DateTime? last, DateTime? first, DateTime? snooze}) =>
          WebRules.backupDue(
              isWeb: web, hasData: data, lastBackup: last, firstData: first, snoozedAt: snooze, now: now);
      final d20 = now.subtract(const Duration(days: 20));
      final d5 = now.subtract(const Duration(days: 5));
      expect(due(first: d20), isTrue, reason: 'nie gesichert, Daten seit 20 Tagen');
      expect(due(first: d5), isFalse, reason: 'Daten erst seit 5 Tagen');
      expect(due(last: d5, first: d20), isFalse, reason: 'vor 5 Tagen gesichert');
      expect(due(last: d20, first: d20), isTrue);
      expect(due(last: d20, snooze: now.subtract(const Duration(days: 2))), isFalse);
      expect(due(last: d20, snooze: now.subtract(const Duration(days: 8))), isTrue);
      expect(due(data: false, first: d20), isFalse);
      expect(due(web: false, first: d20), isFalse);
    });

    test('Dateiname und „Zuletzt gesichert“', () {
      expect(WebRules.backupFileName(DateTime(2026, 3, 7)), 'darts_backup_2026-03-07.json');
      expect(WebRules.lastBackupLabel(null, now), 'Noch nie gesichert');
      expect(WebRules.lastBackupLabel(DateTime(2026, 11, 21, 1), now), 'Zuletzt gesichert: heute');
      expect(WebRules.lastBackupLabel(DateTime(2026, 11, 20, 23), now), 'Zuletzt gesichert: gestern');
      expect(WebRules.lastBackupLabel(DateTime(2026, 11, 1), now), 'Zuletzt gesichert: vor 20 Tagen');
      expect(ErrorLog.exportFileName(DateTime(2026, 1, 2)), 'darts-fehlerprotokoll-2026-01-02.txt');
    });

    test('Fehlerprotokoll im Browser: neueste Zeilen behalten, Grenze einhalten', () {
      final lines = [for (var i = 0; i < 10; i++) 'x' * 9]; // je 10 Zeichen mit Zeilenumbruch
      final keep = trimToLimit(lines, 35);
      expect(keep.length, 3);
      expect(trimToLimit(lines, 1000).length, 10);
      expect(trimToLimit(['a' * 50], 10), isEmpty);
    });
  });

  group('Fehlerprotokoll mit austauschbarem Speicher', () {
    test('lädt, schreibt und kommt ohne Hänger-Wächter aus (Browser)', () async {
      final prevFlutter = FlutterError.onError;
      final prevPlatform = PlatformDispatcher.instance.onError;
      final mem = MemoryBackend(['{"t":5,"kind":"error","message":"alt"}', 'kaputt']);
      ErrorLog.backendForTest = mem;
      ErrorLog.entries.value = [];
      await ErrorLog.init(appVersion: '3.0.0');
      FlutterError.onError = prevFlutter;
      PlatformDispatcher.instance.onError = prevPlatform;
      expect(ErrorLog.entries.value.single.message, 'alt');
      ErrorLog.crumb('Test');
      ErrorLog.setActive(false); // ohne Wächter: darf nichts tun
      ErrorLog.record('error', 'neu');
      expect(mem.writes, 1);
      expect(mem.lines.last, contains('neu'), reason: 'älteste zuerst');
      ErrorLog.clear();
      expect(mem.lines, isEmpty);
    });
  });

  group('Plattform-Weichen', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Store.init();
    });
    tearDown(() => Plat.I = FakeEnv(isWeb: false, isIos: false, isStandalone: true, canVibrate: true));

    test('Vibration im Browser ohne navigator.vibrate still ignorieren', () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
          (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls++;
        return null;
      });
      Store.vibration = true;
      Plat.I = FakeEnv(canVibrate: false);
      Haptics.light();
      Haptics.heavy();
      expect(calls, 0);
      Plat.I = FakeEnv(isWeb: false, canVibrate: true);
      Haptics.light();
      expect(calls, 1);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('Start im Browser fragt Speicher-Schutz an, Hinweis wegklickbar', () async {
      final env = FakeEnv();
      Plat.I = env;
      await WebHints.init();
      await Future<void>.delayed(Duration.zero);
      expect(env.persistCalls, 1);
      expect(WebHints.showInstallHint, isTrue);
      WebHints.hideInstallHint();
      expect(WebHints.showInstallHint, isFalse);
    });

    test('APK: kein Hinweis, kein Speicher-Schutz nötig', () async {
      final env = FakeEnv(isWeb: false, isIos: false, isStandalone: true);
      Plat.I = env;
      await WebHints.init();
      expect(env.persistCalls, 0);
      expect(WebHints.showInstallHint, isFalse);
      expect(WebHints.backupDue, isFalse);
    });

    test('Backup-Export speichert Datei und merkt sich „zuletzt gesichert“', () async {
      final env = FakeEnv();
      Plat.I = env;
      await WebHints.init();
      expect(WebHints.lastBackup, isNull);
      env.cancel = true;
      expect(await WebHints.exportBackup(), isFalse);
      expect(WebHints.lastBackup, isNull, reason: 'abgebrochen');
      env.cancel = false;
      expect(await WebHints.exportBackup(), isTrue);
      final (name, mime, size) = env.saved.single;
      expect(name, matches(RegExp(r'^darts_backup_\d{4}-\d\d-\d\d\.json$')));
      expect(mime, 'application/json');
      expect(size, greaterThan(10));
      expect(WebHints.lastBackup, isNotNull);
      expect(WebHints.lastBackupLabel, 'Zuletzt gesichert: heute');
    });

    testWidgets('Startseiten-Hinweis erscheint nur im Browser', (tester) async {
      Plat.I = FakeEnv();
      await WebHints.init();
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: WebNotices())));
      expect(find.text('Zum Home-Bildschirm hinzufügen'), findsOneWidget);
      await tester.tap(find.byTooltip('Ausblenden'));
      await tester.pump();
      expect(find.text('Zum Home-Bildschirm hinzufügen'), findsNothing);

      Plat.I = FakeEnv(isWeb: false);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: WebNotices(key: ValueKey('apk')))));
      expect(find.byType(Card), findsNothing);
      expect(find.textContaining('Backup'), findsNothing);
    });
  });
}

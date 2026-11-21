import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Prüft die PWA-Dateien in web/ (Home-Bildschirm, Offline-Start, Basis-Pfad).
void main() {
  String read(String p) => File(p).readAsStringSync();

  test('manifest.json: Name, Vollbild, dunkle Farben, Icons vorhanden', () {
    final m = jsonDecode(read('web/manifest.json')) as Map<String, dynamic>;
    expect(m['name'], 'Darts');
    expect(m['short_name'], 'Darts');
    expect(m['display'], 'standalone');
    expect(m['background_color'], '#1C1E25');
    expect(m['start_url'], './', reason: 'relativ, damit ein Unterpfad (--base-href) funktioniert');
    final icons = (m['icons'] as List).cast<Map>();
    expect(icons.where((i) => i['purpose'] == 'maskable'), isNotEmpty);
    for (final i in icons) {
      expect(File('web/${i['src']}').existsSync(), isTrue, reason: '${i['src']}');
    }
  });

  test('index.html: Basis-Pfad steuerbar, iOS-Tags, Safe-Area, kein weißer Blitz', () {
    final h = read('web/index.html');
    expect(h, contains(r'<base href="$FLUTTER_BASE_HREF">'));
    expect(h, contains('viewport-fit=cover'));
    expect(h, contains('apple-mobile-web-app-capable'));
    expect(h, contains('apple-mobile-web-app-status-bar-style'));
    expect(h, contains('icons/apple-touch-icon.png'));
    expect(h, contains('<title>Darts</title>'));
    expect(h, contains('background: #1C1E25'));
    expect(File('web/icons/apple-touch-icon.png').existsSync(), isTrue);
    expect(File('web/icons/splash.png').existsSync(), isTrue);
  });

  test('Start: lokales CanvasKit und eigener Service Worker', () {
    final b = read('web/flutter_bootstrap.js');
    expect(b, contains('{{flutter_js}}'));
    expect(b, contains('{{flutter_build_config}}'));
    expect(b, contains("canvasKitBaseUrl: 'canvaskit/'"));
    expect(b, contains("register('sw.js')"));
    expect(b, isNot(contains('serviceWorkerVersion')), reason: 'Flutters eigener Worker räumt nur auf');
    final sw = read('web/sw.js');
    expect(sw, contains("cache: 'no-cache'"), reason: 'Netz zuerst: Updates kommen an');
    for (final live in ['/ws', '/version.json', '/health', '/apk/']) {
      expect(sw, contains("'$live'"), reason: '$live nie aus dem Cache');
    }
  });
}

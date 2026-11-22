import 'dart:convert';
import 'dart:io';

import 'package:darts_protocol/darts_protocol.dart';
import 'package:darts_server/darts_server.dart';
import 'package:darts_server/src/app_page.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late Directory root;
  late DartsServer s;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('darts_http');
    final web = Directory('${root.path}/web')..createSync();
    File('${web.path}/index.html').writeAsStringSync('<html>APP</html>');
    File('${web.path}/flutter_bootstrap.js').writeAsStringSync('// boot');
    File('${web.path}/main.dart.wasm').writeAsBytesSync([0, 97, 115, 109]);
    Directory('${web.path}/assets').createSync();
    File('${web.path}/assets/style.css').writeAsStringSync('body{}');
    File('${web.path}/.geheim').writeAsStringSync('versteckt');
    File('${root.path}/secret.txt').writeAsStringSync('GEHEIM');
    final apk = Directory('${root.path}/apk')..createSync();
    File('${apk.path}/Darts_3.0.0.apk').writeAsBytesSync(List.filled(1000, 7));
    File('${root.path}/version.json').writeAsStringSync(
        jsonEncode(const VersionInfo(version: '3.0.0', build: 20, minProtocol: 3, apkUrl: '/apk/Darts_3.0.0.apk')
            .toJson()));
    s = await startServer(testConfig(
      webDir: web.path,
      apkDir: apk.path,
      versionFile: '${root.path}/version.json',
    ));
  });

  tearDown(() async {
    await s.stop();
    await root.delete(recursive: true);
  });

  test('/health', () async {
    final r = await openRoom(s);
    await joinRoom(s, r.room);
    final res = await httpGet(s, '/health');
    expect(res.status, 200);
    expect(res.headers['content-type'], startsWith('application/json'));
    final j = jsonDecode(utf8.decode(res.body)) as Map<String, dynamic>;
    expect(j['ok'], true);
    expect(j['version'], serverVersion);
    expect(j['rooms'], 1);
    expect(j['connections'], 2);
    expect(j['uptimeSeconds'], isA<int>());
  });

  test('/version.json mit no-cache, 404 wenn Datei fehlt', () async {
    final res = await httpGet(s, '/version.json');
    expect(res.status, 200);
    expect(res.headers['cache-control'], 'no-cache');
    expect(res.headers['access-control-allow-origin'], '*');
    final info = VersionInfo.fromJson(jsonDecode(utf8.decode(res.body)) as Map<String, dynamic>);
    expect(info.build, 20);
    File('${root.path}/version.json').deleteSync();
    expect((await httpGet(s, '/version.json')).status, 404);
  });

  test('/app: Download-Knopf, Verbinden-Link mit eigener Adresse, sicher ausgeliefert', () async {
    final res = await httpGet(s, '/app');
    expect(res.status, 200);
    expect(res.headers['content-type'], startsWith('text/html'));
    expect(res.headers['cache-control'], 'no-cache');
    expect(res.headers['content-security-policy'], contains("default-src 'none'"));
    final html = utf8.decode(res.body);
    final origin = 'http://127.0.0.1:${s.port}';
    expect(html, contains('href="$origin/apk/Darts_3.0.0.apk"'));
    expect(html, contains('Version 3.0.0'));
    final enc = Uri.encodeQueryComponent(origin);
    expect(html, contains('intent://connect?server=$enc#Intent;scheme=darts;package=de.simon.darts;'));
    expect(html, contains('darts://connect?server=$enc'));
    expect((await httpGet(s, '/app/')).status, 200);
    // ohne version.json: Seite geht trotzdem, nur ohne Download
    File('${root.path}/version.json').deleteSync();
    final res2 = await httpGet(s, '/app');
    expect(res2.status, 200);
    expect(utf8.decode(res2.body), contains('noch nicht auf diesem Server'));
  });

  test('/app: PUBLIC_URL hat Vorrang, gefälschter Host wird ohne TRUST_PROXY ignoriert', () async {
    expect(
        serverOrigin(Request('GET', Uri.parse('http://intern:8080/app'), headers: {'x-forwarded-host': 'boese.de'}),
            publicUrl: 'https://darts.beispiel.de/', trustProxy: false),
        'https://darts.beispiel.de');
    expect(
        serverOrigin(Request('GET', Uri.parse('http://intern:8080/app'), headers: {'x-forwarded-host': 'boese.de'}),
            publicUrl: '', trustProxy: false),
        'http://intern:8080');
    expect(
        serverOrigin(
            Request('GET', Uri.parse('http://darts:8080/app'),
                headers: {'x-forwarded-host': 'darts.beispiel.de', 'x-forwarded-proto': 'https'}),
            publicUrl: '',
            trustProxy: true),
        'https://darts.beispiel.de');
    expect(
        serverOrigin(Request('GET', Uri.parse('http://darts:8080/app'), headers: {'x-forwarded-host': 'a"><script>'}),
            publicUrl: '', trustProxy: true),
        'http://darts:8080');
    expect(appPageHtml(origin: 'https://x.de"><b>'), isNot(contains('"><b>')));
  });

  test('/apk: Download mit richtigem Typ, keine Pfad-Tricks', () async {
    final res = await httpGet(s, '/apk/Darts_3.0.0.apk');
    expect(res.status, 200);
    expect(res.headers['content-type'], 'application/vnd.android.package-archive');
    expect(res.headers['content-disposition'], contains('Darts_3.0.0.apk'));
    expect(res.body.length, 1000);
    expect((await httpGet(s, '/apk/Darts_9.apk')).status, 404);
    expect((await httpGet(s, '/apk/version.json')).status, 404);
    expect((await httpGet(s, '/apk/')).status, 404);
    expect(await rawGet(s, '/apk/..%2Fsecret.txt'), isNot(contains('GEHEIM')));
    expect(await rawGet(s, '/apk/..%5C..%5Csecret.txt'), isNot(contains('GEHEIM')));
  });

  test('Statische Web-App: index, Cache-Header, Sicherheits-Header', () async {
    final index = await httpGet(s, '/');
    expect(index.status, 200);
    expect(utf8.decode(index.body), '<html>APP</html>');
    expect(index.headers['content-type'], startsWith('text/html'));
    expect(index.headers['cache-control'], 'no-cache');
    expect(index.headers['x-content-type-options'], 'nosniff');
    expect(index.headers['referrer-policy'], isNotNull);
    expect(index.headers.containsKey('x-powered-by'), isFalse);

    final boot = await httpGet(s, '/flutter_bootstrap.js');
    expect(boot.headers['cache-control'], 'no-cache');
    expect(boot.headers['content-type'], startsWith('text/javascript'));

    final wasm = await httpGet(s, '/main.dart.wasm');
    expect(wasm.headers['content-type'], 'application/wasm');

    final css = await httpGet(s, '/assets/style.css');
    expect(css.status, 200);
    expect(css.headers['cache-control'], contains('max-age'));
    expect(css.headers['x-content-type-options'], 'nosniff');

    final head = await httpGet(s, '/', method: 'HEAD');
    expect(head.status, 200);
    expect(head.body, isEmpty);
    expect((await httpGet(s, '/', method: 'POST')).status, 405);
  });

  test('SPA-Fallback: Pfade ohne Endung → index.html, fehlende Dateien → 404', () async {
    final spa = await httpGet(s, '/spiel/123');
    expect(spa.status, 200);
    expect(utf8.decode(spa.body), '<html>APP</html>');
    expect(spa.headers['cache-control'], 'no-cache');
    expect((await httpGet(s, '/fehlt.png')).status, 404);
  });

  test('Kein Directory-Listing, keine versteckten Dateien, kein Pfad-Traversal', () async {
    expect((await httpGet(s, '/assets/')).status, isNot(200));
    expect((await httpGet(s, '/.geheim')).status, 404);
    for (final path in [
      '/../secret.txt',
      '/%2e%2e/secret.txt',
      '/assets/../../secret.txt',
      '/assets/%2e%2e/%2e%2e/secret.txt',
      '/..%2Fsecret.txt',
      '/..%5Csecret.txt',
      '/assets/..%5C..%5Csecret.txt',
    ]) {
      expect(await rawGet(s, path), isNot(contains('GEHEIM')), reason: path);
    }
  });

  test('/ws ohne Upgrade → 426', () async {
    expect((await httpGet(s, '/ws')).status, 426);
  });
}

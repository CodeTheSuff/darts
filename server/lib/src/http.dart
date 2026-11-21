import 'dart:convert';
import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';

import 'config.dart';
import 'log.dart';
import 'version_source.dart';

/// Dateien, die nie aus dem Cache kommen dürfen (sonst bleibt nach einem Update die alte Web-App).
/// `main.dart.*` hat bei Flutter keinen Hash im Namen – deshalb ebenfalls immer neu prüfen
/// (dank ETag kostet das nur ein 304).
const noCacheFiles = {
  'index.html',
  'flutter_service_worker.js',
  'flutter_bootstrap.js',
  'version.json',
  'manifest.json',
  'main.dart.js',
  'main.dart.mjs',
  'main.dart.wasm',
};

const _apkType = 'application/vnd.android.package-archive';
final _apkName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._\-]{0,150}\.apk$');

/// HTTP-Teil des Servers: /health, /version.json, /apk/…, statische Web-App (SPA).
class HttpApp {
  HttpApp(this.config, this.log, this.versions, this.health);

  final ServerConfig config;
  final Log log;
  final VersionSource versions;
  final Map<String, Object?> Function() health;

  Handler? _static;
  late final Handler handler = const Pipeline().addMiddleware(_securityHeaders).addHandler(_route);

  static final _mime = MimeTypeResolver()
    ..addExtension('wasm', 'application/wasm')
    ..addExtension('mjs', 'text/javascript')
    ..addExtension('js', 'text/javascript')
    ..addExtension('json', 'application/json')
    ..addExtension('webmanifest', 'application/manifest+json')
    ..addExtension('otf', 'font/otf')
    ..addExtension('ttf', 'font/ttf')
    ..addExtension('woff2', 'font/woff2');

  Handler _securityHeaders(Handler inner) => (request) async {
        final res = await inner(request);
        return res.change(headers: {
          'X-Content-Type-Options': 'nosniff',
          'Referrer-Policy': 'no-referrer',
          'X-Frame-Options': 'SAMEORIGIN',
        });
      };

  Future<Response> _route(Request request) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      return Response(HttpStatus.methodNotAllowed, body: 'Methode nicht erlaubt', headers: {'Allow': 'GET, HEAD'});
    }
    final segs = request.url.pathSegments;
    if (!_safeSegments(segs)) return _notFound();

    final path = request.url.path;
    if (path == 'health') return _health();
    if (path == 'version.json') return _version();
    if (path == 'ws') {
      return Response(HttpStatus.upgradeRequired, body: 'WebSocket erwartet', headers: {'Upgrade': 'websocket'});
    }
    if (segs.isNotEmpty && segs.first == 'apk') return _apk(request, segs);
    return _web(request, segs);
  }

  /// Keine Pfad-Tricks: kein `.`/`..`, keine Trenner oder Laufwerksangaben in Segmenten,
  /// keine versteckten Dateien.
  static bool _safeSegments(List<String> segs) {
    for (var i = 0; i < segs.length; i++) {
      final s = segs[i];
      if (s.isEmpty) {
        if (i == segs.length - 1) continue; // abschließender "/"
        return false;
      }
      if (s == '.' || s == '..' || s.startsWith('.')) return false;
      if (s.contains('/') || s.contains('\\') || s.contains(':') || s.contains('\u0000')) return false;
    }
    return true;
  }

  Response _notFound() => Response.notFound('Nicht gefunden', headers: {'Content-Type': 'text/plain; charset=utf-8'});

  /// Öffentliche, harmlose JSON-Antworten – auch von anderer Herkunft lesbar (z. B. `flutter run -d chrome`).
  static const _jsonHeaders = {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-cache',
    'Access-Control-Allow-Origin': '*',
  };

  Response _health() => Response.ok(jsonEncode(health()), headers: _jsonHeaders);

  Future<Response> _version() async {
    final raw = await versions.raw();
    if (raw == null) return _notFound();
    return Response.ok(raw, headers: _jsonHeaders);
  }

  Future<Response> _apk(Request request, List<String> segs) async {
    if (segs.length != 2 || !_apkName.hasMatch(segs[1])) return _notFound();
    final dir = Directory(config.apkDir);
    if (!dir.existsSync()) return _notFound();
    final root = dir.resolveSymbolicLinksSync();
    final file = File(p.join(root, segs[1]));
    if (!file.existsSync()) return _notFound();
    if (!p.isWithin(root, file.resolveSymbolicLinksSync())) return _notFound();
    final res = await createFileHandler(file.path, url: request.url.path, contentType: _apkType)(request);
    log.debug('APK-Download');
    return res.change(headers: {
      'Content-Disposition': 'attachment; filename="${segs[1]}"',
      'Cache-Control': 'no-cache',
    });
  }

  Handler? _staticHandler() {
    if (_static != null) return _static;
    if (!Directory(config.webDir).existsSync()) return null;
    return _static = createStaticHandler(
      config.webDir,
      defaultDocument: 'index.html',
      listDirectories: false,
      contentTypeResolver: _mime,
    );
  }

  Future<Response> _web(Request request, List<String> segs) async {
    final h = _staticHandler();
    if (h == null) return _notFound();
    var res = await h(request);
    var name = segs.isEmpty || segs.last.isEmpty ? 'index.html' : segs.last;
    if (res.statusCode == HttpStatus.notFound && !name.contains('.')) {
      // SPA: unbekannte Pfade ohne Dateiendung → index.html
      final index = Request(
        request.method,
        request.requestedUri.replace(path: '/index.html', query: ''),
        headers: request.headers,
      );
      res = await h(index);
      name = 'index.html';
    }
    if (res.statusCode == HttpStatus.notFound) return _notFound();
    if (res.statusCode == HttpStatus.ok || res.statusCode == HttpStatus.notModified ||
        res.statusCode == HttpStatus.partialContent) {
      final cache = noCacheFiles.contains(name) ? 'no-cache' : 'public, max-age=3600';
      res = res.change(headers: {'Cache-Control': cache});
    }
    return res;
  }
}

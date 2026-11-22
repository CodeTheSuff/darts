import 'package:darts_protocol/darts_protocol.dart';
import 'package:shelf/shelf.dart';

/// Android-Paketname der App (für den intent://-Link).
const androidPackage = 'de.simon.darts';

/// Öffentliche Adresse dieses Servers: PUBLIC_URL, sonst aus der Anfrage
/// (hinter einem vertrauenswürdigen Proxy aus X-Forwarded-Proto/-Host).
String serverOrigin(Request request, {required String publicUrl, required bool trustProxy}) {
  if (publicUrl.isNotEmpty) return publicUrl.replaceAll(RegExp(r'/+$'), '');
  final u = request.requestedUri;
  var scheme = u.scheme;
  var host = u.hasPort && !(u.port == 80 && scheme == 'http') && !(u.port == 443 && scheme == 'https')
      ? '${u.host}:${u.port}'
      : u.host;
  if (trustProxy) {
    final p = request.headers['x-forwarded-proto']?.split(',').first.trim();
    final h = request.headers['x-forwarded-host']?.split(',').first.trim();
    if (p == 'https' || p == 'http') scheme = p!;
    if (h != null && RegExp(r'^[A-Za-z0-9.\-]+(:\d{1,5})?$').hasMatch(h)) host = h;
  }
  return '$scheme://$host';
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

/// Seite `/app`: Android-App laden, App mit diesem Server verbinden, im Browser spielen.
String appPageHtml({required String origin, VersionInfo? info, String? apkUrl}) {
  final server = Uri.encodeQueryComponent(origin);
  final connect = 'darts://connect?server=$server';
  // intent:// öffnet die App zuverlässig aus Chrome; ist sie nicht installiert, geht es zur APK.
  final fallback = apkUrl ?? '$origin/app';
  final intent = 'intent://connect?server=$server#Intent;scheme=darts;package=$androidPackage;'
      'S.browser_fallback_url=${Uri.encodeComponent(fallback)};end';
  final version = info?.version;
  final apkButton = apkUrl == null
      ? '<p class="muted">Die Android-App liegt noch nicht auf diesem Server.</p>'
      : '<a class="btn" href="${_esc(apkUrl)}" download>Android-App herunterladen'
          '${version == null ? '' : ' <small>(Version ${_esc(version)})</small>'}</a>';
  return '''<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Darts – App</title>
<link rel="icon" href="/favicon.png">
<style>
  :root { color-scheme: dark; }
  body { margin: 0; background: #1C1E25; color: #E8EEF6; font: 16px/1.45 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
  main { max-width: 460px; margin: 0 auto; padding: 28px 16px 40px; }
  header { display: flex; align-items: center; gap: 14px; margin-bottom: 22px; }
  header img { width: 64px; height: 64px; border-radius: 15px; }
  h1 { font-size: 26px; margin: 0; }
  .muted { color: #9AA7B8; font-size: 14px; }
  section { background: #262A34; border-radius: 16px; padding: 18px 16px; margin-bottom: 14px; }
  h2 { font-size: 17px; margin: 0 0 6px; }
  .step { display: inline-block; width: 24px; height: 24px; border-radius: 12px; background: #7FD3F5; color: #10202A;
          text-align: center; font-weight: 800; font-size: 14px; line-height: 24px; margin-right: 6px; }
  .btn { display: block; text-align: center; background: #7FD3F5; color: #0E1A22; font-weight: 700; text-decoration: none;
         padding: 14px 12px; border-radius: 12px; margin-top: 10px; }
  .btn.alt { background: transparent; color: #7FD3F5; border: 2px solid #7FD3F5; }
  small { font-weight: 500; }
  code { background: #1C1E25; padding: 2px 6px; border-radius: 6px; word-break: break-all; }
  p { margin: 6px 0; }
</style>
</head>
<body>
<main>
  <header>
    <img src="/icons/Icon-192.png" alt="">
    <div><h1>Darts</h1><div class="muted">Server <code>${_esc(origin)}</code></div></div>
  </header>

  <section>
    <h2><span class="step">1</span>Android-App installieren</h2>
    <p class="muted">Nach dem Download die Datei öffnen und „Installieren“ tippen. Beim ersten Mal fragt Android,
      ob der Browser Apps installieren darf – das erlauben. Ein Update über die vorhandene App behält alle Daten.</p>
    $apkButton
  </section>

  <section>
    <h2><span class="step">2</span>App mit diesem Server verbinden</h2>
    <p class="muted">Öffnet die installierte Darts-App und trägt diesen Server ein – danach klappen Online-Spiele
      und Updates ohne weitere Einstellungen.</p>
    <a class="btn" href="${_esc(intent)}">App mit diesem Server verbinden</a>
    <p class="muted" style="margin-top:10px">Klappt der Knopf nicht? <a href="${_esc(connect)}" style="color:#7FD3F5">Alternativer Link</a>
      oder in der App unter Koppeln → Online → Erweitert die Adresse <code>${_esc(origin)}</code> eintragen.</p>
  </section>

  <section>
    <h2>iPhone, iPad &amp; Computer</h2>
    <p class="muted">Darts läuft direkt im Browser. Auf dem iPhone in Safari öffnen, dann Teilen → „Zum Home-Bildschirm“.</p>
    <a class="btn alt" href="/">Im Browser spielen</a>
  </section>
</main>
</body>
</html>
''';
}

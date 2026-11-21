import 'dart:convert';
import 'dart:io';

/// Einfacher GET-Abruf (Status, Text). Wirft bei Netzfehlern.
Future<(int, String)> httpGet(Uri uri, {Duration timeout = const Duration(seconds: 8)}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final req = await client.getUrl(uri).timeout(timeout);
    req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final res = await req.close().timeout(timeout);
    final body = await res.transform(utf8.decoder).join().timeout(timeout);
    return (res.statusCode, body);
  } finally {
    client.close(force: true);
  }
}

/// Nur im Web sinnvoll.
void reloadPage() {}

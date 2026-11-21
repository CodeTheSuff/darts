import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Einfacher GET-Abruf (Status, Text) per fetch. Wirft bei Netzfehlern.
Future<(int, String)> httpGet(Uri uri, {Duration timeout = const Duration(seconds: 8)}) async {
  final res = await web.window.fetch(uri.toString().toJS, web.RequestInit(cache: 'no-store')).toDart.timeout(timeout);
  final text = (await res.text().toDart).toDart;
  return (res.status, text);
}

/// Seite neu laden (neue Web-App-Version).
void reloadPage() => web.window.location.reload();

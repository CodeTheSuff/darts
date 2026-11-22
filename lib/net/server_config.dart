import 'package:darts_protocol/darts_protocol.dart';
import 'package:flutter/foundation.dart';

import '../data/storage.dart';
import 'web_bridge.dart';

/// Produktiv-Adresse des Vermittlungs-Servers.
///
/// Wird beim Bauen gesetzt: `--dart-define=DARTS_SERVER_URL=https://darts.example.de`
/// (macht `tool/build_release.ps1 -Domain …` automatisch). Ohne Angabe steht hier ein
/// Platzhalter – dann geht online nur mit selbst eingetragener Adresse (Einstellungen → Erweitert).
/// Im Browser spielt das keine Rolle: Die Web-App nimmt immer den Server, von dem sie geladen wurde.
const defaultServerUrl = String.fromEnvironment('DARTS_SERVER_URL', defaultValue: placeholderServerUrl);

/// Platzhalter, solange keine echte Adresse eingebaut ist.
const placeholderServerUrl = 'https://darts.example.invalid';

/// Wo der Vermittlungs-Server liegt und wie man ihn erreicht.
class ServerConfig {
  ServerConfig._();

  /// Aktuelle Server-Adresse (ohne „/“ am Ende):
  /// eigene Einstellung → im Web die eigene Herkunft → [defaultServerUrl].
  static String get url {
    final own = Store.serverUrl;
    if (own != null && own.trim().isNotEmpty) return normalize(own);
    if (kIsWeb) return Uri.base.origin;
    return defaultServerUrl;
  }

  /// Ist noch die Platzhalter-Adresse eingestellt?
  static bool get isPlaceholder => url == placeholderServerUrl;

  /// Eingabe vereinheitlichen: ohne Schema → http:// (lokal) bzw. https://, ohne „/“ am Ende.
  static String normalize(String input) {
    var t = input.trim();
    if (t.isEmpty) return t;
    if (!t.contains('://')) {
      final local = RegExp(r'^(localhost|127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)').hasMatch(t);
      t = '${local ? 'http' : 'https'}://$t';
    }
    while (t.endsWith('/')) {
      t = t.substring(0, t.length - 1);
    }
    return t;
  }

  /// WebSocket-Adresse des Relais: http → ws, https → wss, Pfad [relayPath].
  static Uri relayUri([String? base]) {
    final b = Uri.parse(normalize(base ?? url));
    final scheme = b.scheme == 'https' ? 'wss' : (b.scheme == 'http' ? 'ws' : b.scheme);
    final basePath = b.path.endsWith('/') ? b.path.substring(0, b.path.length - 1) : b.path;
    return b.replace(scheme: scheme, path: '$basePath$relayPath', query: null, fragment: null);
  }

  /// Pfad/URL relativ zur Server-Adresse auflösen (absolute URLs bleiben, wie sie sind).
  static Uri resolve(String pathOrUrl, [String? base]) {
    final b = Uri.parse('${normalize(base ?? url)}/');
    return b.resolve(pathOrUrl);
  }

  /// „Verbindung testen“: GET /health. Liefert null bei Erfolg, sonst eine Fehlermeldung.
  static Future<String?> test([String? base]) async {
    final b = normalize(base ?? url);
    if (b.isEmpty) return 'Keine Server-Adresse eingetragen.';
    final Uri u;
    try {
      u = resolve('health', b);
      if (!u.hasScheme || u.host.isEmpty) return 'Ungültige Adresse.';
    } catch (_) {
      return 'Ungültige Adresse.';
    }
    try {
      // /health darf Text oder JSON liefern – wichtig ist nur Status 200.
      final (status, _) = await httpGet(u, timeout: const Duration(seconds: 6));
      return status == 200 ? null : 'Server antwortet mit Fehler $status.';
    } catch (_) {
      return 'Server nicht erreichbar – Adresse und Internet prüfen.';
    }
  }
}

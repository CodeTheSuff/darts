import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';

import '../data/error_log.dart';
import '../data/storage.dart';
import 'server_config.dart';

/// Link „App mit diesem Server verbinden“ von der Seite `https://<server>/app`:
/// `darts://connect?server=https://darts.beispiel.de`
///
/// Damit braucht die APK keine fest eingebaute Adresse – derselbe Build passt zu jedem Server.
/// Übernommen wird die Adresse erst nach Rückfrage und erfolgreichem Verbindungstest.
class ServerLink {
  ServerLink._();

  static const _channel = MethodChannel('darts/link');

  /// Fragt, ob die Adresse übernommen werden soll (UI); null = keine UI verfügbar.
  static Future<bool> Function(String server)? confirm;

  /// Meldet das Ergebnis (UI): [error] null = übernommen.
  static void Function(String server, String? error)? done;

  static bool _init = false;

  /// Beim Start: Link aus dem Start-Intent holen und auf weitere Links lauschen (nur Android).
  static Future<void> init() async {
    if (kIsWeb || _init) return;
    _init = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'link') unawaited(handle(call.arguments as String?));
    });
    try {
      final first = await _channel.invokeMethod<String>('initial');
      if (first != null) unawaited(handle(first));
    } catch (_) {
      // Kanal fehlt (z. B. Tests) – nichts zu tun.
    }
  }

  /// Server-Adresse aus dem Link – oder null, wenn es kein gültiger Verbinden-Link ist.
  @visibleForTesting
  static String? parse(String? link) {
    if (link == null) return null;
    final Uri u;
    try {
      u = Uri.parse(link.trim());
    } catch (_) {
      return null;
    }
    if (u.scheme != 'darts' || u.host != 'connect') return null;
    final raw = u.queryParameters['server'];
    if (raw == null || raw.trim().isEmpty || raw.length > 200) return null;
    final s = ServerConfig.normalize(raw);
    final Uri su;
    try {
      su = Uri.parse(s);
    } catch (_) {
      return null;
    }
    if (su.host.isEmpty || su.hasQuery || su.hasFragment || su.userInfo.isNotEmpty) return null;
    // https immer; http nur für lokale Tests im eigenen Netz
    final local = RegExp(r'^(localhost|127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)').hasMatch(su.host);
    if (su.scheme != 'https' && !(su.scheme == 'http' && local)) return null;
    return s;
  }

  static Future<void> handle(String? link) async {
    final server = parse(link);
    if (server == null) {
      ErrorLog.crumb('Server-Link ignoriert (ungültig)');
      return;
    }
    if (ServerConfig.url == server && Store.serverUrl != null) {
      done?.call(server, null);
      return;
    }
    // Erst fragen (der Link könnte von irgendwo kommen) …
    final ok = await (confirm?.call(server) ?? Future.value(false));
    if (!ok) return;
    // … dann prüfen, ob dort wirklich ein Darts-Server antwortet.
    final err = await ServerConfig.test(server);
    if (err == null) {
      Store.serverUrl = server;
      ErrorLog.crumb('Server per Link übernommen');
    }
    done?.call(server, err);
  }
}

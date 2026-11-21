import 'dart:convert';

import 'package:darts_protocol/darts_protocol.dart';

import '../data/storage.dart';
import 'server_config.dart';
import 'web_bridge.dart';

/// Ein Update-Angebot für den Dialog.
class UpdateOffer {
  const UpdateOffer({required this.info, this.apk, required this.web, this.required = false});

  final VersionInfo info;

  /// Download der APK (schon mit der Server-Adresse aufgelöst), null = keine hinterlegt / Web.
  final Uri? apk;

  /// Web-App: statt Download einfach neu laden.
  final bool web;

  /// Server lehnt die alte Version ab (Relais-Fehler `update`).
  final bool required;
}

/// Prüft `<server>/version.json` auf eine neuere Version (höchstens 1× am Tag).
class UpdateCheck {
  UpdateCheck._();

  static const interval = Duration(days: 1);

  /// Ist wieder eine Prüfung fällig?
  static bool due([DateTime? now]) {
    final t = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final last = Store.lastUpdateCheck;
    return last <= 0 || t - last >= interval.inMilliseconds || t < last;
  }

  /// Angebot, falls [info] neuer ist als die installierte Version ([installedBuild] = versionCode).
  static UpdateOffer? evaluate(VersionInfo info,
      {required int installedBuild, required bool web, String? server, bool required = false}) {
    if (!required && !info.isNewerThan(installedBuild)) return null;
    final apk = info.apkUrl;
    return UpdateOffer(
      info: info,
      web: web,
      required: required,
      apk: web || apk == null || apk.isEmpty ? null : ServerConfig.resolve(apk, server),
    );
  }

  /// Angebot aus dem Relais-Fehler `update` ({version, apk} – evtl. unvollständig).
  static UpdateOffer fromRelay(Map<String, dynamic>? update, {required bool web, String? server}) {
    // Defensiv lesen: Felder können fehlen oder einen anderen Typ haben.
    final b = update?['build'], apk = update?['apk'], notes = update?['notes'];
    final info = VersionInfo(
      version: '${update?['version'] ?? 'neu'}',
      build: b is num ? b.toInt() : 0,
      minProtocol: 0,
      apkUrl: apk is String ? apk : null,
      notes: [if (notes is List) for (final n in notes) '$n'],
    );
    return evaluate(info, installedBuild: 0, web: web, server: server, required: true)!;
  }

  /// `version.json` holen (null bei Fehler).
  static Future<VersionInfo?> fetch([String? server]) async {
    try {
      final (status, body) = await httpGet(ServerConfig.resolve('version.json', server));
      if (status != 200) return null;
      final j = jsonDecode(body);
      return j is Map ? VersionInfo.fromJson(Map<String, dynamic>.from(j)) : null;
    } catch (_) {
      return null;
    }
  }

  /// Prüfen (ohne [force] höchstens 1× am Tag). Liefert ein Angebot oder null.
  static Future<UpdateOffer?> check(
      {required int installedBuild, required bool web, bool force = false, String? server, DateTime? now}) async {
    // Platzhalter-Adresse nicht abfragen (gibt es nicht).
    if (server == null && ServerConfig.isPlaceholder) return null;
    if (!force && !due(now)) return null;
    Store.lastUpdateCheck = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final info = await fetch(server);
    if (info == null) return null;
    return evaluate(info, installedBuild: installedBuild, web: web, server: server);
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:darts_protocol/darts_protocol.dart';

/// Liest `VERSION_FILE` (Inhalt von /version.json) bei Bedarf neu ein, sobald sich die Datei ändert.
class VersionSource {
  VersionSource(this.path, {this.publicUrl = ''});

  final String path;
  final String publicUrl;

  DateTime? _modified;
  String? _raw;
  VersionInfo? _info;

  /// Roher Dateiinhalt oder null, wenn die Datei fehlt.
  Future<String?> raw() async {
    await _refresh();
    return _raw;
  }

  /// Geparster Inhalt oder null (fehlt / kein gültiges JSON).
  Future<VersionInfo?> info() async {
    await _refresh();
    return _info;
  }

  /// Angaben für `error update`: `{version, apk}` (APK-Link absolut, falls PUBLIC_URL gesetzt).
  Future<Map<String, dynamic>?> updateInfo() async {
    final i = await info();
    if (i == null) return null;
    return {'version': i.version, 'apk': ?resolveApk(i.apkUrl)};
  }

  String? resolveApk(String? apk) {
    if (apk == null || apk.isEmpty || publicUrl.isEmpty) return apk;
    final u = Uri.tryParse(apk);
    if (u == null || u.hasScheme) return apk;
    final base = Uri.parse(publicUrl.endsWith('/') ? publicUrl : '$publicUrl/');
    return base.resolve(apk.startsWith('/') ? apk.substring(1) : apk).toString();
  }

  Future<void> _refresh() async {
    final f = File(path);
    FileStat stat;
    try {
      stat = await f.stat();
    } catch (_) {
      _clear();
      return;
    }
    if (stat.type != FileSystemEntityType.file) {
      _clear();
      return;
    }
    if (_raw != null && _modified == stat.modified) return;
    try {
      // Schutz: version.json ist klein – größere Dateien werden nicht ausgeliefert.
      if (stat.size > 256 * 1024) {
        _clear();
        return;
      }
      final text = await f.readAsString();
      _raw = text;
      _modified = stat.modified;
      try {
        final j = jsonDecode(text);
        _info = j is Map ? VersionInfo.fromJson(Map<String, dynamic>.from(j)) : null;
      } catch (_) {
        _info = null;
      }
    } catch (_) {
      _clear();
    }
  }

  void _clear() {
    _raw = null;
    _info = null;
    _modified = null;
  }
}

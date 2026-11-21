/// Inhalt von `/version.json` auf dem Server: aktuelle App-Version und APK-Download.
class VersionInfo {
  const VersionInfo({
    required this.version,
    required this.build,
    required this.minProtocol,
    this.apkUrl,
    this.notes = const [],
  });

  /// z. B. "3.0.0"
  final String version;

  /// Android versionCode (z. B. 19) – zum Vergleichen.
  final int build;

  /// Älteste Protokollversion, die der Server noch annimmt.
  final int minProtocol;

  /// Download der aktuellen APK (relativ zur Server-Adresse oder absolut), null = keine APK hinterlegt.
  final String? apkUrl;

  /// Kurze Änderungsliste für den Update-Dialog.
  final List<String> notes;

  Map<String, dynamic> toJson() => {
        'version': version,
        'build': build,
        'minProtocol': minProtocol,
        if (apkUrl != null) 'apk': apkUrl,
        'notes': notes,
      };

  factory VersionInfo.fromJson(Map<String, dynamic> j) => VersionInfo(
        version: '${j['version'] ?? '0.0.0'}',
        build: (j['build'] as num?)?.toInt() ?? 0,
        minProtocol: (j['minProtocol'] as num?)?.toInt() ?? 0,
        apkUrl: j['apk'] as String?,
        notes: [for (final n in (j['notes'] as List?) ?? const []) '$n'],
      );

  /// Ist diese Version neuer als [build] (versionCode der installierten App)?
  bool isNewerThan(int installedBuild) => build > installedBuild;
}

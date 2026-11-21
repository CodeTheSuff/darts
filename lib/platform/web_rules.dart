/// Reine Regeln für die Web-Hinweise (ohne Browser-Zugriff, daher in Tests prüfbar).
class WebRules {
  WebRules._();

  /// Erinnerung an ein Backup, wenn das letzte so lange her ist.
  static const backupEvery = Duration(days: 14);

  /// „Später“ bei der Backup-Erinnerung: so lange Ruhe.
  static const backupSnooze = Duration(days: 7);

  /// Weggeklickter Home-Bildschirm-Hinweis kommt nach dieser Zeit wieder.
  static const installHintPause = Duration(days: 30);

  /// Hinweis „Zum Home-Bildschirm hinzufügen“: nur Safari auf iPhone/iPad im Browser
  /// (nicht schon installiert), und nicht kurz nach dem Wegklicken.
  static bool showInstallHint({
    required bool isWeb,
    required bool isIos,
    required bool standalone,
    DateTime? dismissedAt,
    required DateTime now,
  }) {
    if (!isWeb || !isIos || standalone) return false;
    if (dismissedAt != null && now.difference(dismissedAt) < installHintPause) return false;
    return true;
  }

  /// Backup-Erinnerung (nur Web): Es gibt Spieldaten und das letzte Backup – bzw. ohne Backup
  /// die ersten Spieldaten – ist mindestens [backupEvery] her. „Später“ pausiert [backupSnooze].
  static bool backupDue({
    required bool isWeb,
    required bool hasData,
    DateTime? lastBackup,
    DateTime? firstData,
    DateTime? snoozedAt,
    required DateTime now,
  }) {
    if (!isWeb || !hasData) return false;
    if (snoozedAt != null && now.difference(snoozedAt) < backupSnooze) return false;
    final since = lastBackup ?? firstData;
    if (since == null) return false;
    return now.difference(since) >= backupEvery;
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// Dateiname des Backups wie in der APK: `darts_backup_JJJJ-MM-TT.json`.
  static String backupFileName(DateTime now) =>
      'darts_backup_${now.year}-${_two(now.month)}-${_two(now.day)}.json';

  /// „Zuletzt gesichert: …“ für Einstellungen und Erinnerung.
  static String lastBackupLabel(DateTime? last, DateTime now) {
    if (last == null) return 'Noch nie gesichert';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(last.year, last.month, last.day);
    final days = today.difference(day).inDays;
    if (days <= 0) return 'Zuletzt gesichert: heute';
    if (days == 1) return 'Zuletzt gesichert: gestern';
    return 'Zuletzt gesichert: vor $days Tagen';
  }
}

/// Behält die neuesten Zeilen (am Ende der Liste), bis [maxChars] erreicht ist.
List<String> trimToLimit(List<String> lines, int maxChars) {
  var total = 0;
  var start = lines.length;
  while (start > 0) {
    final len = lines[start - 1].length + 1;
    if (total + len > maxChars) break;
    total += len;
    start--;
  }
  return lines.sublist(start);
}

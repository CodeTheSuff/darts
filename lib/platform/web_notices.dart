import 'package:material_ui/material_ui.dart';

import '../ui/theme.dart';
import 'platform_env.dart';
import 'web_hints.dart';

/// Hinweise auf der Startseite, nur im Browser:
/// - „Zum Home-Bildschirm hinzufügen“ (Safari auf iPhone/iPad, noch nicht installiert)
/// - Erinnerung an ein Backup (Daten liegen nur in diesem Browser)
class WebNotices extends StatelessWidget {
  const WebNotices({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Plat.I.isWeb) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: WebHints.tick,
      builder: (context, _, _) {
        final install = WebHints.showInstallHint;
        final backup = WebHints.backupDue;
        if (!install && !backup) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (install) const _InstallHint(),
            if (backup) const _BackupReminder(),
          ],
        );
      },
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.tint,
    required this.title,
    required this.body,
    required this.onClose,
    this.actions = const [],
  });

  final IconData icon;
  final Color tint;
  final String title;
  final Widget body;
  final VoidCallback onClose;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return GlowCard(
      tint: tint,
      strength: 0.10,
      borderAlpha: 0.35,
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
      margin: const EdgeInsets.only(top: 8, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: tint, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                DefaultTextStyle.merge(style: TextStyle(color: C.muted, fontSize: 13, height: 1.3), child: body),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, children: actions),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Ausblenden',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, color: C.muted, size: 20),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _InstallHint extends StatelessWidget {
  const _InstallHint();

  @override
  Widget build(BuildContext context) {
    return _Notice(
      icon: Icons.add_to_home_screen_rounded,
      tint: C.accent,
      title: 'Zum Home-Bildschirm hinzufügen',
      onClose: WebHints.hideInstallHint,
      body: Text.rich(TextSpan(children: [
        const TextSpan(text: 'Tippe in Safari auf das Teilen-Symbol '),
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Icon(Icons.ios_share_rounded, size: 16, color: C.text),
        ),
        const TextSpan(text: ' und dann auf '),
        TextSpan(text: '„Zum Home-Bildschirm“', style: TextStyle(color: C.text, fontWeight: FontWeight.w700)),
        const TextSpan(
          text: '. Darts startet dann wie eine App im Vollbild.\n'
              'Wichtig: Ohne das löscht Safari Spieler und Statistiken, '
              'wenn du die Seite ein paar Tage nicht öffnest.',
        ),
      ])),
    );
  }
}

class _BackupReminder extends StatefulWidget {
  const _BackupReminder();

  @override
  State<_BackupReminder> createState() => _BackupReminderState();
}

class _BackupReminderState extends State<_BackupReminder> {
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final ok = await WebHints.exportBackup();
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup gespeichert')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup fehlgeschlagen: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Notice(
      icon: Icons.save_alt_rounded,
      tint: C.gold,
      title: 'Zeit für ein Backup',
      onClose: WebHints.snoozeBackup,
      body: Text('Deine Spieler und Statistiken liegen nur in diesem Browser. '
          'Sichere sie ab und zu als Datei. ${WebHints.lastBackupLabel}.'),
      actions: [
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _save,
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Jetzt sichern'),
        ),
        TextButton(onPressed: WebHints.snoozeBackup, child: const Text('Später')),
      ],
    );
  }
}

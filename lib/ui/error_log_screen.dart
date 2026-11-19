import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../data/error_log.dart';
import 'theme.dart';

/// Fehlerprotokoll ansehen, teilen und leeren.
class ErrorLogScreen extends StatelessWidget {
  const ErrorLogScreen({super.key});

  Future<void> _share(BuildContext context) async {
    final now = DateTime.now();
    final name = 'darts-fehlerprotokoll-${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}.txt';
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(utf8.encode(ErrorLog.exportText()), mimeType: 'text/plain', name: name)],
        subject: 'Darts – Fehlerprotokoll',
      ));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Teilen nicht möglich: $e')));
      }
    }
  }

  Future<void> _clear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Protokoll leeren?'),
        content: const Text('Alle gespeicherten Einträge werden gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Leeren')),
        ],
      ),
    );
    if (ok == true) ErrorLog.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fehlerprotokoll')),
      body: ValueListenableBuilder<List<LogItem>>(
        valueListenable: ErrorLog.entries,
        builder: (_, list, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text(
              'Hier landen Fehler, Ruckler und Hänger der App. Schick mir das Protokoll über „Teilen“, '
              'dann kann ich die Ursache finden.',
              style: TextStyle(color: C.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: list.isEmpty ? null : () => _share(context),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('Teilen'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: list.isEmpty ? null : () => _clear(context),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Leeren'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(Icons.check_circle_rounded, color: C.dbl, size: 48),
                    const SizedBox(height: 10),
                    Text('Keine Fehler gespeichert', style: TextStyle(color: C.muted, fontSize: 16)),
                  ],
                ),
              ),
            for (final e in list) _tile(context, e),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, LogItem e) {
    final d = DateTime.fromMillisecondsSinceEpoch(e.t);
    String two(int v) => v.toString().padLeft(2, '0');
    final when = '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
    final col = e.kind == 'stall' ? C.gold : C.danger;
    final icon = switch (e.kind) {
      'hang' || 'hangKilled' => Icons.hourglass_bottom_rounded,
      'stall' => Icons.slow_motion_video_rounded,
      _ => Icons.error_outline_rounded,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(14)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(icon, color: col),
          title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('$when · ${e.message}',
              maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 13)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(e.toText(), style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: C.muted2)),
          ],
        ),
      ),
    );
  }
}

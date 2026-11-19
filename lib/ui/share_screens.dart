import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../data/storage.dart';
import '../data/sync.dart';
import '../games/engine.dart';
import '../net/link.dart';
import 'theme.dart';

/// Spieler auswählen und als Datei oder an gekoppelte Geräte senden.
class ShareScreen extends StatefulWidget {
  const ShareScreen({super.key});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  late final Set<String> _sel = {for (final p in Store.profiles) p.id};
  bool _tournaments = true;

  void _snack(String t) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(t)));

  Future<void> _asFile() async {
    final pkg = Sync.build(_sel, tournaments: _tournaments);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name = 'darts_spieler_${now.year}-${two(now.month)}-${two(now.day)}.json';
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(utf8.encode(pkg.encode()), mimeType: 'application/json', name: name)],
        fileNameOverrides: [name],
        subject: 'Darts – Spielerdaten',
      ));
    } catch (e) {
      _snack('Teilen fehlgeschlagen: $e');
    }
  }

  void _toLinked() {
    final pkg = Sync.build(_sel, tournaments: _tournaments);
    Link.I.sendShare(pkg);
    _snack('An ${Link.I.peerCount} gekoppelte${Link.I.peerCount == 1 ? 's Gerät' : ' Geräte'} gesendet');
  }

  @override
  Widget build(BuildContext context) {
    final profiles = Store.profiles;
    final linked = Link.I.isConnected && Link.I.peerCount > 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Spieler teilen')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                    child: Text(
                        'Die Statistik wird Match für Match übertragen. Auf dem anderen Handy kommt nur dazu, '
                        'was dort noch fehlt – nichts wird doppelt gezählt.',
                        style: TextStyle(color: C.muted, fontSize: 13)),
                  ),
                  SectionTitle('Spieler', trailing: '${_sel.length} / ${profiles.length}'),
                  GlowCard(
                    padding: EdgeInsets.zero,
                    strength: 0.04,
                    child: Column(
                      children: [
                        CheckboxListTile(
                          value: _sel.length == profiles.length,
                          onChanged: (v) => setState(() {
                            _sel.clear();
                            if (v == true) _sel.addAll(profiles.map((p) => p.id));
                          }),
                          title: const Text('Alle', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                        for (final p in profiles)
                          CheckboxListTile(
                            value: _sel.contains(p.id),
                            onChanged: (v) => setState(() => v == true ? _sel.add(p.id) : _sel.remove(p.id)),
                            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                                '${Store.statsFor(p.id).x01.matches} X01-Matches · Ø ${fmt1(Store.statsFor(p.id).x01.average)}',
                                style: TextStyle(color: C.muted, fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                  GlowCard(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    strength: 0.04,
                    child: SwitchListTile(
                      value: _tournaments,
                      onChanged: (v) => setState(() => _tournaments = v),
                      title: const Text('Turniere mitsenden', style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('Turniere, an denen diese Spieler teilnehmen',
                          style: TextStyle(color: C.muted, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Column(
                children: [
                  if (linked) ...[
                    PrimaryButton(
                      label: 'An gekoppelte Geräte senden',
                      icon: Icons.wifi_tethering_rounded,
                      onTap: _sel.isEmpty ? null : _toLinked,
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: Key3(
                      semantics: 'Als Datei teilen',
                      onTap: _sel.isEmpty ? null : _asFile,
                      enabled: _sel.isNotEmpty,
                      color: linked ? C.surface2 : null,
                      gradient: linked ? null : C.accentGradient,
                      borderColor: linked ? C.line : Colors.transparent,
                      radius: 18,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.ios_share_rounded, color: linked ? C.text : C.onAccent),
                          const SizedBox(width: 8),
                          Text('Als Datei teilen',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 16, color: linked ? C.text : C.onAccent)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vorschau beim Import: Zuordnung der eingehenden Spieler.
class ImportPreviewScreen extends StatefulWidget {
  const ImportPreviewScreen({super.key, required this.pkg});
  final SharePackage pkg;

  @override
  State<ImportPreviewScreen> createState() => _ImportPreviewScreenState();
}

class _ImportPreviewScreenState extends State<ImportPreviewScreen> {
  late final Map<String, MergeChoice> _choices = Sync.suggest(widget.pkg);

  void _apply() {
    final (added, created, ts) = Sync.apply(widget.pkg, _choices);
    final parts = [
      '$added neue Match-Einträge',
      if (created > 0) '$created neue Spieler',
      if (ts > 0) '$ts Turniere',
    ];
    Navigator.of(context).pop('Übernommen: ${parts.join(' · ')}');
  }

  @override
  Widget build(BuildContext context) {
    final pkg = widget.pkg;
    final locals = Store.profiles;
    return Scaffold(
      appBar: AppBar(title: const Text('Daten übernehmen')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  GlowCard(
                    strength: 0.10,
                    child: Row(
                      children: [
                        Icon(Icons.phone_android_rounded, color: C.accent, size: 30),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Von ${pkg.deviceName}',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                              Text(
                                  '${pkg.profiles.length} Spieler · ${pkg.entries.length} Einträge'
                                  '${pkg.tournaments.isNotEmpty ? ' · ${pkg.tournaments.length} Turniere' : ''}',
                                  style: TextStyle(color: C.muted, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SectionTitle('Zuordnung'),
                  for (final p in pkg.profiles) _row(p.id, p.name, locals),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: PrimaryButton(label: 'Übernehmen', icon: Icons.download_done_rounded, onTap: _apply),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String id, String name, List<dynamic> locals) {
    final c = _choices[id]!;
    final fresh = widget.pkg.newEntriesOf(id);
    final items = <DropdownMenuItem<String>>[
      for (final l in locals) DropdownMenuItem(value: 'm:${l.id}', child: Text('mit ${l.name}')),
      const DropdownMenuItem(value: 'new', child: Text('Neu anlegen')),
      const DropdownMenuItem(value: 'skip', child: Text('Nicht übernehmen')),
    ];
    final value = switch (c.kind) {
      MergeKind.merge => 'm:${c.localId}',
      MergeKind.create => 'new',
      MergeKind.skip => 'skip',
    };
    return GlowCard(
      strength: 0.04,
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(fresh == 0 ? 'Schon aktuell' : (fresh == 1 ? '1 neuer Eintrag' : '$fresh neue Einträge'),
                    style: TextStyle(color: fresh == 0 ? C.muted : C.dbl, fontSize: 12)),
              ],
            ),
          ),
          DropdownButton<String>(
            value: items.any((i) => i.value == value) ? value : 'new',
            underline: const SizedBox(),
            borderRadius: BorderRadius.circular(14),
            dropdownColor: C.surface2,
            items: items,
            onChanged: (v) => setState(() {
              if (v == null) return;
              if (v == 'new') {
                c.kind = MergeKind.create;
              } else if (v == 'skip') {
                c.kind = MergeKind.skip;
              } else {
                c.kind = MergeKind.merge;
                c.localId = v.substring(2);
              }
            }),
          ),
        ],
      ),
    );
  }
}

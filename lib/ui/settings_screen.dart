import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../data/sound.dart';
import '../data/storage.dart';
import '../data/sync.dart';
import 'look.dart';
import 'about_screen.dart';
import 'share_screens.dart';
import 'theme.dart';
import 'tutorial/tutorial_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _confirm(String title, String text, String action, {bool danger = true}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: danger ? FilledButton.styleFrom(backgroundColor: C.danger, foregroundColor: Colors.white) : null,
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _export() async {
    try {
      final json = Store.exportBackup();
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final name = 'darts_backup_${now.year}-${two(now.month)}-${two(now.day)}.json';
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(utf8.encode(json), mimeType: 'application/json', name: name)],
        fileNameOverrides: [name],
        subject: 'Darts – Backup',
      ));
    } catch (e) {
      _snack('Export fehlgeschlagen: $e');
    }
  }

  Future<void> _import() async {
    try {
      final f = await FilePicker.pickFile(type: FileType.any);
      if (f == null) return;
      final text = utf8.decode(await f.readAsBytes());
      if (!mounted) return;
      // Spielerdaten eines anderen Handys → Vorschau mit Zuordnung
      final root = jsonDecode(text);
      if (SharePackage.looksLike(root)) {
        final pkg = SharePackage.fromJson(Map<String, dynamic>.from(root as Map));
        final res = await Navigator.of(context)
            .push<String>(MaterialPageRoute(builder: (_) => ImportPreviewScreen(pkg: pkg)));
        if (res != null) _snack(res);
        if (mounted) setState(() {});
        return;
      }
      final ok = await _confirm(
        'Backup wiederherstellen?',
        'Alle aktuellen Spieler, Statistiken und Turniere werden durch die Sicherung ersetzt.',
        'Wiederherstellen',
      );
      if (!ok) return;
      final n = await Store.importBackup(text);
      if (!mounted) return;
      setState(() {});
      _snack('Backup wiederhergestellt – $n Spieler');
    } on FormatException {
      _snack('Die Datei ist keine Darts-Counter-Datei.');
    } catch (e) {
      _snack('Import fehlgeschlagen: $e');
    }
  }

  void _setTheme(String id) {
    Haptics.selection();
    Store.themeId = id;
    applyStoredTheme(context: context);
    setState(() {});
  }

  void _applyLook() {
    applyStoredTheme(context: context);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const SectionTitle('Ton & Feedback'),
          _group([
            _switch(Icons.volume_up_rounded, 'Ton', 'Soundeffekte bei Würfen und Erfolgen', Store.soundOn,
                (v) => setState(() => Store.soundOn = v)),
            _slider(),
            _switch(Icons.vibration_rounded, 'Vibration', 'Kurzes Feedback beim Tippen', Store.vibration,
                (v) => setState(() => Store.vibration = v)),
            _switch(Icons.celebration_rounded, 'Jubel-Animationen', '180, Ton+, Leg- und Match-Gewinn',
                Store.celebrations, (v) => setState(() => Store.celebrations = v)),
          ]),
          const SizedBox(height: 14),
          const SectionTitle('Spiel'),
          _group([
            _switch(Icons.flag_rounded, 'Checkout-Hilfe', 'Finish-Vorschlag im X01 anzeigen', Store.checkoutHint,
                (v) => setState(() => Store.checkoutHint = v)),
            _switch(Icons.swap_horiz_rounded, 'Single Out anbieten',
                'Nach 5 Aufnahmen ohne Treffer im Finish: Leg auch ohne Double beenden', Store.singleOutOffer,
                (v) => setState(() => Store.singleOutOffer = v)),
            _switch(Icons.record_voice_over_rounded, 'Ansagen (Sounds)',
                '80–180, Bullseye, „1“ und „You win“ – bei verbundener Anzeige spielt nur die Anzeige',
                Store.announce, (v) => setState(() => Store.announce = v)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _icon(Icons.smart_toy_rounded),
                      const SizedBox(width: 12),
                      const Text('Bot-Tempo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Langsam')),
                        ButtonSegment(value: 1, label: Text('Normal')),
                        ButtonSegment(value: 2, label: Text('Schnell')),
                      ],
                      selected: {Store.botSpeed},
                      onSelectionChanged: (v) => setState(() => Store.botSpeed = v.first),
                      style: segStyle(),
                    ),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),
          const SectionTitle('Design'),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.05,
            children: [for (final p in palettes) _themeTile(p), _autoTile()],
          ),
          if (Store.themeId == 'auto')
            GlowCard(
              margin: const EdgeInsets.only(top: 10),
              strength: 0.04,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Design am Abend', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  Text('Tagsüber gilt „Hell“, sobald das Handy dunkel ist dieses:',
                      style: TextStyle(fontSize: 12, color: C.muted)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in palettes.where((p) => !p.isLight))
                        ChoiceChip(
                          label: Text(p.name),
                          selected: Store.nightThemeId == p.id,
                          onSelected: (_) {
                            Store.nightThemeId = p.id;
                            _applyLook();
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          _group([
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _icon(Icons.format_size_rounded),
                      const SizedBox(width: 12),
                      const Text('Schriftgröße', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<double>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 1.0, label: Text('Normal')),
                        ButtonSegment(value: 1.15, label: Text('Groß')),
                      ],
                      selected: {Store.fontScale},
                      onSelectionChanged: (v) {
                        Store.fontScale = v.first;
                        _applyLook();
                      },
                      style: segStyle(),
                    ),
                  ),
                ],
              ),
            ),
            _switch(Icons.visibility_rounded, 'Modus für Farbschwäche',
                'Andere Farben und Symbole für Double, Triple und Miss', Store.colorblind, (v) {
              Store.colorblind = v;
              _applyLook();
            }),
          ]),
          const SizedBox(height: 18),
          const SectionTitle('Daten'),
          _group([
            _switch(Icons.sync_rounded, 'Automatisch abgleichen',
                'Gekoppelte Handys tauschen Spielerdaten beim Koppeln und nach jedem Spiel aus', Store.autoSync,
                (v) => setState(() => Store.autoSync = v)),
            _action(Icons.pin_rounded, 'Raum-Code: ${Store.roomCode}',
                'Fester Code beim Koppeln, damit andere Geräte sich ohne Neueingabe verbinden', _editRoomCode),
            _action(Icons.group_rounded, 'Spieler teilen', 'Statistiken an ein anderes Handy senden', () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShareScreen()));
            }),
            _action(Icons.file_open_rounded, 'Daten importieren', 'Spielerdaten oder Backup öffnen', _import),
            _action(Icons.ios_share_rounded, 'Backup exportieren', 'Komplette Sicherung als Datei', _export),
            _action(Icons.restart_alt_rounded, 'Statistiken zurücksetzen', 'Spieler bleiben erhalten', () async {
              if (await _confirm('Statistiken zurücksetzen?',
                  'Alle Averages, Bestleistungen und Bilanzen werden gelöscht.', 'Zurücksetzen')) {
                Store.resetStats();
                _snack('Statistiken zurückgesetzt');
              }
            }, danger: true),
            _action(Icons.person_remove_rounded, 'Alle Spieler löschen', 'Inklusive ihrer Statistiken', () async {
              if (await _confirm('Alle Spieler löschen?',
                  'Alle gespeicherten Spieler und ihre Statistiken werden entfernt. Turniere bleiben erhalten.',
                  'Löschen')) {
                Store.deleteAllPlayers();
                _snack('Alle Spieler gelöscht');
              }
            }, danger: true),
          ]),
          const SizedBox(height: 18),
          const SectionTitle('App'),
          _group([
            _action(Icons.menu_book_rounded, 'Tutorial', 'Alle Funktionen ausführlich erklärt',
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TutorialScreen()))),
            _action(Icons.school_rounded, 'Einführung erneut zeigen', 'Kurzer Rundgang über die Startseite', () {
              Store.onboarded = false;
              Navigator.of(context).popUntil((r) => r.isFirst);
            }),
            _action(Icons.new_releases_rounded, 'Was ist neu', 'Neuerungen in Version $appVersion',
                () => showWhatsNew(context)),
            _action(Icons.info_outline_rounded, 'Über die App', 'Version, Lizenzen',
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen()))),
          ]),
        ],
      ),
    );
  }

  Future<void> _editRoomCode() async {
    final ctl = TextEditingController(text: Store.roomCode);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Raum-Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Diesen Code geben andere Geräte beim Koppeln ein. Er bleibt gleich, bis du ihn änderst.'),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              style: const TextStyle(fontFamily: numFont, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 8),
              decoration: const InputDecoration(labelText: '4 Ziffern', counterText: ''),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, (1000 + DateTime.now().microsecond % 9000).toString()),
            child: const Text('Zufällig'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Speichern')),
        ],
      ),
    );
    if (v == null) return;
    if (!RegExp(r'^\d{4}$').hasMatch(v)) {
      _snack('Der Code muss aus genau 4 Ziffern bestehen.');
      return;
    }
    setState(() => Store.roomCode = v);
    _snack('Raum-Code ist jetzt $v. Er gilt ab dem nächsten geöffneten Raum.');
  }

  Widget _group(List<Widget> children) => GlowCard(
        padding: EdgeInsets.zero,
        strength: 0.04,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, color: C.surface3, indent: 14, endIndent: 14),
              children[i],
            ],
          ],
        ),
      );

  Widget _icon(IconData icon, {Color? color}) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: (color ?? C.accent).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, size: 20, color: color ?? C.accent),
      );

  Widget _switch(IconData icon, String title, String sub, bool value, ValueChanged<bool> onChanged) => InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              _icon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    Text(sub, style: TextStyle(fontSize: 12, color: C.muted)),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      );

  Widget _slider() => AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: Store.soundOn ? 1 : 0.4,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          child: Row(
            children: [
              _icon(Icons.graphic_eq_rounded),
              const SizedBox(width: 12),
              const Text('Lautstärke', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Expanded(
                child: Slider(
                  value: Store.volume,
                  divisions: 10,
                  label: '${(Store.volume * 100).round()} %',
                  onChanged: Store.soundOn ? (v) => setState(() => Store.volume = v) : null,
                  onChangeEnd: (_) => Sound.play('thunk'),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _action(IconData icon, String title, String sub, VoidCallback onTap, {bool danger = false}) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              _icon(icon, color: danger ? C.danger : null),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: danger ? C.danger : C.text)),
                    Text(sub, style: TextStyle(fontSize: 12, color: C.muted)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: C.muted),
            ],
          ),
        ),
      );

  Widget _autoTile() {
    final selected = Store.themeId == 'auto';
    final day = paletteById('hell');
    final night = paletteById(Store.nightThemeId);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Design Automatisch',
      child: GestureDetector(
        onTap: () => _setTheme('auto'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? C.accent : C.border, width: selected ? 2.5 : 1),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [day.bg, day.bg, night.bg, night.bg],
              stops: const [0, 0.52, 0.52, 1],
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Row(
                    children: [
                      Icon(Icons.light_mode_rounded, color: day.accent, size: 28),
                      const Spacer(),
                      Text('Tag', style: TextStyle(color: day.muted, fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Automatisch',
                            style: TextStyle(color: night.text, fontWeight: FontWeight.w800, fontSize: 15)),
                        Text('Wie das Handy', style: TextStyle(color: night.muted, fontSize: 11)),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle_rounded, color: C.accent, size: 22)
                  else
                    Icon(Icons.dark_mode_rounded, color: night.accent, size: 22),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _themeTile(AppPalette p) {
    final selected = Store.themeId == p.id;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Design ${p.name}',
      child: GestureDetector(
        onTap: () => _setTheme(p.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: p.bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? C.accent : C.border, width: selected ? 2.5 : 1),
            boxShadow: selected ? [BoxShadow(color: C.accent.withValues(alpha: 0.3), blurRadius: 16)] : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mini-Vorschau: Karte mit Punktestand + Button
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color.alphaBlend(p.accent.withValues(alpha: 0.16), p.surface), p.surface],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.accent.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(width: 7, height: 7, decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle)),
                          const SizedBox(width: 4),
                          Container(width: 34, height: 5, color: p.muted.withValues(alpha: 0.6)),
                        ],
                      ),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text('501',
                              style: TextStyle(
                                  fontFamily: numFont, fontSize: 30, fontWeight: FontWeight.w700, color: p.text)),
                        ),
                      ),
                      Container(
                        height: 10,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          gradient: LinearGradient(colors: [p.accent, Color.lerp(p.accent, p.accent2, 0.65)!]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name, style: TextStyle(color: p.text, fontWeight: FontWeight.w800, fontSize: 15)),
                        Text(p.tagline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.muted, fontSize: 11)),
                      ],
                    ),
                  ),
                  if (selected) Icon(Icons.check_circle_rounded, color: C.accent, size: 22),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

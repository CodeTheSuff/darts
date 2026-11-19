import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/error_log.dart';
import 'error_log_screen.dart';

import '../data/storage.dart';
import 'logo.dart';
import 'theme.dart';

const appVersion = '2.4.0';

/// Neuerungen je Version (neueste zuerst).
const changelog = <String, List<(IconData, String, String)>>{
  '2.4.0': [
    (Icons.swap_horiz_rounded, 'Single Out anbieten', 'Wer 5 Aufnahmen am Double hängt, kann das Leg auch single beenden'),
    (Icons.tv_rounded, 'Größere Anzeige', 'Finish-Weg, Darts, Namen und Average auf dem 2. Bildschirm viel größer'),
    (Icons.verified_user_rounded, 'Sichere Kopplung', 'Neue Geräte müssen am Host bestätigt werden, der Code wird nicht mehr verraten'),
    (Icons.speed_rounded, 'Schneller', 'Schnellere Gerätesuche und flüssigeres Spiel mit gekoppelten Geräten'),
    (Icons.bug_report_rounded, 'Fehlerprotokoll', 'Fehler und Hänger werden gespeichert und lassen sich teilen'),
  ],
  '2.3.0': [
    (Icons.devices_rounded, 'Bekannte Geräte', 'Einmal gekoppelt, danach mit einem Tippen wieder verbinden'),
    (Icons.pin_rounded, 'Fester Raum-Code', 'Bleibt immer gleich und ist in den Einstellungen änderbar'),
    (Icons.wifi_find_rounded, 'Suche in großen WLANs', 'Findet Räume jetzt auch in großen Netzen'),
  ],
  '2.2.0': [
    (Icons.tv_rounded, 'Schönere Anzeige', 'Scoreboard mit den 3 Darts der Aufnahme, Jubel-Animationen und hervorgehobenem Sieger'),
    (Icons.wifi_find_rounded, 'Bessere Gerätesuche', 'Findet Räume jetzt auch in WLANs, die Broadcasts blockieren'),
  ],
  '2.1.0': [
    (Icons.tune_rounded, 'Eigene Bots', 'Average und Doppelquote frei einstellen oder einen Bot auf deinem Niveau wählen'),
    (Icons.record_voice_over_rounded, 'Neue Caller-Stimme', 'Tiefe Männerstimme, „180“ wie im TV, Stimme in den Einstellungen wählbar'),
    (Icons.auto_awesome_rounded, 'Neues Logo', 'Helles, blaues App-Icon'),
  ],
  '2.0.0': [
    (Icons.palette_rounded, 'Neues Design', '5 Themes, „Automatisch“ wie das Handy, größere Schrift, Modus für Farbschwäche'),
    (Icons.emoji_events_rounded, 'Turniere', 'K.o., Doppel-K.o., Gruppen und Liga für 3–32 Spieler'),
    (Icons.smart_toy_rounded, 'Bots', 'Spiel gegen Bots von Leicht bis Profi'),
    (Icons.wifi_tethering_rounded, 'Handys koppeln', 'Gemeinsam eintragen, Scoreboard-Anzeige und automatischer Datenabgleich'),
    (Icons.record_voice_over_rounded, 'Caller', 'Ansage der Punkte und Restpunkte wie im TV'),
    (Icons.insights_rounded, 'Mehr Statistik', 'Verlauf, Match-Historie, Direktvergleich, Doppel-Analyse und Erfolge'),
    (Icons.ios_share_rounded, 'Ergebnis teilen', 'Ergebniskarte als Bild für WhatsApp & Co.'),
  ],
};

/// Lizenz der mitgelieferten Schrift registrieren (einmalig).
void registerLicenses() {
  LicenseRegistry.addLicense(() async* {
    try {
      final text = await rootBundle.loadString('assets/fonts/OFL.txt');
      yield LicenseEntryWithLineBreaks(['Barlow (Schrift)'], text);
    } catch (_) {}
  });
}

/// Zeigt „Was ist neu“ einmal nach einem Update – beim allerersten Start nicht.
Future<void> maybeShowWhatsNew(BuildContext context) async {
  final seen = Store.seenVersion;
  Store.seenVersion = appVersion;
  if (seen == appVersion) return;
  // Erster Start überhaupt (keine Spieler, keine Daten): keine Neuerungen zeigen.
  if (seen == null && Store.profiles.isEmpty) return;
  await showWhatsNew(context);
}

Future<void> showWhatsNew(BuildContext context) {
  final items = changelog[appVersion] ?? const [];
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                  width: 40, height: 4, decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const DartsLogo(size: 44),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Was ist neu', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    Text('Version $appVersion', style: TextStyle(color: C.muted, fontSize: 13)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (icon, title, text) in items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon, color: C.accent, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                Text(text, style: TextStyle(color: C.muted, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            PrimaryButton(label: 'Los geht’s', icon: null, onTap: () => Navigator.pop(ctx)),
          ],
        ),
      ),
    ),
  );
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Über die App')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Center(
            child: Column(
              children: [
                const DartsLogo(size: 104, radius: 28),
                const SizedBox(height: 14),
                const Text('Darts', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
                Text('Version $appVersion', style: TextStyle(color: C.muted)),
                const SizedBox(height: 10),
                Text('Punktezähler, Training, Minispiele und Turniere –\nfür einen oder mehrere Spieler und Handys.',
                    textAlign: TextAlign.center, style: TextStyle(color: C.muted2, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 22),
          GlowCard(
            padding: EdgeInsets.zero,
            strength: 0.04,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.new_releases_rounded, color: C.accent),
                  title: const Text('Was ist neu', style: TextStyle(fontWeight: FontWeight.w700)),
                  trailing: Icon(Icons.chevron_right_rounded, color: C.muted),
                  onTap: () => showWhatsNew(context),
                ),
                Divider(height: 1, color: C.surface3, indent: 14, endIndent: 14),
                ValueListenableBuilder<List<LogItem>>(
                  valueListenable: ErrorLog.entries,
                  builder: (_, list, _) => ListTile(
                    leading: Icon(Icons.bug_report_rounded, color: C.accent),
                    title: const Text('Fehlerprotokoll', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(list.isEmpty ? 'Keine Fehler gespeichert' : '${list.length} Einträge – ansehen und teilen',
                        style: TextStyle(color: C.muted)),
                    trailing: Icon(Icons.chevron_right_rounded, color: C.muted),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ErrorLogScreen())),
                  ),
                ),
                Divider(height: 1, color: C.surface3, indent: 14, endIndent: 14),
                ListTile(
                  leading: Icon(Icons.description_rounded, color: C.accent),
                  title: const Text('Lizenzen', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('Verwendete Pakete und die Schrift Barlow', style: TextStyle(color: C.muted)),
                  trailing: Icon(Icons.chevron_right_rounded, color: C.muted),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Darts',
                    applicationVersion: appVersion,
                    applicationIcon: const Padding(padding: EdgeInsets.all(12), child: DartsLogo(size: 64)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Alle Daten bleiben auf deinem Handy. Gekoppelte Handys tauschen Daten nur direkt im eigenen WLAN aus.',
              textAlign: TextAlign.center, style: TextStyle(color: C.muted, fontSize: 12)),
        ],
      ),
    );
  }
}

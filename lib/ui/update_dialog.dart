import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/error_log.dart';
import '../net/update_check.dart';
import '../net/web_bridge.dart';
import 'about_screen.dart' show appBuild;
import 'link_coordinator.dart' show navigatorKey;
import 'theme.dart';

/// Update-Hinweis: APK → „Herunterladen“ (Browser lädt, Android installiert),
/// Web → „Neu laden“.
class UpdateUi {
  UpdateUi._();

  static bool _showing = false;
  static bool _startChecked = false;

  /// Einmal beim App-Start (höchstens 1× am Tag wirklich abfragen).
  static Future<void> checkOnStart() async {
    if (_startChecked) return;
    _startChecked = true;
    await checkNow();
  }

  /// Beim Online-Koppeln bzw. von Hand ([force] = auch wenn heute schon geprüft).
  static Future<bool> checkNow({bool force = false}) async {
    try {
      final offer = await UpdateCheck.check(installedBuild: appBuild, web: kIsWeb, force: force);
      if (offer == null) return false;
      await show(offer);
      return true;
    } catch (e) {
      ErrorLog.crumb('Update-Prüfung fehlgeschlagen: $e');
      return false;
    }
  }

  /// Relais meldet „App zu alt“: sofort anzeigen (Angaben ggf. aus version.json ergänzen).
  static Future<void> showRequired(Map<String, dynamic>? update) async {
    var offer = UpdateCheck.fromRelay(update, web: kIsWeb);
    if (offer.apk == null || offer.info.notes.isEmpty) {
      final info = await UpdateCheck.fetch();
      if (info != null) {
        offer = UpdateCheck.evaluate(info, installedBuild: 0, web: kIsWeb, required: true) ?? offer;
      }
    }
    await show(offer);
  }

  static Future<void> show(UpdateOffer offer) async {
    final ctx = navigatorKey.currentContext;
    if (_showing || ctx == null || !ctx.mounted) return;
    _showing = true;
    try {
      await showDialog<void>(context: ctx, builder: (c) => UpdateDialog(offer: offer));
    } finally {
      _showing = false;
    }
  }
}

class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key, required this.offer});

  final UpdateOffer offer;

  Future<void> _download(BuildContext context) async {
    final apk = offer.apk;
    if (apk == null) return;
    var ok = false;
    try {
      ok = await launchUrl(apk, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.pop(context);
    if (!ok) messenger?.showSnackBar(SnackBar(content: Text('Download konnte nicht geöffnet werden: $apk')));
  }

  @override
  Widget build(BuildContext context) {
    final v = offer.info.version;
    final title = offer.web ? 'Neue Version verfügbar' : 'Neue Version $v';
    return AlertDialog(
      icon: Icon(offer.web ? Icons.refresh_rounded : Icons.system_update_rounded, size: 36, color: C.accent),
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (offer.required)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Diese Version ist zu alt für den Server. Online koppeln geht erst nach dem Update '
                  '(im WLAN klappt es weiterhin).',
                  style: TextStyle(color: C.danger, fontWeight: FontWeight.w700),
                ),
              ),
            if (offer.web)
              Text('Version $v ist da – einfach neu laden.', style: TextStyle(color: C.muted)),
            for (final n in offer.info.notes)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: TextStyle(color: C.accent, fontWeight: FontWeight.w800)),
                    Expanded(child: Text(n)),
                  ],
                ),
              ),
            if (!offer.web && offer.apk == null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Auf dem Server liegt keine APK – bitte beim Betreiber nachfragen.',
                    style: TextStyle(color: C.muted, fontSize: 13)),
              ),
            if (!offer.web && offer.apk != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Der Browser lädt die neue APK. Danach antippen und „Installieren“ – deine Daten bleiben erhalten.',
                  style: TextStyle(color: C.muted, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Später')),
        if (offer.web)
          FilledButton.icon(
            onPressed: reloadPage,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Neu laden'),
          )
        else if (offer.apk != null)
          FilledButton.icon(
            onPressed: () => _download(context),
            icon: const Icon(Icons.download_rounded),
            label: const Text('Herunterladen'),
          ),
      ],
    );
  }
}

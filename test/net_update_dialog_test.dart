import 'package:darts_counter/net/update_check.dart';
import 'package:darts_counter/ui/update_dialog.dart';
import 'package:darts_protocol/darts_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Eigene Datei: Widget-Tests ersetzen den HttpClient (→ 400), das stört die Abruf-Tests.
void main() {
  const info = VersionInfo(
      version: '3.0.1', build: 20, minProtocol: 3, apkUrl: 'apk/Darts_3.0.1.apk', notes: ['Fehler behoben']);

  testWidgets('Dialog zeigt Version, Änderungen und „Herunterladen“ bzw. „Neu laden“', (t) async {
    final o = UpdateCheck.evaluate(info, installedBuild: 19, web: false, server: 'http://h')!;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: UpdateDialog(offer: o))));
    expect(find.text('Neue Version 3.0.1'), findsOneWidget);
    expect(find.text('Fehler behoben'), findsOneWidget);
    expect(find.text('Herunterladen'), findsOneWidget);
    final w = UpdateCheck.evaluate(info, installedBuild: 19, web: true)!;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: UpdateDialog(offer: w))));
    expect(find.text('Neue Version verfügbar'), findsOneWidget);
    expect(find.text('Neu laden'), findsOneWidget);
    final r = UpdateCheck.fromRelay({'version': '3.1.0'}, web: false);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: UpdateDialog(offer: r))));
    expect(find.textContaining('zu alt'), findsOneWidget);
    expect(find.textContaining('keine APK'), findsOneWidget);
  });
}

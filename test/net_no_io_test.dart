import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Die Web-App darf kein `dart:io` laden: nur `lan_io.dart` und `web_bridge_io.dart`
/// (per Conditional Import, nicht im Web) dürfen es benutzen.
void main() {
  final ioImport = RegExp(r'''^\s*import\s+['"]dart:io['"]''', multiLine: true);

  test('lib/net/link.dart importiert kein dart:io', () {
    final src = File('lib/net/link.dart').readAsStringSync();
    expect(ioImport.hasMatch(src), isFalse);
    // WLAN-Teil nur per Conditional Import
    expect(src, contains("'lan_stub.dart' if (dart.library.io) 'lan_io.dart'"));
  });

  test('Kopplungs-Dateien ohne dart:io (außer den IO-Weichen)', () {
    const allowed = {'lan_io.dart', 'web_bridge_io.dart'};
    final files = [
      ...Directory('lib/net').listSync().whereType<File>().where((f) => f.path.endsWith('.dart')),
      File('lib/ui/link_screen.dart'),
      File('lib/ui/link_coordinator.dart'),
      File('lib/ui/update_dialog.dart'),
    ];
    for (final f in files) {
      final name = f.uri.pathSegments.last;
      if (allowed.contains(name)) continue;
      expect(ioImport.hasMatch(f.readAsStringSync()), isFalse, reason: '$name importiert dart:io');
    }
  });
}

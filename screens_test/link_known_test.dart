import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/ui/link_screen.dart';
import 'package:darts_counter/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'v4_screens_test.dart' show loadFonts, shot, prep, settle;

void main() {
  setUpAll(loadFonts);
  testWidgets('Bekannte Geräte', (t) async {
    await prep(t, {}, size: const Size(412, 1000));
    Store.rememberHost(KnownHost(device: 'a', name: 'Simons S24', address: '10.192.37.14', port: 47123, code: '4711'));
    Store.rememberHost(
        KnownHost(device: 'b', name: 'Tablet Wand', address: '10.192.51.80', port: 47123, code: '2580', viewer: true));
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(C.p), home: const LinkScreen()));
    await settle(t, 4);
    await shot(t, 'link_known');
    await t.pumpWidget(const SizedBox());
    await settle(t, 2);
  });
}

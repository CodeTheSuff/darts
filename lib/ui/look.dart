import 'package:material_ui/material_ui.dart';

import '../data/storage.dart';
import 'theme.dart';

/// Theme, Farbschwäche-Modus und Schriftgröße aus den Einstellungen übernehmen.
void applyStoredTheme({BuildContext? context}) {
  ThemeHost.fontScale = Store.fontScale;
  final system = WidgetsBinding.instance.platformDispatcher.platformBrightness;
  ThemeHost.apply(ThemeHost.resolve(Store.themeId, Store.nightThemeId, system),
      context: context, colorblind: Store.colorblind);
}

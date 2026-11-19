import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Ein komplettes Farbschema der App.
class AppPalette {
  const AppPalette({
    required this.id,
    required this.name,
    required this.tagline,
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.border,
    required this.line,
    required this.text,
    required this.muted,
    required this.muted2,
    required this.accent,
    required this.accent2,
    required this.onAccent,
    this.dbl = const Color(0xFF3DD68C),
    this.trp = const Color(0xFFFF8A3D),
    this.miss = const Color(0xFFFF5C5C),
    this.gold = const Color(0xFFFFD166),
  });

  final String id;
  final String name;
  final String tagline;
  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color border;
  final Color line;
  final Color text;
  final Color muted;
  final Color muted2;

  /// Hauptakzent (Buttons, Auswahl, Navigation) und Zweitakzent (Verläufe).
  final Color accent;
  final Color accent2;
  final Color onAccent;
  final Color dbl;

  /// Triple (orange) – Rot ist für Miss reserviert.
  final Color trp;

  /// Miss und Warnungen (rot).
  final Color miss;
  final Color gold;

  bool get isLight => brightness == Brightness.light;

  /// Variante für Farbschwäche: Double, Triple und Miss gut unterscheidbar
  /// auch bei Rot-Grün-Schwäche (angelehnt an die Okabe-Ito-Palette).
  AppPalette colorblind() => AppPalette(
        id: id,
        name: name,
        tagline: tagline,
        brightness: brightness,
        bg: bg,
        surface: surface,
        surface2: surface2,
        surface3: surface3,
        border: border,
        line: line,
        text: text,
        muted: muted,
        muted2: muted2,
        accent: accent,
        accent2: accent2,
        onAccent: onAccent,
        dbl: isLight ? const Color(0xFF0A8FA8) : const Color(0xFF2CC6DB),
        trp: isLight ? const Color(0xFFB97F00) : const Color(0xFFF2A900),
        miss: isLight ? const Color(0xFFC24F12) : const Color(0xFFE8642A),
        gold: gold,
      );
}

const palettes = <AppPalette>[
  AppPalette(
    id: 'arena',
    name: 'Arena',
    tagline: 'Modern & klar',
    brightness: Brightness.dark,
    bg: Color(0xFF111317),
    surface: Color(0xFF1B1E24),
    surface2: Color(0xFF22262D),
    surface3: Color(0xFF2B3038),
    border: Color(0xFF2D323A),
    line: Color(0xFF3B414A),
    text: Color(0xFFF2F4F6),
    muted: Color(0xFF98A2AD),
    muted2: Color(0xFFC4CBD3),
    accent: Color(0xFF4F9DFF),
    accent2: Color(0xFF7C5CFF),
    onAccent: Color(0xFF06101F),
  ),
  AppPalette(
    id: 'pub',
    name: 'Pub',
    tagline: 'Dunkelgrün & Messing',
    brightness: Brightness.dark,
    bg: Color(0xFF0C1712),
    surface: Color(0xFF13231B),
    surface2: Color(0xFF192C22),
    surface3: Color(0xFF21382B),
    border: Color(0xFF284031),
    line: Color(0xFF365240),
    text: Color(0xFFF4EFE3),
    muted: Color(0xFF98AE9F),
    muted2: Color(0xFFCAD5C9),
    accent: Color(0xFFDDA845),
    accent2: Color(0xFFB4632F),
    onAccent: Color(0xFF1C1205),
  ),
  AppPalette(
    id: 'turnier',
    name: 'Turnier',
    tagline: 'Schwarz & Rot wie im TV',
    brightness: Brightness.dark,
    bg: Color(0xFF09090A),
    surface: Color(0xFF151517),
    surface2: Color(0xFF1C1C1F),
    surface3: Color(0xFF262629),
    border: Color(0xFF2C2C31),
    line: Color(0xFF3B3B41),
    text: Color(0xFFF6F6F6),
    muted: Color(0xFF9D9DA5),
    muted2: Color(0xFFCBCBD1),
    accent: Color(0xFFEF3B48),
    accent2: Color(0xFFFF8A3D),
    onAccent: Color(0xFF1F0306),
    miss: Color(0xFFFF6B6B),
  ),
  AppPalette(
    id: 'neon',
    name: 'Neon',
    tagline: 'Violett, Cyan & Pink',
    brightness: Brightness.dark,
    bg: Color(0xFF0E0A1D),
    surface: Color(0xFF17112E),
    surface2: Color(0xFF1E1739),
    surface3: Color(0xFF281F48),
    border: Color(0xFF332858),
    line: Color(0xFF44366D),
    text: Color(0xFFF5F1FF),
    muted: Color(0xFFA49CC6),
    muted2: Color(0xFFD1CAEC),
    accent: Color(0xFF2CE5E8),
    accent2: Color(0xFFFF4FD8),
    onAccent: Color(0xFF041819),
  ),
  AppPalette(
    id: 'hell',
    name: 'Hell',
    tagline: 'Für Tageslicht',
    brightness: Brightness.light,
    bg: Color(0xFFF2F4F7),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF6F7F9),
    surface3: Color(0xFFE7EBF0),
    border: Color(0xFFDDE2E9),
    line: Color(0xFFC8CFD8),
    text: Color(0xFF151A20),
    muted: Color(0xFF65707C),
    muted2: Color(0xFF3D4651),
    accent: Color(0xFF2563EB),
    accent2: Color(0xFF7C3AED),
    onAccent: Color(0xFFFFFFFF),
    dbl: Color(0xFF14A866),
    trp: Color(0xFFE86A10),
    miss: Color(0xFFE5484D),
    gold: Color(0xFFD99A00),
  ),
];

AppPalette paletteById(String? id) =>
    palettes.firstWhere((p) => p.id == id, orElse: () => palettes.first);

/// Aktuelle Farben. Werden beim Theme-Wechsel umgestellt und die ganze
/// Oberfläche neu gezeichnet (siehe [ThemeHost]).
class C {
  C._();
  static AppPalette p = palettes.first;

  /// Farbschwäche-Modus: zusätzlich Symbole für Double, Triple und Miss.
  static bool cb = false;

  static Color get bg => p.bg;
  static Color get surface => p.surface;
  static Color get surface2 => p.surface2;
  static Color get surface3 => p.surface3;
  static Color get border => p.border;
  static Color get line => p.line;
  static Color get text => p.text;
  static Color get muted => p.muted;
  static Color get muted2 => p.muted2;
  static Color get accent => p.accent;
  static Color get accent2 => p.accent2;
  static Color get onAccent => p.onAccent;
  static Color get dbl => p.dbl;
  static Color get trp => p.trp;
  static Color get miss => p.miss;

  /// Warnfarbe (Löschen, Bust, Verbindung weg).
  static Color get danger => p.miss;
  static Color get gold => p.gold;
  static bool get isLight => p.isLight;

  /// Halbtransparente Fläche für Overlays (Ergebnis, Dialoge).
  static Color get overlay => p.bg.withValues(alpha: 0.96);

  /// Dunkle Schrift auf den (hellen) Spielerfarben – themenunabhängig.
  static const ink = Color(0xFF10131A);

  /// Die vier Spielerfarben (bewusst kein Grün/Rot – die sind für Double/Triple).
  static const players = [
    Color(0xFF5AA9FF), // Blau
    Color(0xFFF5C84C), // Gelb
    Color(0xFFB48CFF), // Lila
    Color(0xFFFF8AD0), // Pink
    Color(0xFF3DD6C6), // Türkis
    Color(0xFFFF9F43), // Orange
    Color(0xFFB6E35A), // Limette
    Color(0xFFE3E8F2), // Silber
  ];
  static const playerColorNames = ['Blau', 'Gelb', 'Lila', 'Pink', 'Türkis', 'Orange', 'Limette', 'Silber'];

  /// Karten-Verlauf in der Akzentfarbe.
  static LinearGradient cardGradient([Color? tint, double strength = 0.10]) {
    final t = tint ?? accent;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color.alphaBlend(t.withValues(alpha: strength), surface), surface],
    );
  }

  static LinearGradient get accentGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [accent, Color.lerp(accent, accent2, 0.65)!],
      );
}

const tabular = [FontFeature.tabularFigures()];

/// Schrift für große Zahlen (Punktestände).
const numFont = 'BarlowCondensed';

ThemeData buildTheme(AppPalette p) {
  final dark = !p.isLight;
  final scheme = ColorScheme.fromSeed(
    seedColor: p.accent,
    brightness: p.brightness,
  ).copyWith(
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.accent2,
    surface: p.bg,
    onSurface: p.text,
    surfaceContainerHighest: p.surface3,
    surfaceContainerHigh: p.surface2,
    surfaceContainer: p.surface,
    surfaceContainerLow: p.surface,
    outline: p.line,
    outlineVariant: p.border,
    error: p.miss,
  );
  final base = ThemeData(
    brightness: p.brightness,
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    fontFamily: 'Barlow',
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: overlayStyle(p),
      titleTextStyle: TextStyle(
          fontFamily: 'Barlow', fontSize: 22, fontWeight: FontWeight.w800, color: p.text),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.accent.withValues(alpha: dark ? 0.22 : 0.16),
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? p.accent : p.muted)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontFamily: 'Barlow',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: s.contains(WidgetState.selected) ? p.text : p.muted)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.surface3,
      contentTextStyle: TextStyle(color: p.text, fontFamily: 'Barlow'),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(backgroundColor: p.surface),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.surface, surfaceTintColor: Colors.transparent),
    chipTheme: ChipThemeData(
      backgroundColor: p.surface2,
      selectedColor: p.accent.withValues(alpha: 0.22),
      side: BorderSide(color: p.line),
      labelStyle: TextStyle(color: p.text, fontWeight: FontWeight.w600, fontFamily: 'Barlow'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.onAccent : p.muted),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : p.surface3),
      trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : p.line),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.accent,
      inactiveTrackColor: p.surface3,
      thumbColor: p.accent,
      overlayColor: p.accent.withValues(alpha: 0.15),
    ),
    dividerTheme: DividerThemeData(color: p.surface3, space: 1, thickness: 1),
    textTheme: base.textTheme.apply(bodyColor: p.text, displayColor: p.text, fontFamily: 'Barlow'),
  );
}

SystemUiOverlayStyle overlayStyle(AppPalette p) => SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: p.isLight ? Brightness.dark : Brightness.light,
      statusBarBrightness: p.isLight ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: p.surface,
      systemNavigationBarIconBrightness: p.isLight ? Brightness.dark : Brightness.light,
    );

/// Hält das aktuelle Theme. Beim Wechsel wird die gesamte Oberfläche neu
/// aufgebaut, ohne die Navigation zu verlieren.
class ThemeHost {
  ThemeHost._();
  static final notifier = ValueNotifier<AppPalette>(palettes.first);

  /// Zählt Änderungen, die die ganze App neu zeichnen (Theme, Schriftgröße, Farbschwäche).
  static final tick = ValueNotifier<int>(0);

  /// Schriftgröße der App (1.0 normal, 1.15 groß).
  static double fontScale = 1.0;

  static void apply(AppPalette p, {BuildContext? context, bool colorblind = false}) {
    final eff = colorblind ? p.colorblind() : p;
    C.p = eff;
    C.cb = colorblind;
    notifier.value = eff;
    tick.value++;
    SystemChrome.setSystemUIOverlayStyle(overlayStyle(eff));
    if (context != null) rebuildAll(context);
  }

  /// Theme nach Einstellung: [themeId] 'auto' folgt dem Hell/Dunkel des Systems.
  static AppPalette resolve(String themeId, String nightId, Brightness system) {
    if (themeId == 'auto') return system == Brightness.light ? paletteById('hell') : paletteById(nightId);
    return paletteById(themeId);
  }
}

/// Zwingt alle Elemente unterhalb von [context]s Wurzel zum Neuaufbau
/// (nötig, weil die Farben in [C] statisch gelesen werden).
void rebuildAll(BuildContext context) {
  void walk(Element el) {
    el.markNeedsBuild();
    el.visitChildren(walk);
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) walk(root);
}

/// Gedrückt-Effekt: leichtes Einfedern + Ripple.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, required this.onTap, this.enabled = true});
  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => widget.enabled ? setState(() => _down = true) : null,
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.94 : 1,
        duration: const Duration(milliseconds: 80),
        child: widget.child,
      ),
    );
  }
}

/// Abgerundete Taste mit Ripple.
class Key3 extends StatelessWidget {
  const Key3({
    super.key,
    required this.child,
    required this.onTap,
    this.color,
    this.borderColor,
    this.gradient,
    this.radius = 14,
    this.enabled = true,
    this.semantics,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final Gradient? gradient;
  final double radius;
  final bool enabled;
  final String? semantics;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: borderColor ?? C.border),
    );
    return Semantics(
      button: true,
      label: semantics,
      enabled: enabled,
      excludeSemantics: semantics != null,
      child: PressScale(
        enabled: enabled,
        onTap: onTap,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.35,
          duration: const Duration(milliseconds: 150),
          child: Material(
            color: gradient == null ? (color ?? C.surface2) : Colors.transparent,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: gradient == null ? null : ShapeDecoration(gradient: gradient, shape: shape),
              child: InkWell(
                onTap: enabled ? onTap : null,
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Großer Haupt-Button im Akzent-Verlauf.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon = Icons.arrow_forward_rounded,
    this.height = 56,
    this.semantics,
  });
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final double height;
  final String? semantics;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: C.accent.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6)),
          ],
        ),
        child: Key3(
          semantics: semantics ?? label,
          onTap: onTap,
          enabled: onTap != null,
          gradient: C.accentGradient,
          borderColor: Colors.transparent,
          radius: 18,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800, color: C.onAccent, letterSpacing: 0.3)),
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 8),
                Icon(icon, color: C.onAccent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Karte mit leichtem Verlauf und feiner Kante.
class GlowCard extends StatelessWidget {
  const GlowCard({
    super.key,
    required this.child,
    this.tint,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 10),
    this.radius = 20,
    this.strength = 0.08,
    this.borderAlpha = 0.18,
  });
  final Widget child;
  final Color? tint;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final double radius;
  final double strength;
  final double borderAlpha;

  @override
  Widget build(BuildContext context) {
    final t = tint ?? C.accent;
    final br = BorderRadius.circular(radius);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        gradient: C.cardGradient(t, strength),
        borderRadius: br,
        border: Border.all(color: Color.alphaBlend(t.withValues(alpha: borderAlpha), C.border)),
        boxShadow: C.isLight
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 3))]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: br,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Abschnittsüberschrift in Großbuchstaben.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(4, 8, 4, 8)});
  final String text;
  final String? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(
          children: [
            Text(text.toUpperCase(),
                style: TextStyle(color: C.muted, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            const Spacer(),
            if (trailing != null) Text(trailing!, style: TextStyle(color: C.muted, fontSize: 13)),
          ],
        ),
      );
}

/// Zahl, die beim Ändern sanft hoch- bzw. runterzählt.
class AnimatedNumber extends StatelessWidget {
  const AnimatedNumber(this.value, {super.key, required this.style, this.duration = const Duration(milliseconds: 380)});
  final int value;
  final TextStyle style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text('${v.round()}', style: style),
    );
  }
}

/// Einheitlicher Stil für SegmentedButtons.
ButtonStyle segStyle() => SegmentedButton.styleFrom(
      selectedBackgroundColor: C.accent,
      selectedForegroundColor: C.onAccent,
      foregroundColor: C.muted2,
      side: BorderSide(color: C.line),
      textStyle: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Barlow'),
    );

/// Zahl mit − / + Tasten.
class NumberStepper extends StatelessWidget {
  const NumberStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 99,
    this.step = 1,
    this.onTapValue,
    this.sub,
  });
  final String label;
  final String? sub;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;
  final VoidCallback? onTapValue;

  Widget _btn(IconData icon, String tip, bool enabled, VoidCallback onTap) => IconButton(
        tooltip: tip,
        onPressed: enabled ? onTap : null,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          backgroundColor: C.surface3,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                if (sub != null) Text(sub!, style: TextStyle(fontSize: 12, color: C.muted)),
              ],
            ),
          ),
          _btn(Icons.remove_rounded, 'Weniger', value > min, () => onChanged((value - step).clamp(min, max))),
          GestureDetector(
            onTap: onTapValue,
            child: SizedBox(
              width: 60,
              child: Text('$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w800, fontFamily: numFont, fontFeatures: tabular)),
            ),
          ),
          _btn(Icons.add_rounded, 'Mehr', value < max, () => onChanged((value + step).clamp(min, max))),
        ],
      );
}

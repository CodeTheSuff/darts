import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Rahmen für einen App-Ausschnitt im Tutorial in fester Entwurfsbreite, nicht antippbar.
/// Das Tutorial skaliert ihn auf den verfügbaren Platz.
class TutFrame extends StatelessWidget {
  const TutFrame({super.key, required this.child, this.width = 360, this.height});
  final Widget child;
  final double width;

  /// Feste Höhe nur für Inhalte, die den Platz selbst füllen (Raster, Baum); sonst so hoch wie nötig.
  final double? height;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: C.bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: C.line),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 18)],
        ),
        clipBehavior: Clip.antiAlias,
        child: IgnorePointer(
          child: SizedBox(
            width: width,
            height: height,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: height == null
                  ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [child])
                  : child,
            ),
          ),
        ),
      );
}

/// Hebt einen Teil des Ausschnitts hervor (leuchtender Rahmen in Akzentfarbe).
class Spot extends StatelessWidget {
  const Spot({super.key, required this.child, this.on = true, this.radius = 14});
  final Widget child;
  final bool on;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (!on) return child;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius + 3),
        border: Border.all(color: C.accent, width: 3),
        boxShadow: [BoxShadow(color: C.accent.withValues(alpha: 0.55), blurRadius: 16, spreadRadius: 1)],
      ),
      padding: const EdgeInsets.all(2),
      child: child,
    );
  }
}

/// Eine Taste wie im Tastenblock.
class MockKey extends StatelessWidget {
  const MockKey(this.label, {super.key, this.tone, this.spot = false, this.filled = false, this.flex = 1, this.height = 40});
  final String label;
  final Color? tone;
  final bool spot;
  final bool filled;
  final int flex;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = tone;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(2.5),
        child: Spot(
          on: spot,
          radius: 10,
          child: Container(
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: filled && t != null
                  ? t
                  : t != null
                      ? Color.alphaBlend(t.withValues(alpha: 0.12), C.surface2)
                      : C.surface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t?.withValues(alpha: 0.5) ?? C.border),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: filled ? const Color(0xFF0B0E1A) : (t ?? C.text))),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kleine Karte im Stil der App.
class MockCard extends StatelessWidget {
  const MockCard({super.key, required this.child, this.tint, this.spot = false, this.padding = const EdgeInsets.all(10)});
  final Widget child;
  final Color? tint;
  final bool spot;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Spot(
        on: spot,
        radius: 14,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint != null ? Color.alphaBlend(tint!.withValues(alpha: 0.10), C.surface) : C.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: (tint ?? C.line).withValues(alpha: tint != null ? 0.45 : 1)),
          ),
          child: child,
        ),
      );
}

/// Zeile wie in den Einstellungen: Symbol, Titel, Untertitel, optional Schalter.
class MockSetting extends StatelessWidget {
  const MockSetting(this.icon, this.title, this.sub, {super.key, this.toggle, this.spot = false});
  final IconData icon;
  final String title;
  final String sub;
  final bool? toggle;
  final bool spot;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: MockCard(
          spot: spot,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(
            children: [
              Icon(icon, color: C.accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 11)),
                  ],
                ),
              ),
              if (toggle != null)
                Container(
                  width: 38,
                  height: 22,
                  padding: const EdgeInsets.all(3),
                  alignment: toggle! ? Alignment.centerRight : Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: toggle! ? C.accent : C.surface3,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      );
}

/// Kleiner Chip (z. B. Auswahl im Setup).
class MockChip extends StatelessWidget {
  const MockChip(this.label, {super.key, this.on = false, this.spot = false, this.color});
  final String label;
  final bool on;
  final bool spot;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? C.accent;
    return Spot(
      on: spot,
      radius: 99,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: on ? c.withValues(alpha: 0.2) : C.surface2,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: on ? c : C.line),
        ),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: on ? c : C.text)),
      ),
    );
  }
}

/// Spielerkarte mit Restpunkten (wie im Spielbildschirm).
class MockPlayer extends StatelessWidget {
  const MockPlayer(this.name, this.score, this.color, {super.key, this.active = false, this.sub = '', this.spot = false});
  final String name;
  final String score;
  final Color color;
  final bool active;
  final String sub;
  final bool spot;

  @override
  Widget build(BuildContext context) => MockCard(
        spot: spot,
        tint: active ? color : null,
        child: Row(
          children: [
            Container(width: 4, height: 44, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    if (active) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                        child: Text('AM WURF', style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ]),
                  if (sub.isNotEmpty) Text(sub, style: TextStyle(color: C.muted, fontSize: 11)),
                ],
              ),
            ),
            Text(score, style: TextStyle(fontFamily: numFont, fontSize: 40, fontWeight: FontWeight.w800, color: C.text)),
          ],
        ),
      );
}

/// Hinweis-Leiste (z. B. Checkout-Vorschlag).
class MockHint extends StatelessWidget {
  const MockHint(this.label, this.value, {super.key, this.spot = false, this.tone});
  final String label;
  final String value;
  final bool spot;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = tone ?? C.accent;
    return Spot(
      on: spot,
      radius: 12,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: t.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: TextStyle(color: t, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: C.text, fontSize: 15, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog-Ausschnitt (Titel, Text, Knöpfe).
class MockDialog extends StatelessWidget {
  const MockDialog(this.title, this.text, this.buttons, {super.key, this.icon});
  final String title;
  final String text;
  final List<String> buttons;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 300,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: C.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) Center(child: Icon(icon, size: 32, color: C.accent)),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(text, style: TextStyle(color: C.muted2, fontSize: 13, height: 1.3)),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.end,
                runSpacing: 6,
                children: [
                  for (final (i, b) in buttons.indexed)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: i == buttons.length - 1 ? C.accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(b,
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: i == buttons.length - 1 ? C.onAccent : C.accent)),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
}

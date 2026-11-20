import 'package:material_ui/material_ui.dart';

import '../data/sound.dart';

import '../games/engine.dart';
import 'theme.dart';

/// Eingabe pro Pfeil. Je nach Modus ([InputSpec]):
/// - full:    Double/Triple-Schalter (sonst Single), Zahlen 1–20, Bull, Miss, Undo
///            (optional fest auf Double oder Triple eingestellt)
/// - numbers: nur bestimmte Zahlen (z. B. Cricket 15–20 + Bull) mit Schaltern
/// - buttons: wenige große Treffer-Tasten + Miss (z. B. Around the Clock)
class Keypad extends StatefulWidget {
  const Keypad({
    super.key,
    required this.onDart,
    required this.onUndo,
    required this.canUndo,
    this.spec = const InputSpec.full(),
    this.color,
    this.enabled = true,
  });

  final void Function(int field, int mult) onDart;
  final VoidCallback onUndo;
  final bool canUndo;
  final InputSpec spec;
  final Color? color;
  final bool enabled;

  @override
  State<Keypad> createState() => _KeypadState();
}

/// Symbol für Double/Triple/Miss im Farbschwäche-Modus.
IconData? multIcon(int m) => switch (m) {
      2 => Icons.diamond_rounded,
      3 => Icons.change_history_rounded,
      0 => Icons.close_rounded,
      _ => null,
    };

class _KeypadState extends State<Keypad> {
  int _mult = 1;
  static const gap = 7.0;

  int get _effMult => widget.spec.lockedMult ?? _mult;

  void _toggle(int m) {
    Haptics.selection();
    setState(() => _mult = _mult == m ? 1 : m);
  }

  void _hit(int field, [int? mult]) {
    if (!widget.enabled) return;
    final m = field == 0 ? 1 : (mult ?? _effMult);
    if (field == 25 && m == 3) return;
    Haptics.light();
    setState(() => _mult = 1);
    widget.onDart(field, m);
  }

  // ---------------------------------------------------------------- Bausteine

  Widget _pad(Widget child, {int flex = 1}) => Expanded(
        flex: flex,
        child: Padding(padding: const EdgeInsets.all(gap / 2), child: child),
      );

  Widget _toggleBtn(String label, String sub, int m, Color color, Color dark) {
    final on = _mult == m;
    return Expanded(
      child: Key3(
        semantics: '$label${on ? ' aktiv' : ''}',
        onTap: () => _toggle(m),
        color: on ? color : C.surface,
        borderColor: on ? color : color.withValues(alpha: 0.4),
        radius: 16,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (C.cb) ...[
              Icon(multIcon(m), size: 18, color: on ? dark : color),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: on ? dark : color)),
            const SizedBox(width: 6),
            Text(sub,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: (on ? dark : color).withValues(alpha: 0.8))),
          ],
        ),
      ),
    );
  }

  Widget _toggles() => SizedBox(
        height: 52,
        child: Row(
          children: [
            _toggleBtn('Double', '×2', 2, C.dbl, const Color(0xFF06150D)),
            const SizedBox(width: 8),
            _toggleBtn('Triple', '×3', 3, C.trp, const Color(0xFF2A1203)),
          ],
        ),
      );

  Widget _titleBar(String text, Color tone) => Container(
        height: 44,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tone.withValues(alpha: 0.35)),
        ),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: tone, fontWeight: FontWeight.w800, fontSize: 15)),
      );

  ({Color bg, Color border, Color? tone, String prefix}) _style() {
    final m = _effMult;
    final tone = m == 2 ? C.dbl : m == 3 ? C.trp : null;
    return (
      bg: tone != null ? Color.alphaBlend(tone.withValues(alpha: 0.10), C.surface2) : C.surface2,
      border: tone != null ? tone.withValues(alpha: 0.35) : C.border,
      tone: tone,
      prefix: m == 2 ? 'D' : m == 3 ? 'T' : '',
    );
  }

  Widget _numKey(int n, {double fontSize = 22}) {
    final s = _style();
    final m = _effMult;
    final isBull = n == 25;
    return _pad(Key3(
      semantics: isBull
          ? (m == 2 ? 'Bullseye 50' : '25')
          : '${m == 2 ? 'Double ' : m == 3 ? 'Triple ' : ''}$n',
      enabled: !(isBull && m == 3),
      onTap: () => _hit(n),
      color: s.bg,
      borderColor: s.border,
      child: isBull
          ? Text(m == 2 ? 'Bull 50' : 'Bull 25',
              style: TextStyle(fontSize: fontSize * 0.75, fontWeight: FontWeight.w800))
          : Text.rich(
              TextSpan(children: [
                if (C.cb && multIcon(m) != null && m > 0)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(multIcon(m), size: fontSize * 0.5, color: s.tone),
                    ),
                  ),
                if (s.prefix.isNotEmpty)
                  TextSpan(
                      text: s.prefix,
                      style: TextStyle(fontSize: fontSize * 0.55, fontWeight: FontWeight.w800, color: s.tone)),
                TextSpan(text: '$n'),
              ]),
              style: TextStyle(
                  fontSize: fontSize, fontWeight: FontWeight.w700, color: C.text, fontFeatures: tabular),
            ),
    ));
  }

  /// Miss ist immer rot.
  Widget _missKey({int flex = 1}) => _pad(
        Key3(
          semantics: 'Miss',
          onTap: () => _hit(0),
          color: Color.alphaBlend(C.miss.withValues(alpha: 0.12), C.surface2),
          borderColor: C.miss.withValues(alpha: 0.6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (C.cb) ...[Icon(Icons.close_rounded, size: 18, color: C.miss), const SizedBox(width: 4)],
              Text('Miss', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: C.miss)),
            ],
          ),
        ),
        flex: flex,
      );

  Widget _undoKey() => _pad(Key3(
        semantics: 'Letzten Pfeil rückgängig machen',
        enabled: widget.canUndo,
        onTap: () {
          Haptics.medium();
          setState(() => _mult = 1);
          widget.onUndo();
        },
        color: C.surface3,
        borderColor: C.line,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.undo_rounded, size: 20, color: C.text),
            SizedBox(width: 6),
            Text('Undo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
      ));

  // ---------------------------------------------------------------- Layouts

  Widget _full() {
    final locked = widget.spec.lockedMult;
    return Column(
      children: [
        if (locked == null)
          _toggles()
        else
          _titleBar(widget.spec.title ?? (locked == 2 ? 'Nur Doubles' : 'Nur Triples'),
              locked == 2 ? C.dbl : C.trp),
        const SizedBox(height: gap / 2),
        Expanded(
          child: Column(
            children: [
              for (var row = 0; row < 4; row++)
                Expanded(
                  child: Row(children: [for (var col = 1; col <= 5; col++) _numKey(row * 5 + col)]),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 56,
          child: Row(
            children: [
              if (locked != 3) _numKey(25, fontSize: 21),
              _missKey(),
              _undoKey(),
            ],
          ),
        ),
      ],
    );
  }

  /// Feste Bull-Taste (25 oder 50) – unabhängig von Double/Triple.
  Widget _fixedBull(int mult, {double fontSize = 30}) => _pad(Key3(
        semantics: mult == 2 ? 'Bullseye 50' : '25',
        onTap: () => _hit(25, mult),
        color: mult == 2 ? Color.alphaBlend(C.dbl.withValues(alpha: 0.10), C.surface2) : C.surface2,
        borderColor: mult == 2 ? C.dbl.withValues(alpha: 0.35) : C.border,
        child: Text(mult == 2 ? 'Bull 50' : 'Bull 25',
            style: TextStyle(fontSize: fontSize * 0.75, fontWeight: FontWeight.w800)),
      ));

  Widget _numbers() {
    // Bull erscheint als zwei feste Tasten: Bull 25 und Bull 50 (Index 50 = Bull 50).
    final nums = [for (final n in widget.spec.numbers) ...(n == 25 ? const [25, 50] : [n])];
    final rows = <List<int>>[];
    for (var i = 0; i < nums.length; i += 4) {
      rows.add(nums.sublist(i, (i + 4).clamp(0, nums.length)));
    }
    return Column(
      children: [
        _toggles(),
        const SizedBox(height: gap / 2),
        Expanded(
          child: Column(
            children: [
              for (final r in rows)
                Expanded(
                  child: Row(children: [
                    for (final n in r)
                      n == 25
                          ? _fixedBull(1)
                          : n == 50
                              ? _fixedBull(2)
                              : _numKey(n, fontSize: 30),
                    for (var k = r.length; k < 4; k++) const Expanded(child: SizedBox()),
                  ]),
                ),
            ],
          ),
        ),
        SizedBox(height: 60, child: Row(children: [_missKey(flex: 2), _undoKey()])),
      ],
    );
  }

  Widget _quick(QuickButton b) {
    // Treffer-Tasten in Spielerfarbe (Killer: Farbe des Ziel-Spielers).
    // Bei mehreren Tasten: Single hell, Double mittel, Triple kräftig.
    final tone = b.color != null ? Color(b.color!) : (widget.color ?? C.text);
    final multi = widget.spec.buttons.where((x) => x.field == b.field).length > 1 && b.color == null;
    final level = multi ? b.mult.clamp(1, 3) : 2;
    final bgA = const [0.0, 0.08, 0.17, 0.30][level];
    final brA = const [0.0, 0.35, 0.65, 0.95][level];
    return _pad(Key3(
      semantics: '${b.label}${b.sub != null ? ', ${b.sub}' : ''}',
      onTap: () => _hit(b.field, b.mult),
      color: Color.alphaBlend(tone.withValues(alpha: bgA), C.surface2),
      borderColor: tone.withValues(alpha: brA),
      radius: 20,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(b.label,
                  style: TextStyle(
                      fontSize: 44, fontWeight: FontWeight.w800, color: C.text, fontFeatures: tabular)),
              if (b.sub != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (C.cb && b.mult > 1) ...[
                      Icon(multIcon(b.mult), size: 14, color: tone),
                      const SizedBox(width: 4),
                    ],
                    Text(b.sub!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: tone)),
                  ],
                ),
            ],
          ),
        ),
      ),
    ));
  }

  Widget _buttons() {
    final bs = widget.spec.buttons;
    final perRow = bs.length == 4 ? 2 : bs.length.clamp(1, 3);
    final rows = <List<QuickButton>>[];
    for (var i = 0; i < bs.length; i += perRow) {
      rows.add(bs.sublist(i, (i + perRow).clamp(0, bs.length)));
    }
    return Column(
      children: [
        if (widget.spec.title != null) ...[
          _titleBar(widget.spec.title!, widget.color ?? C.text),
          const SizedBox(height: gap / 2),
        ],
        Expanded(
          flex: 3,
          child: Column(
            children: [
              for (final r in rows) Expanded(child: Row(children: [for (final b in r) _quick(b)])),
            ],
          ),
        ),
        Expanded(
          flex: rows.length == 1 ? 2 : 1,
          child: Row(children: [_missKey(flex: 2), _undoKey()]),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => switch (widget.spec.kind) {
        InputKind.full => _full(),
        InputKind.numbers => _numbers(),
        InputKind.buttons => _buttons(),
      };
}

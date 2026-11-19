import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../data/sound.dart';
import '../models/player.dart';
import 'theme.dart';

/// Ausbullen mit kompletter Reihenfolge: Die Spieler werden in der Reihenfolge
/// angetippt, in der sie am nächsten am Bull waren (1., 2., 3. …). Der Letzte
/// bekommt seinen Platz automatisch. Liefert die Indizes in Wurfreihenfolge
/// oder `null` bei Abbruch.
Future<List<int>?> showBullOffOrder(BuildContext context, List<GamePlayer> players) {
  return showModalBottomSheet<List<int>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => _BullOffSheet(players: players),
  );
}

/// Nur der Startspieler (z. B. Turnier mit zwei Spielern).
Future<int?> showBullOff(BuildContext context, List<GamePlayer> players) async {
  final order = await showBullOffOrder(context, players);
  return order?.first;
}

/// Reihenfolge nach Antippen: [picked] sind die bisher gewählten Indizes; ist nur noch
/// einer übrig, kommt er automatisch dazu.
List<int> completeOrder(List<int> picked, int n) {
  final rest = [for (var i = 0; i < n; i++) if (!picked.contains(i)) i];
  return rest.length == 1 ? [...picked, rest.single] : List.of(picked);
}

class _BullOffSheet extends StatefulWidget {
  const _BullOffSheet({required this.players});
  final List<GamePlayer> players;

  @override
  State<_BullOffSheet> createState() => _BullOffSheetState();
}

class _BullOffSheetState extends State<_BullOffSheet> {
  final _order = <int>[];
  bool _closing = false;

  List<GamePlayer> get _p => widget.players;

  void _tap(int i) {
    if (_closing) return;
    Haptics.selection();
    setState(() {
      final at = _order.indexOf(i);
      if (at >= 0) {
        // erneut getippt: diesen und alle späteren Plätze zurücknehmen
        _order.removeRange(at, _order.length);
      } else {
        _order
          ..add(i)
          ..replaceRange(0, _order.length, completeOrder(_order, _p.length));
      }
    });
    if (_order.length == _p.length) _finish();
  }

  void _finish() {
    _closing = true;
    Haptics.medium();
    if (_p.length == 2) {
      Navigator.pop(context, List.of(_order));
      return;
    }
    // ab 3 Spielern kurz zeigen, wer welchen Platz hat
    Timer(const Duration(milliseconds: 450), () {
      if (mounted) Navigator.pop(context, List.of(_order));
    });
  }

  void _draw() {
    final o = [for (var i = 0; i < _p.length; i++) i]..shuffle();
    setState(() => _order
      ..clear()
      ..addAll(o));
    _finish();
  }

  @override
  Widget build(BuildContext context) {
    final next = _order.length + 1;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: C.accentGradient),
                  child: Icon(Icons.adjust_rounded, color: C.onAccent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ausbullen', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      Text(
                        _order.length == _p.length
                            ? 'Reihenfolge steht'
                            : _p.length == 2
                                ? 'Jeder wirft einen Dart aufs Bull. Wer war am nächsten dran?'
                                : 'Tippe die Spieler nach Nähe zum Bull an – jetzt Platz $next.',
                        style: TextStyle(color: C.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var i = 0; i < _p.length; i++) _tile(i),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (_order.isNotEmpty && !_closing)
                  TextButton.icon(
                    onPressed: () => setState(_order.clear),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Zurücksetzen', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _closing ? null : _draw,
                  icon: const Icon(Icons.casino_rounded),
                  label: const Text('Auslosen', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(int i) {
    final p = _p[i];
    final col = Color(p.color);
    final rank = _order.indexOf(i);
    final ranked = rank >= 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 58,
        child: Key3(
          semantics: ranked
              ? '${p.name}, Platz ${rank + 1}'
              : _p.length == 2
                  ? '${p.name} beginnt'
                  : '${p.name} als Nächster',
          onTap: () => _tap(i),
          color: Color.alphaBlend(col.withValues(alpha: ranked ? 0.28 : 0.10), C.surface2),
          borderColor: col.withValues(alpha: ranked ? 1 : 0.5),
          radius: 18,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: col,
                  child: Text(p.name.characters.first.toUpperCase(),
                      style: const TextStyle(color: C.ink, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(p.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                if (ranked)
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: col, shape: BoxShape.circle),
                    child: Text('${rank + 1}.',
                        style: const TextStyle(
                            fontFamily: numFont, fontSize: 20, fontWeight: FontWeight.w800, color: C.ink)),
                  )
                else
                  Text(_p.length == 2 ? 'beginnt' : 'Platz ${_order.length + 1}',
                      style: TextStyle(color: C.muted, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

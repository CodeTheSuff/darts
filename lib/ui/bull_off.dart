import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../data/sound.dart';
import '../models/player.dart';
import 'theme.dart';

/// Ausbullen: Wer am nächsten am Bull ist, beginnt. Liefert den Index des
/// Startspielers oder `null` bei Abbruch.
Future<int?> showBullOff(BuildContext context, List<GamePlayer> players) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => SafeArea(
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
                      Text('Jeder wirft einen Dart aufs Bull. Wer war am nächsten dran?',
                          style: TextStyle(color: C.muted, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < players.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  height: 58,
                  child: Key3(
                    semantics: '${players[i].name} beginnt',
                    onTap: () {
                      Haptics.medium();
                      Navigator.pop(ctx, i);
                    },
                    color: Color.alphaBlend(Color(players[i].color).withValues(alpha: 0.12), C.surface2),
                    borderColor: Color(players[i].color).withValues(alpha: 0.6),
                    radius: 18,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 15,
                            backgroundColor: Color(players[i].color),
                            child: Text(players[i].name.characters.first.toUpperCase(),
                                style: const TextStyle(color: C.ink, fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(players[i].name,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                          ),
                          Text('beginnt', style: TextStyle(color: C.muted, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx, Random().nextInt(players.length)),
              icon: const Icon(Icons.casino_rounded),
              label: const Text('Auslosen', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    ),
  );
}

import 'package:material_ui/material_ui.dart';

import '../net/link.dart';
import 'link_screen.dart';
import 'theme.dart';

/// Verbindungs-Symbol oben im Spiel. Zeigt, ob und mit wie vielen Geräten gekoppelt ist;
/// antippen öffnet „Geräte verbinden“ als Fenster über dem Spiel – dort lässt sich auch
/// mitten im Spiel ein Raum eröffnen. Neue Geräte steigen direkt ins laufende Spiel ein.
class LinkBadge extends StatelessWidget {
  const LinkBadge({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Link.I,
        builder: (context, _) {
          final l = Link.I;
          final linked = l.role != LinkRole.none;
          final ok = l.isConnected;
          final col = !linked ? C.muted : (ok ? C.dbl : C.danger);
          final tip = !linked
              ? 'Geräte verbinden'
              : ok
                  ? 'Gekoppelt · ${l.peerCount + 1} Geräte'
                  : (l.status.isEmpty ? 'Nicht verbunden' : l.status);
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Tooltip(
              message: tip,
              child: Material(
                key: const ValueKey('link-badge'),
                color: col.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => showLinkSheet(context),
                  child: Container(
                    height: 36,
                    constraints: const BoxConstraints(minWidth: 40),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          !linked
                              ? Icons.add_link_rounded
                              : ok
                                  ? Icons.wifi_tethering_rounded
                                  : Icons.wifi_tethering_off_rounded,
                          size: 18,
                          color: col,
                        ),
                        if (linked) ...[
                          const SizedBox(width: 4),
                          Text(
                            '${ok ? l.peerCount + 1 : '!'}',
                            style: TextStyle(fontWeight: FontWeight.w800, color: col),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

/// „Geräte verbinden“ als Fenster über dem aktuellen Bildschirm (z. B. mitten im Spiel).
Future<void> showLinkSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: const LinkScreen(sheet: true),
        ),
      ),
    );

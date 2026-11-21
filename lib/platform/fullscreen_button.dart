import 'package:material_ui/material_ui.dart';

import 'platform_env.dart';

/// Vollbild-Taste für den Anzeige-Modus im Browser (Fullscreen-API).
/// Wo es die API nicht gibt (iPhone, Android-APK), wird nichts angezeigt –
/// auf dem iPhone ist die vom Home-Bildschirm gestartete App ohnehin randlos.
class FullscreenButton extends StatefulWidget {
  const FullscreenButton({super.key, this.color});

  final Color? color;

  @override
  State<FullscreenButton> createState() => _FullscreenButtonState();
}

class _FullscreenButtonState extends State<FullscreenButton> {
  @override
  Widget build(BuildContext context) {
    final env = Plat.I;
    if (!env.isWeb || !env.fullscreenSupported) return const SizedBox.shrink();
    final on = env.isFullscreen;
    return IconButton(
      tooltip: on ? 'Vollbild beenden' : 'Vollbild',
      icon: Icon(on ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, color: widget.color),
      onPressed: () async {
        await env.setFullscreen(!on);
        if (mounted) setState(() {});
      },
    );
  }
}

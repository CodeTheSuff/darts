import 'package:material_ui/material_ui.dart';

import '../data/sound.dart';
import 'theme.dart';

/// Ein Schritt der Einführung: hervorgehobene Stelle + kurzer Text.
class CoachStep {
  const CoachStep({required this.target, required this.title, required this.text, this.icon, this.actionLabel, this.onAction});

  /// Liefert die hervorzuhebende Fläche in globalen Koordinaten (oder null).
  final Rect? Function() target;
  final String title;
  final String text;
  final IconData? icon;

  /// Zusätzlicher Knopf (z. B. „Jetzt ansehen“); daneben „Später“ beendet nur den Rundgang.
  final String? actionLabel;
  final VoidCallback? onAction;
}

/// Rect eines Widgets mit [key] in globalen Koordinaten.
Rect? rectOf(GlobalKey key) {
  final box = key.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Abgedunkelte Fläche mit Loch über der aktuellen Stelle, Sprechblase mit Text.
class CoachOverlay extends StatefulWidget {
  const CoachOverlay({super.key, required this.steps, required this.onDone});
  final List<CoachStep> steps;
  final VoidCallback onDone;

  @override
  State<CoachOverlay> createState() => _CoachOverlayState();
}

class _CoachOverlayState extends State<CoachOverlay> {
  int _i = 0;
  Rect? _hole;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  /// Position erst nach dem Layout bestimmen (nie während des Aufbaus).
  void _measure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final r = widget.steps[_i].target()?.inflate(6);
      if (r != _hole) setState(() => _hole = r);
    });
  }

  void _next() {
    Haptics.selection();
    if (_i >= widget.steps.length - 1) {
      widget.onDone();
    } else {
      setState(() => _i++);
      _measure();
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_i];
    final size = MediaQuery.sizeOf(context);
    final hole = _hole;
    final last = _i == widget.steps.length - 1;
    final below = hole == null || hole.center.dy < size.height * 0.55;

    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: C.accent.withValues(alpha: 0.6)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (step.icon != null) ...[Icon(step.icon, color: C.accent, size: 22), const SizedBox(width: 8)],
              Expanded(
                child: Text(step.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              Text('${_i + 1}/${widget.steps.length}', style: TextStyle(color: C.muted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          Text(step.text, style: TextStyle(color: C.muted2, height: 1.35)),
          const SizedBox(height: 8),
          Row(
            children: [
              if (!last || step.actionLabel != null)
                TextButton(
                  onPressed: widget.onDone,
                  child: Text(last ? 'Später' : 'Überspringen', style: TextStyle(color: C.muted)),
                ),
              const Spacer(),
              FilledButton(
                onPressed: last && step.onAction != null
                    ? () {
                        widget.onDone();
                        step.onAction!();
                      }
                    : _next,
                style: FilledButton.styleFrom(backgroundColor: C.accent, foregroundColor: C.onAccent),
                child: Text(last ? (step.actionLabel ?? 'Los geht’s') : 'Weiter',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ],
      ),
    );

    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _next,
          child: Stack(
            children: [
              Positioned.fill(
                child: hole == null
                    ? CustomPaint(painter: _ScrimPainter(null, C.accent))
                    : TweenAnimationBuilder<Rect?>(
                        tween: RectTween(end: hole),
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        builder: (_, r, _) => CustomPaint(painter: _ScrimPainter(r, C.accent)),
                      ),
              ),
              Positioned(
                left: 16,
                right: 16,
                top: below ? (hole?.bottom ?? size.height * 0.3) + 14 : null,
                bottom: below ? null : size.height - hole.top + 14,
                child: Center(child: bubble),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  _ScrimPainter(this.hole, this.accent);
  final Rect? hole;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final h = hole;
    final scrim = Paint()..color = const Color(0xCC05070D);
    if (h == null) {
      canvas.drawPath(full, scrim);
      return;
    }
    final rr = RRect.fromRectAndRadius(h, const Radius.circular(18));
    canvas.drawPath(Path.combine(PathOperation.difference, full, Path()..addRRect(rr)), scrim);
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = accent
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4),
    );
  }

  @override
  bool shouldRepaint(covariant _ScrimPainter old) => old.hole != hole;
}

import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../data/sound.dart';
import '../data/storage.dart';
import '../games/engine.dart';
import '../models/dart.dart';
import 'dartboard.dart';
import 'theme.dart';

enum CelebrationKind { ton, ton40, max180, highFinish, legWon, match }

CelebrationKind kindOf(Celebration c) => switch (c) {
      Celebration.ton => CelebrationKind.ton,
      Celebration.ton40 => CelebrationKind.ton40,
      Celebration.max180 => CelebrationKind.max180,
      Celebration.highFinish => CelebrationKind.highFinish,
      Celebration.legWon => CelebrationKind.legWon,
    };

/// Jubel-Ton zur Animation (null = keiner, weil die eigenen Ansagen ihn ersetzen).
String? celebrationSound(CelebrationKind k) {
  if (Store.announce &&
      (k == CelebrationKind.ton ||
          k == CelebrationKind.ton40 ||
          k == CelebrationKind.max180 ||
          k == CelebrationKind.match)) {
    return null;
  }
  return _cheer(k);
}

String _cheer(CelebrationKind k) => switch (k) {
      CelebrationKind.ton => 'ton',
      CelebrationKind.ton40 => 'ton40',
      CelebrationKind.max180 => 'max180',
      CelebrationKind.highFinish => 'finish',
      CelebrationKind.legWon => 'leg',
      CelebrationKind.match => 'win',
    };

class _Burst {
  _Burst(this.t0, this.origin, this.count, this.speed, this.colors, this.seed,
      {this.ring = false, this.rocket = false, this.launchX});
  final double t0;
  final Offset origin; // 0..1
  final int count;
  final double speed;
  final List<Color> colors;
  final int seed;
  final bool ring;

  /// Feuerwerksrakete: steigt vor [t0] vom unteren Rand auf und explodiert bei [origin].
  final bool rocket;
  final double? launchX;

  /// Steigzeit einer Rakete in Sekunden.
  static const climb = 0.55;
}

class _Particle {
  _Particle(this.dir, this.speed, this.size, this.color, this.life, this.streak);
  final Offset dir;
  final double speed;
  final double size;
  final Color color;
  final double life;
  final bool streak;
}

/// Große Belohnungs-Animation. Antippen überspringt.
class CelebrationOverlay extends StatefulWidget {
  const CelebrationOverlay({
    super.key,
    required this.kind,
    required this.name,
    required this.color,
    required this.darts,
    required this.onDone,
    this.value,
    this.label,
  });

  final CelebrationKind kind;
  final String name;
  final Color color;
  final List<Dart> darts;
  final int? value;
  final String? label;
  final VoidCallback onDone;

  @override
  State<CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<CelebrationOverlay> with SingleTickerProviderStateMixin {
  late final double duration = switch (widget.kind) {
    CelebrationKind.ton => 3.6,
    CelebrationKind.ton40 => 4.1,
    CelebrationKind.max180 => 7.4,
    CelebrationKind.highFinish => 4.3,
    CelebrationKind.legWon => 3.1,
    CelebrationKind.match => 4.4,
  };

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (duration * 1000).round()),
  );

  late final List<_Burst> _bursts = _makeBursts();
  late final Map<_Burst, List<_Particle>> _particles = {
    for (final b in _bursts) b: _makeParticles(b),
  };

  bool _done = false;

  @override
  void initState() {
    super.initState();
    final snd = celebrationSound(widget.kind);
    if (snd != null) Sound.play(snd);
    _c.forward().whenComplete(_finish);
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  List<_Burst> _makeBursts() {
    final col = widget.color;
    final rnd = Random(widget.kind.index * 31 + (widget.value ?? 0));
    const board = Offset(0.5, 0.47);
    switch (widget.kind) {
      case CelebrationKind.ton:
        return [
          _Burst(0.35, board, 70, 1.0, [col, Colors.white], 1),
          _Burst(0.35, board, 0, 1.0, [col], 2, ring: true),
        ];
      case CelebrationKind.ton40:
        return [
          _Burst(0.30, board, 90, 1.2, [col, Colors.white, C.gold], 1),
          _Burst(0.30, board, 0, 1.2, [col], 2, ring: true),
          _Burst(0.75, const Offset(0.25, 0.3), 50, 0.8, [col, Colors.white], 3),
          _Burst(0.95, const Offset(0.75, 0.32), 50, 0.8, [C.gold, Colors.white], 4),
        ];
      case CelebrationKind.max180:
        final list = <_Burst>[
          _Burst(0.30, board, 140, 1.5, [C.gold, Colors.white, col], 1),
          _Burst(0.30, board, 0, 1.6, [C.gold], 2, ring: true),
          _Burst(0.55, board, 0, 1.3, [col], 3, ring: true),
        ];
        // Großes Feuerwerk: Raketen in Wellen über die ganze Dauer
        const palettes = [
          [Color(0xFFFFD166), Colors.white],
          [Color(0xFFFF5C8A), Color(0xFFFFC2D4)],
          [Color(0xFF5AA9FF), Colors.white],
          [Color(0xFF7CFFB2), Color(0xFFE8FFF2)],
          [Color(0xFFB48CFF), Color(0xFFFFD166)],
          [Color(0xFFFF9F43), Color(0xFFFFE0B8)],
        ];
        for (var i = 0; i < 16; i++) {
          final x = 0.12 + rnd.nextDouble() * 0.76;
          // abwechselnd über und unter der Scheibe, damit das Feuerwerk frei sichtbar ist
          final y = i.isEven ? 0.06 + rnd.nextDouble() * 0.14 : 0.74 + rnd.nextDouble() * 0.14;
          list.add(_Burst(
            0.9 + i * 0.36 + rnd.nextDouble() * 0.2,
            Offset(x, y),
            110 + rnd.nextInt(50),
            1.25 + rnd.nextDouble() * 0.45,
            palettes[i % palettes.length],
            40 + i,
            rocket: true,
            launchX: x + (rnd.nextDouble() - 0.5) * 0.12,
          ));
        }
        for (var i = 0; i < 9; i++) {
          list.add(_Burst(
            0.7 + i * 0.32 + rnd.nextDouble() * 0.15,
            Offset(0.15 + rnd.nextDouble() * 0.7, 0.12 + rnd.nextDouble() * 0.5),
            60,
            0.8 + rnd.nextDouble() * 0.4,
            [
              [C.gold, Colors.white],
              [col, Colors.white],
              [const Color(0xFFFF8A5B), C.gold],
              [C.players[(i + 1) % 4], Colors.white],
            ][i % 4],
            10 + i,
          ));
        }
        return list;
      case CelebrationKind.highFinish:
        return [
          _Burst(0.35, board, 100, 1.2, [C.gold, Colors.white, col], 1),
          _Burst(0.35, board, 0, 1.3, [C.gold], 2, ring: true),
          _Burst(1.1, const Offset(0.3, 0.25), 55, 0.8, [C.gold, Colors.white], 3),
          _Burst(1.4, const Offset(0.7, 0.28), 55, 0.8, [col, C.gold], 4),
        ];
      case CelebrationKind.legWon:
        return [
          _Burst(0.3, board, 55, 0.9, [col, Colors.white], 1),
        ];
      case CelebrationKind.match:
        return [
          for (var i = 0; i < 6; i++)
            _Burst(0.2 + i * 0.35, Offset(0.2 + (i % 3) * 0.3, 0.2 + (i % 2) * 0.25), 70, 1.0,
                [col, C.gold, Colors.white, C.players[(i + 2) % 4]], i + 1),
        ];
    }
  }

  List<_Particle> _makeParticles(_Burst b) {
    final rnd = Random(b.seed * 97 + widget.kind.index);
    return List.generate(b.count, (_) {
      final a = rnd.nextDouble() * 2 * pi;
      return _Particle(
        Offset(cos(a), sin(a)),
        b.speed * (b.rocket ? 0.55 + rnd.nextDouble() * 0.5 : 0.35 + rnd.nextDouble() * 0.9),
        b.rocket ? 2.4 + rnd.nextDouble() * 2.8 : 2 + rnd.nextDouble() * 3.5,
        b.colors[rnd.nextInt(b.colors.length)],
        b.rocket ? 1.3 + rnd.nextDouble() * 0.9 : 0.9 + rnd.nextDouble() * 0.9,
        b.rocket ? rnd.nextDouble() < 0.7 : rnd.nextDouble() < 0.45,
      );
    });
  }

  String get _label {
    if (widget.label != null) return widget.label!;
    return switch (widget.kind) {
      CelebrationKind.ton => 'TON!',
      CelebrationKind.ton40 => 'TON 40!',
      CelebrationKind.max180 => 'ONE HUNDRED AND EIGHTY',
      CelebrationKind.highFinish => 'HIGH FINISH',
      CelebrationKind.legWon => 'LEG GEWONNEN',
      CelebrationKind.match => 'MATCH GEWONNEN',
    };
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value * duration; // Sekunden
          final fadeIn = (t / 0.25).clamp(0.0, 1.0);
          final fadeOut = ((duration - t) / 0.4).clamp(0.0, 1.0);
          final vis = fadeIn * fadeOut;
          final pop = Curves.elasticOut.transform(((t - 0.05) / 0.9).clamp(0.0, 1.0));
          final is180 = widget.kind == CelebrationKind.max180;
          final shakeAmp = is180 ? 10.0 * (1 - ((t - 0.3) / 0.8).clamp(0.0, 1.0)) * (t > 0.3 ? 1 : 0) : 0.0;
          final shake = Offset(sin(t * 63) * shakeAmp, cos(t * 51) * shakeAmp);
          final size = MediaQuery.sizeOf(context);
          final boardSize = min(size.width * 0.74, 320.0);
          final accent = switch (widget.kind) {
            CelebrationKind.max180 || CelebrationKind.highFinish => C.gold,
            _ => widget.color,
          };

          return Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: vis,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        accent.withValues(alpha: 0.28),
                        const Color(0xF20A0B0D),
                      ],
                      radius: 0.9,
                    ),
                  ),
                ),
              ),
              Opacity(
                opacity: fadeOut,
                child: CustomPaint(
                  painter: _ParticlePainter(_bursts, _particles, t),
                ),
              ),
              Transform.translate(
                offset: shake,
                child: Opacity(
                  opacity: vis,
                  child: SafeArea(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Transform.scale(
                            scale: 0.6 + 0.4 * pop,
                            child: _GlowText(
                              _label,
                              color: accent,
                              size: is180 ? 22 : 28,
                              spacing: is180 ? 3 : 4,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Transform.rotate(
                            angle: (1 - pop) * -0.5,
                            child: Transform.scale(
                              scale: 0.5 + 0.5 * pop,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: accent.withValues(alpha: 0.45),
                                      blurRadius: 60,
                                      spreadRadius: 6,
                                    ),
                                  ],
                                ),
                                child: Dartboard(size: boardSize, darts: widget.darts, color: widget.color),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          if (widget.value != null)
                            Transform.scale(
                              scale: 0.4 + 0.6 * Curves.elasticOut.transform(((t - 0.25) / 0.9).clamp(0.0, 1.0)),
                              child: _GlowText(
                                '${widget.value}',
                                color: is180 ? C.gold : Colors.white,
                                family: numFont,
                                size: is180 ? 96 : 76,
                                spacing: -2,
                                weight: FontWeight.w800,
                              ),
                            ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 8),
                              Text(widget.name,
                                  style: const TextStyle(
                                      fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                            ],
                          ),
                          const SizedBox(height: 28),
                          Text('Tippen zum Fortfahren',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GlowText extends StatelessWidget {
  const _GlowText(this.text,
      {required this.color, required this.size, this.spacing = 0, this.weight = FontWeight.w900, this.family});
  final String text;
  final String? family;
  final Color color;
  final double size;
  final double spacing;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontFamily: family,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: spacing,
          height: 1,
          fontFeatures: tabular,
          shadows: [
            Shadow(color: color.withValues(alpha: 0.8), blurRadius: 24),
            Shadow(color: color.withValues(alpha: 0.5), blurRadius: 48),
          ],
        ),
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.bursts, this.particles, this.t);
  final List<_Burst> bursts;
  final Map<_Burst, List<_Particle>> particles;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide;
    for (final b in bursts) {
      final dt = t - b.t0;
      final o = Offset(b.origin.dx * size.width, b.origin.dy * size.height);
      if (b.rocket && dt < 0) {
        // Aufsteigende Rakete mit leuchtendem Schweif
        if (dt < -_Burst.climb) continue;
        final k = Curves.easeOut.transform(1 + dt / _Burst.climb);
        final start = Offset((b.launchX ?? b.origin.dx) * size.width, size.height * 1.02);
        final pos = Offset.lerp(start, o, k)!;
        final tail = Offset.lerp(start, o, (k - 0.12).clamp(0.0, 1.0))!;
        canvas.drawLine(
          tail,
          pos,
          Paint()
            ..shader = LinearGradient(colors: [b.colors.first.withValues(alpha: 0), b.colors.last])
                .createShader(Rect.fromPoints(tail, pos))
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawCircle(pos, 3.5, Paint()..color = Colors.white);
        continue;
      }
      if (dt < 0) continue;
      if (b.rocket && dt < 0.18) {
        // kurzer Lichtblitz bei der Explosion
        final f = 1 - dt / 0.18;
        canvas.drawCircle(
          o,
          unit * 0.09 * (1 + dt * 3),
          Paint()
            ..color = b.colors.last.withValues(alpha: 0.55 * f)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
        );
      }
      if (b.ring) {
        if (dt > 0.8) continue;
        final k = dt / 0.8;
        canvas.drawCircle(
          o,
          unit * 0.08 + unit * 0.6 * b.speed * Curves.easeOut.transform(k),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 10 * (1 - k) + 1
            ..color = b.colors.first.withValues(alpha: 0.7 * (1 - k))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        continue;
      }
      for (final p in particles[b]!) {
        if (dt > p.life) continue;
        final k = dt / p.life;
        // Abbremsen durch Luftwiderstand + Schwerkraft
        const drag = 2.6;
        final dist = unit * 0.55 * p.speed * (1 - exp(-drag * dt)) / drag * 2.2;
        final fall = unit * 0.18 * dt * dt;
        final pos = o + p.dir * dist + Offset(0, fall);
        var alpha = (1 - k) * (1 - k);
        // Feuerwerksfunken glitzern zum Ende hin
        if (b.rocket && k > 0.45) alpha *= 0.55 + 0.45 * sin(dt * 38 + p.size * 7).abs();
        final paint = Paint()..color = p.color.withValues(alpha: alpha);
        if (p.streak) {
          final vel = p.dir * (unit * 0.55 * p.speed * exp(-drag * dt) * 0.05) + Offset(0, unit * 0.36 * dt * 0.05);
          canvas.drawLine(
            pos,
            pos - vel * 2,
            paint
              ..strokeWidth = p.size * 0.7
              ..strokeCap = StrokeCap.round,
          );
        } else {
          canvas.drawCircle(
              pos,
              p.size * 2.2 * (1 - k * 0.5),
              Paint()
                ..color = p.color.withValues(alpha: alpha * 0.35)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
          canvas.drawCircle(pos, p.size * (1 - k * 0.5), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.t != t;
}

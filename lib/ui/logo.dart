import 'package:material_ui/material_ui.dart';

/// App-Logo (Pfeil mit Lila-Pink-Orange-Verlauf) als abgerundetes weißes Quadrat.
/// Quelle: darts_logo_paket/darts_icon_1024.png, aufbereitet von screens_test/icon_test.dart.
class DartsLogo extends StatelessWidget {
  const DartsLogo({super.key, this.size = 32, this.radius});
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius ?? size * 0.26),
        child: Image.asset(
          'assets/logo/logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          semanticLabel: 'Darts',
        ),
      );
}

/// Nur der Pfeil, freigestellt (z. B. als Wasserzeichen).
class DartsMark extends StatelessWidget {
  const DartsMark({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/logo/mark.png', width: size, height: size, filterQuality: FilterQuality.medium);
}

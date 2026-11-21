import 'dart:math';

/// Ein einzelner geworfener Pfeil.
///
/// [field]: 0 = Miss, 1–20, 25 = Bull-Bereich.
/// [mult]: 1 = Single, 2 = Double (bei 25 also Bullseye 50), 3 = Triple.
/// Die Jitter-Werte bestimmen nur, wo der Pfeil auf der gezeichneten
/// Scheibe steckt. Sie werden beim Wurf zufällig gesetzt und mitgespeichert,
/// damit der Pfeil nach einem Neuaufbau (z. B. Undo) an derselben Stelle bleibt.
class Dart {
  final int field;
  final int mult;
  final double jitterA; // -1..1  (Winkelabweichung)
  final double jitterR; // 0..1   (Position im Ring)
  final double tilt; // Grad, Neigung des Pfeils
  final bool inner; // Single: inneres statt äußeres Single-Feld

  const Dart(
    this.field,
    this.mult, {
    this.jitterA = 0,
    this.jitterR = 0.5,
    this.tilt = 25,
    this.inner = false,
  });

  factory Dart.thrown(int field, int mult, [Random? rng]) {
    final r = rng ?? Random();
    final m = field == 0 ? 1 : mult;
    return Dart(
      field,
      m,
      jitterA: r.nextDouble() * 2 - 1,
      jitterR: r.nextDouble(),
      tilt: 16 + r.nextDouble() * 22,
      inner: r.nextDouble() < 0.4,
    );
  }

  /// Steuer-Markierung in der Wurf-Liste (kein echter Pfeil): Single Out an/aus.
  static const singleOutOn = Dart(-1, 1);
  static const singleOutOff = Dart(-1, 0);

  /// Nach dem Sieg: die übrigen Spieler spielen um den nächsten Platz weiter.
  static const playOn = Dart(-2, 1);

  /// Checkout-Training/Catch 40: Wer noch wirft, wird übersprungen – nächste Zahl für alle.
  static const skipRound = Dart(-3, 1);

  bool get isControl => field < 0;

  /// Kompakte Zahl fürs Archiv: Feld * 4 + Multiplikator, Markierungen negativ.
  int get code => isControl ? (field == -3 ? -4 : field == -2 ? -3 : -1 - mult) : field * 4 + mult;

  factory Dart.fromCode(int c) =>
      c == -4 ? skipRound : c == -3 ? playOn : (c < 0 ? Dart(-1, -1 - c) : Dart(c ~/ 4, c % 4));

  int get value => isControl ? 0 : field * mult;
  bool get isMiss => field == 0;
  bool get isBull => field == 25;
  bool get isDouble => field > 0 && mult == 2;
  bool get isTriple => mult == 3;

  String get label {
    if (field == -3) return 'Runde übersprungen';
    if (field == -2) return 'Weiterspielen';
    if (isControl) return mult == 1 ? 'Single Out an' : 'Single Out aus';
    if (field == 0) return 'Miss';
    if (field == 25) return mult == 2 ? 'Bull' : '25';
    return '${mult == 2 ? 'D' : mult == 3 ? 'T' : ''}$field';
  }

  /// Schlüssel für die Trefferverteilung (S20, D20, T20, 25, 50, Miss).
  String get key {
    if (field == 0) return 'Miss';
    if (field == 25) return mult == 2 ? '50' : '25';
    return '${mult == 2 ? 'D' : mult == 3 ? 'T' : 'S'}$field';
  }

  Map<String, dynamic> toJson() => {
        'f': field,
        'm': mult,
        'a': jitterA,
        'r': jitterR,
        't': tilt,
        'i': inner,
      };

  factory Dart.fromJson(Map<String, dynamic> j) => Dart(
        j['f'] as int,
        j['m'] as int,
        jitterA: (j['a'] as num).toDouble(),
        jitterR: (j['r'] as num).toDouble(),
        tilt: (j['t'] as num).toDouble(),
        inner: j['i'] as bool,
      );
}

int sumOf(Iterable<Dart> darts) => darts.fold(0, (a, d) => a + d.value);

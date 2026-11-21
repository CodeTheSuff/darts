import 'dart:math';

/// Online-Raum-Codes: 6 Zeichen ohne verwechselbare Zeichen (kein 0/O, 1/I/L).
/// 31^6 ≈ 887 Mio. Möglichkeiten – zusammen mit Rate-Limit und Freigabe durch den Host
/// praktisch nicht zu erraten.
class RoomCode {
  static const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const length = 6;

  static String generate([Random? random]) {
    final r = random ?? Random.secure();
    return List.generate(length, (_) => alphabet[r.nextInt(alphabet.length)]).join();
  }

  /// Eingabe vereinheitlichen: Großbuchstaben, Leerzeichen und Bindestriche entfernen.
  static String normalize(String input) => input.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');

  static bool isValid(String code) =>
      code.length == length && code.split('').every((c) => alphabet.contains(c));

  /// Anzeige mit Lücke in der Mitte: "K7M 2QX".
  static String pretty(String code) =>
      code.length == length ? '${code.substring(0, 3)} ${code.substring(3)}' : code;
}

/// Geheimes Host-Token (zum Zurückholen des eigenen Raums nach Verbindungsabbruch).
String randomToken([int bytes = 24]) {
  final r = Random.secure();
  return [for (var i = 0; i < bytes; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
}

/// Platzhalter außerhalb des Browsers: Android nutzt audioplayers (SoundPool).
class WebAudio {
  WebAudio._();

  static bool get supported => false;

  static void installUnlock() {}

  static Future<void> load(String asset) async {}

  static Future<void> play(String asset, double volume, {bool waitForEnd = false}) async {}

  static String get state => 'none';
}

import 'dart:typed_data';

import 'platform_env_io.dart' if (dart.library.js_interop) 'platform_env_web.dart' as impl;

/// Plattform-Weiche zwischen Android (APK) und Browser (Web-App).
///
/// Alles, was im Browser anders laufen muss (Datei speichern, Vollbild,
/// Speicher-Schutz, Home-Bildschirm), geht über diese Schnittstelle.
/// In Tests lässt sich [Plat.I] durch eine Attrappe ersetzen.
abstract class PlatformEnv {
  /// Läuft im Browser.
  bool get isWeb;

  /// iPhone oder iPad (auch iPadOS mit Desktop-Kennung).
  bool get isIos;

  /// Vom Home-Bildschirm gestartet (PWA, ohne Browser-Leiste).
  bool get isStandalone;

  /// Das Gerät kann vibrieren (Android immer, Browser nur mit `navigator.vibrate`).
  bool get canVibrate;

  /// Bittet den Browser, die Daten nicht automatisch zu löschen
  /// (`navigator.storage.persist()`). Liefert, ob der Speicher geschützt ist.
  Future<bool> requestPersistentStorage();

  /// Speichert bzw. teilt eine Datei.
  /// Android: Teilen-Dialog. Browser: Download (iPhone/iPad: Teilen-Dialog mit „In Dateien sichern“).
  /// Liefert `false`, wenn der Nutzer abgebrochen hat.
  Future<bool> saveFile(Uint8List bytes, {required String name, required String mime, String? subject});

  /// Vollbild per Fullscreen-API möglich (nicht auf dem iPhone).
  bool get fullscreenSupported;
  bool get isFullscreen;
  Future<void> setFullscreen(bool on);

  /// Seite neu laden (nur Web, z. B. nach einem Update).
  void reload();
}

class Plat {
  Plat._();

  static PlatformEnv? _override;

  /// Aktuelle Plattform (in Tests per [I] setzbar).
  static PlatformEnv get I => _override ??= impl.createPlatformEnv();
  static set I(PlatformEnv v) => _override = v;
}

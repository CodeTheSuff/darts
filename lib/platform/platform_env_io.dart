import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import 'platform_env.dart';

PlatformEnv createPlatformEnv() => IoPlatformEnv();

/// Android (und Tests auf der VM): Verhalten wie bisher.
class IoPlatformEnv implements PlatformEnv {
  @override
  bool get isWeb => false;

  @override
  bool get isIos => false;

  @override
  bool get isStandalone => true;

  @override
  bool get canVibrate => true;

  @override
  Future<bool> requestPersistentStorage() async => true;

  @override
  Future<bool> saveFile(Uint8List bytes, {required String name, required String mime, String? subject}) async {
    final r = await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: mime, name: name)],
      fileNameOverrides: [name],
      subject: subject,
    ));
    return r.status != ShareResultStatus.dismissed;
  }

  @override
  bool get fullscreenSupported => false;

  @override
  bool get isFullscreen => false;

  @override
  Future<void> setFullscreen(bool on) async {}

  @override
  void reload() {}
}

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'platform_env.dart';

PlatformEnv createPlatformEnv() => WebPlatformEnv();

/// Browser (Web-App, auch Safari auf iPhone/iPad).
class WebPlatformEnv implements PlatformEnv {
  @override
  bool get isWeb => true;

  @override
  bool get isIos {
    try {
      final nav = web.window.navigator;
      final ua = nav.userAgent;
      if (RegExp('iPhone|iPad|iPod').hasMatch(ua)) return true;
      // iPadOS meldet sich als Mac – erkennbar an Touch.
      return nav.platform == 'MacIntel' && nav.maxTouchPoints > 1;
    } catch (_) {
      return false;
    }
  }

  @override
  bool get isStandalone {
    try {
      if (web.window.matchMedia('(display-mode: standalone)').matches) return true;
      if (web.window.matchMedia('(display-mode: fullscreen)').matches) return true;
      // Safari (iOS): eigenes Feld navigator.standalone
      final s = (web.window.navigator as JSObject)['standalone'];
      return s != null && s.isA<JSBoolean>() && (s as JSBoolean).toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  bool get canVibrate {
    try {
      return (web.window.navigator as JSObject).has('vibrate');
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPersistentStorage() async {
    try {
      final nav = web.window.navigator as JSObject;
      if (!nav.has('storage')) return false;
      final storage = web.window.navigator.storage;
      if (!(storage as JSObject).has('persist')) return false;
      if ((await storage.persisted().toDart).toDart) return true;
      return (await storage.persist().toDart).toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> saveFile(Uint8List bytes, {required String name, required String mime, String? subject}) async {
    // iPhone/iPad: Teilen-Dialog („In Dateien sichern“, AirDrop, Mail …). Download geht dort zwar auch,
    // landet aber versteckt im Downloads-Ordner der Dateien-App.
    if (isIos) {
      try {
        final file = web.File([bytes.toJS].toJS, name, web.FilePropertyBag(type: mime));
        final data = web.ShareData(files: [file].toJS, title: subject ?? name);
        final nav = web.window.navigator;
        if ((nav as JSObject).has('canShare') && nav.canShare(data)) {
          await nav.share(data).toDart;
          return true;
        }
      } catch (e) {
        // Abgebrochen → nichts weiter tun. Andere Fehler (z. B. keine Nutzer-Geste) → Download.
        if (_isAbort(e)) return false;
      }
    }
    _download(bytes, name, mime);
    return true;
  }

  static bool _isAbort(Object e) {
    try {
      final j = e as JSAny?;
      if (j != null && j.isA<web.DOMException>()) return (j as web.DOMException).name == 'AbortError';
    } catch (_) {}
    return '$e'.contains('AbortError');
  }

  static void _download(Uint8List bytes, String name, String mime) {
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
    final url = web.URL.createObjectURL(blob);
    final a = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = name
      ..style.display = 'none';
    web.document.body?.append(a);
    a.click();
    a.remove();
    // Erst später freigeben, sonst bricht Safari den Download ab.
    Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  }

  @override
  bool get fullscreenSupported {
    try {
      final d = web.document as JSObject;
      if (d.has('fullscreenEnabled')) return web.document.fullscreenEnabled;
      final w = d['webkitFullscreenEnabled'];
      return w != null && w.isA<JSBoolean>() && (w as JSBoolean).toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  bool get isFullscreen {
    try {
      final d = web.document as JSObject;
      if (d.has('fullscreenElement')) return web.document.fullscreenElement != null;
      return d['webkitFullscreenElement'] != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> setFullscreen(bool on) async {
    try {
      final d = web.document as JSObject;
      final el = web.document.documentElement as JSObject?;
      if (on) {
        if (el == null) return;
        if (el.has('requestFullscreen')) {
          await (el.callMethod<JSPromise<JSAny?>?>('requestFullscreen'.toJS))?.toDart;
        } else if (el.has('webkitRequestFullscreen')) {
          el.callMethod<JSAny?>('webkitRequestFullscreen'.toJS);
        }
      } else if (isFullscreen) {
        if (d.has('exitFullscreen')) {
          await (d.callMethod<JSPromise<JSAny?>?>('exitFullscreen'.toJS))?.toDart;
        } else if (d.has('webkitExitFullscreen')) {
          d.callMethod<JSAny?>('webkitExitFullscreen'.toJS);
        }
      }
    } catch (_) {
      // Ohne Nutzer-Geste oder nicht erlaubt: still ignorieren.
    }
  }

  @override
  void reload() => web.window.location.reload();
}

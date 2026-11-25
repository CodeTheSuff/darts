import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'data/error_log.dart';
import 'data/match_controller.dart';
import 'data/sound.dart';
import 'data/storage.dart';
import 'data/tournament_store.dart';
import 'ui/about_screen.dart';
import 'ui/home_screen.dart';
import 'ui/link_coordinator.dart';
import 'ui/look.dart';
import 'ui/theme.dart';
import 'net/link.dart';
import 'net/server_link.dart';
import 'platform/web_hints.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  // Browser: Audio-Freischaltung (iOS), Speicher-Schutz, Hinweise. Android: nichts.
  await WebHints.init();
  ErrorLog.situation = () {
    final l = Link.I;
    final link = switch (l.role) {
      LinkRole.host => 'Host mit ${l.peerCount} Gerät(en)',
      LinkRole.client => LinkCoordinator.viewer ? 'Anzeige an ${l.hostName ?? '?'}' : 'Gast bei ${l.hostName ?? '?'}',
      LinkRole.none => 'nicht gekoppelt',
    };
    return 'Bildschirm: ${RouteLog.current} · Kopplung: $link';
  };
  await ErrorLog.init(appVersion: appVersion);
  // Töne einmal vorladen (im Hintergrund, blockiert den Start nicht).
  unawaited(Sound.preload());
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  applyStoredTheme();
  MatchController.onTournamentMatchDone = TournamentStore.onMatchDone;
  LinkCoordinator.init();
  registerLicenses();
  runApp(const DartsApp());
}

class DartsApp extends StatefulWidget {
  const DartsApp({super.key});

  @override
  State<DartsApp> createState() => _DartsAppState();
}

class _DartsAppState extends State<DartsApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showHangNotice();
      // Nach Absturz/Neustart die Kopplung wiederherstellen (nur kurz danach).
      unawaited(LinkCoordinator.restoreSession());
      // Link „App mit diesem Server verbinden“ (Seite https://<server>/app)
      ServerLink.confirm = _confirmServer;
      ServerLink.done = _serverDone;
      unawaited(ServerLink.init());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ErrorLog.setActive(state == AppLifecycleState.resumed);
    ErrorLog.crumb('App: ${state.name}');
  }

  @override
  void didChangePlatformBrightness() {
    if (Store.themeId == 'auto') applyStoredTheme(context: context);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ThemeHost.tick,
      builder: (_, _, _) => MaterialApp(
        title: 'Darts',
        navigatorKey: navigatorKey,
        navigatorObservers: [RouteLog()],
        debugShowCheckedModeBanner: false,
        theme: buildTheme(C.p),
        themeAnimationDuration: Duration.zero,
        builder: (ctx, child) {
          final mq = MediaQuery.of(ctx);
          final scale = ThemeHost.fontScale;
          if (scale == 1.0) return child!;
          return MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * scale)),
            child: child!,
          );
        },
        home: const HomeScreen(),
      ),
    );
  }
}

/// Schreibt Bildschirmwechsel ins Fehlerprotokoll.
class RouteLog extends NavigatorObserver {
  static String current = 'Start';

  static String _name(Route<dynamic>? r) {
    if (r == null) return 'Start';
    final n = r.settings.name;
    if (n != null) return n;
    if (r is MaterialPageRoute) {
      try {
        return r.builder(navigatorKey.currentContext!).runtimeType.toString();
      } catch (_) {}
    }
    return r.runtimeType.toString();
  }

  void _set(Route<dynamic>? r, String what) {
    current = _name(r);
    ErrorLog.crumb('$what: $current');
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _set(route, 'Öffnet');

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _set(previousRoute, 'Zurück zu');

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _set(newRoute, 'Ersetzt durch');
}

Future<bool> _confirmServer(String server) async {
  final ctx = navigatorKey.currentContext;
  if (ctx == null || !ctx.mounted) return false;
  final ok = await showDialog<bool>(
    context: ctx,
    builder: (c) => AlertDialog(
      title: const Text('Mit Server verbinden?'),
      content: Text('Online-Spiele und Updates laufen dann über\n\n$server\n\n'
          'Das kannst du jederzeit unter Einstellungen → Daten → Server ändern.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Verbinden')),
      ],
    ),
  );
  return ok ?? false;
}

void _serverDone(String server, String? error) {
  final ctx = navigatorKey.currentContext;
  if (ctx == null || !ctx.mounted) return;
  if (error == null) {
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(content: Text('Verbunden mit $server')));
    return;
  }
  showDialog<void>(
    context: ctx,
    builder: (c) => AlertDialog(
      title: const Text('Server nicht erreichbar'),
      content: Text('$server\n\n$error\n\nDie Adresse wurde nicht übernommen.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
    ),
  );
}

/// Meldet nach dem Start, dass die App beim letzten Mal eingefroren war.
void showHangNotice() {
  final item = ErrorLog.pendingNotice;
  final ctx = navigatorKey.currentContext;
  if (item == null || ctx == null) return;
  ErrorLog.pendingNotice = null;
  showDialog<void>(
    context: ctx,
    builder: (c) => AlertDialog(
      title: const Text('Die App hat gehangen'),
      content: const Text('Beim letzten Mal hat die App nicht mehr reagiert. Die Details stehen im Fehlerprotokoll '
          '(Einstellungen → Über die App → Fehlerprotokoll). Du kannst sie von dort teilen.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
    ),
  );
}

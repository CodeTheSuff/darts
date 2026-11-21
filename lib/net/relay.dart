import 'dart:async';

import 'package:darts_protocol/darts_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'peer_socket.dart';

/// Online-Kopplung über den Vermittlungs-Server (Relais).
///
/// Der Server reicht nur Umschläge ([RelayFrame]) weiter. Darin steckt unverändert
/// dieselbe Link-Nachricht wie im WLAN (hello/auth/state/dart …). Dadurch arbeitet
/// `Link` online genauso wie im WLAN – nur der Transport ist ein anderer.
///
/// Läuft mit `web_socket_channel` auf Android und im Browser.

/// Close-Code „Raum schließen“ (sonst gilt jede Trennung nur als „Host offline“).
const relayCloseRoom = 4000;

/// Kennung der App im ersten Frame.
const relayApp = 'darts';

/// Zustand der Verbindung zum Server.
enum RelayStatus {
  /// Verbinde (erstmals oder nach Abbruch).
  connecting,

  /// Raum offen (Host) bzw. Host erreichbar (Gast).
  online,

  /// Gast: im Raum, aber der Host ist gerade weg.
  hostOffline,

  /// Raum wurde geschlossen bzw. existiert nicht mehr – keine Wiederverbindung.
  closed,

  /// Endgültiger Fehler (z. B. App zu alt) – keine Wiederverbindung.
  failed,
}

/// Verständliche Meldung zu einem Server-Fehler.
String relayErrorText(RelayError? code, {bool host = false}) => switch (code) {
      RelayError.noRoom => 'Kein Raum mit diesem Code gefunden – Code prüfen (oder der Raum ist abgelaufen).',
      RelayError.full => 'Der Raum ist voll (höchstens ${RelayLimits.maxPeersPerRoom} Geräte).',
      RelayError.rate => 'Zu viele Versuche – bitte kurz warten und noch einmal probieren.',
      RelayError.busy => 'Der Server ist gerade ausgelastet – bitte später noch einmal versuchen.',
      RelayError.token => host
          ? 'Der alte Raum gehört nicht mehr diesem Gerät – es wird ein neuer Raum geöffnet.'
          : 'Der Raum konnte nicht zurückgeholt werden.',
      RelayError.bad => 'Der Server hat die Anfrage nicht verstanden.',
      RelayError.update => 'Diese App-Version ist zu alt für den Server – bitte aktualisieren.',
      null => 'Unbekannter Fehler vom Server.',
    };

/// Meldung, wenn der Server gar nicht erreichbar ist.
const relayUnreachable = 'Server nicht erreichbar – Internet an? Server-Adresse prüfen (Koppeln → Erweitert).';

RelayError? _errorOf(RelayFrame f) {
  final c = f.str('code');
  return RelayError.values.where((e) => e.name == c).firstOrNull;
}

/// Gemeinsame Technik für Host und Gast: Verbindung, Ping, Wiederverbindung mit Backoff.
abstract class RelayClient {
  RelayClient(this.url, {WebSocketChannel Function(Uri)? connector, Duration? pingEvery, Duration? idleTimeout})
      : _connector = connector ?? WebSocketChannel.connect,
        _pingEvery = pingEvery ?? RelayLimits.pingEvery,
        _idleTimeout = idleTimeout ?? RelayLimits.idleTimeout;

  /// WebSocket-Adresse des Relais (ws:// bzw. wss://…/ws).
  final Uri url;
  final WebSocketChannel Function(Uri) _connector;
  final Duration _pingEvery;
  final Duration _idleTimeout;

  /// Wartezeiten zwischen Wiederverbindungen (letzter Wert wiederholt sich).
  @visibleForTesting
  static List<Duration> retryDelays = const [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
  ];

  /// Statuswechsel (mit Text für die Anzeige).
  void Function(RelayStatus status, String text)? onStatus;

  /// Server meldet „App zu alt“ – `info` enthält ggf. {version, apk}.
  void Function(Map<String, dynamic>? info)? onUpdateRequired;

  RelayStatus status = RelayStatus.connecting;
  String statusText = 'Verbinde mit Server …';

  WebSocketChannel? _ch;
  StreamSubscription<dynamic>? _sub;
  Timer? _ping;
  Timer? _retry;
  DateTime _lastRx = DateTime.now();
  bool _stopped = false;
  int _attempt = 0;
  final _first = Completer<String?>();

  /// Ergebnis des ersten Versuchs: null = Raum offen/beigetreten, sonst Fehlermeldung.
  Future<String?> get first => _first.future;

  bool get isStopped => _stopped;

  /// Ist die Verbindung zum Server gerade offen?
  bool get connected => _ch != null;

  void start() => unawaited(_open());

  Future<void> _open() async {
    if (_stopped) return;
    _setStatus(RelayStatus.connecting, _attempt == 0 ? 'Verbinde mit Server …' : 'Verbindung zum Server verloren – verbinde neu …');
    final WebSocketChannel ch;
    try {
      ch = _connector(url);
      await ch.ready.timeout(const Duration(seconds: 8));
    } catch (_) {
      _failFirst(relayUnreachable);
      _scheduleRetry();
      return;
    }
    if (_stopped) {
      unawaited(ch.sink.close());
      return;
    }
    _ch = ch;
    _lastRx = DateTime.now();
    _sub = ch.stream.listen(
      _onData,
      onDone: () => _lost(ch),
      onError: (_) => _lost(ch),
      cancelOnError: true,
    );
    _ping?.cancel();
    _ping = Timer.periodic(_pingEvery, (_) {
      if (DateTime.now().difference(_lastRx) > _idleTimeout) {
        // Server schweigt zu lange – Verbindung neu aufbauen.
        unawaited(ch.sink.close());
        _lost(ch);
        return;
      }
      sendFrame(RelayFrame.ping());
    });
    onOpen();
  }

  void _onData(dynamic raw) {
    _lastRx = DateTime.now();
    final f = RelayFrame.decode(raw);
    if (f == null) return;
    if (f.type == 'pong') return;
    if (f.type == 'error') {
      _onError(_errorOf(f), f);
      return;
    }
    onFrame(f);
  }

  void _onError(RelayError? code, RelayFrame f) {
    if (code == RelayError.update) {
      final u = f.fields['update'];
      onUpdateRequired?.call(u is Map ? Map<String, dynamic>.from(u) : null);
      fail(RelayStatus.failed, relayErrorText(code));
      return;
    }
    onError(code, f);
  }

  void _lost(WebSocketChannel ch) {
    if (_ch != ch) return;
    _ch = null;
    _sub?.cancel();
    _sub = null;
    _ping?.cancel();
    onLost();
    _failFirst(relayUnreachable);
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_stopped) return;
    final d = retryDelays[_attempt.clamp(0, retryDelays.length - 1)];
    _attempt++;
    _retry?.cancel();
    _retry = Timer(d, () => unawaited(_open()));
  }

  /// Erfolgreich (Raum offen / beigetreten): Backoff zurücksetzen.
  @protected
  void succeeded() {
    _attempt = 0;
    if (!_first.isCompleted) _first.complete(null);
  }

  void _failFirst(String text) {
    if (!_first.isCompleted) {
      _first.complete(text);
      // Erster Versuch gescheitert: nicht im Hintergrund weiterprobieren.
      _stopped = true;
      _retry?.cancel();
    }
  }

  /// Endgültig beenden mit Status (z. B. Raum geschlossen).
  @protected
  void fail(RelayStatus s, String text) {
    _failFirst(text);
    _setStatus(s, text);
    unawaited(close());
  }

  /// Wiederverbindung später erneut versuchen (z. B. Server voll).
  @protected
  void retryLater(String text) {
    _failFirst(text);
    _setStatus(RelayStatus.connecting, text);
    final ch = _ch;
    if (ch != null) {
      unawaited(ch.sink.close());
      _lost(ch);
    }
  }

  void _setStatus(RelayStatus s, String text) {
    if (status == RelayStatus.closed || status == RelayStatus.failed) return;
    status = s;
    statusText = text;
    onStatus?.call(s, text);
  }

  @protected
  void setStatus(RelayStatus s, String text) => _setStatus(s, text);

  @protected
  void sendFrame(RelayFrame f) {
    try {
      _ch?.sink.add(f.encode());
    } catch (_) {}
  }

  @protected
  void onOpen();

  @protected
  void onFrame(RelayFrame f);

  @protected
  void onError(RelayError? code, RelayFrame f);

  /// Verbindung zum Server weg (wird gleich neu aufgebaut).
  @protected
  void onLost();

  /// Verbindung beenden. [closeCode] [relayCloseRoom] = Raum schließen (nur Host).
  Future<void> close({int? closeCode}) async {
    _stopped = true;
    _retry?.cancel();
    _ping?.cancel();
    final ch = _ch;
    _ch = null;
    await _sub?.cancel();
    _sub = null;
    onLost();
    if (!_first.isCompleted) _first.complete('Abgebrochen');
    if (ch != null) {
      try {
        await (closeCode == null ? ch.sink.close() : ch.sink.close(closeCode, 'Raum geschlossen'))
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }
}

/// Host: öffnet (bzw. holt) einen Raum und liefert je Gast einen virtuellen [PeerSocket].
class RelayHost extends RelayClient {
  RelayHost(super.url, {this.room, this.token, super.connector, super.pingEvery, super.idleTimeout});

  /// Raum-Code und Token (vom Server; zum Zurückholen nach Abbruch).
  String? room;
  String? token;

  /// Raum gehört uns (resumed = zurückgeholt). Code + Token merken!
  void Function(String room, String token, bool resumed)? onHosted;

  /// Neuer Gast im Raum.
  void Function(PeerSocket socket)? onPeer;

  final Map<String, ChannelPeerSocket> _peers = {};

  /// Zahl der Gäste im Raum (auch noch nicht freigegebene).
  int get guests => _peers.length;

  @override
  void onOpen() => sendFrame(RelayFrame.host(app: relayApp, room: room, token: token));

  ChannelPeerSocket _peer(String id) {
    final have = _peers[id];
    if (have != null) return have;
    late final ChannelPeerSocket s;
    s = ChannelPeerSocket(
      remote: 'relay:$id',
      onSend: (d) => sendFrame(RelayFrame.to(id, d)),
      onClose: () {
        if (_peers[id] == s) _peers.remove(id);
        sendFrame(RelayFrame.kick(id));
      },
    );
    _peers[id] = s;
    onPeer?.call(s);
    return s;
  }

  @override
  void onFrame(RelayFrame f) {
    switch (f.type) {
      case 'hosted':
        final r = f.str('room'), t = f.str('token');
        if (r == null || t == null) return;
        room = r;
        token = t;
        succeeded();
        setStatus(RelayStatus.online, 'Raum offen');
        onHosted?.call(r, t, f.flag('resumed'));
      case 'peer+':
        final id = f.str('peer');
        if (id != null) _peer(id);
      case 'peer-':
        final id = f.str('peer');
        _peers.remove(id)?.terminate();
      case 'from':
        final id = f.str('peer'), d = f.str('d');
        // Unbekannter Gast (z. B. nach dem Zurückholen): wie neu verbunden behandeln.
        if (id != null && d != null) _peer(id).deliver(d);
      case 'closed':
        fail(RelayStatus.closed, 'Der Raum wurde geschlossen.');
    }
  }

  @override
  void onError(RelayError? code, RelayFrame f) {
    switch (code) {
      case RelayError.token:
        // Raum gehört inzwischen jemand anderem → neuen Raum öffnen (anderer Code).
        room = null;
        token = null;
        setStatus(RelayStatus.connecting, relayErrorText(code, host: true));
        onOpen();
      case RelayError.busy || RelayError.rate:
        retryLater(relayErrorText(code, host: true));
      default:
        fail(RelayStatus.failed, relayErrorText(code, host: true));
    }
  }

  @override
  void onLost() {
    for (final p in _peers.values.toList()) {
      p.terminate();
    }
    _peers.clear();
  }

  /// Raum endgültig schließen (Gäste bekommen „closed“).
  Future<void> closeRoom() => close(closeCode: relayCloseRoom);
}

/// Gast: tritt einem Raum bei und liefert je Sitzung einen [PeerSocket] zum Host.
///
/// Eine neue Sitzung beginnt, sobald der Host erreichbar ist (beim Beitritt, nach
/// „Host wieder online“ oder nach Wiederverbindung zum Server). Darin schickt `Link`
/// wie im WLAN sein `hello` (mit Schlüssel → keine erneute Freigabe).
class RelayGuest extends RelayClient {
  RelayGuest(super.url, {required this.room, super.connector, super.pingEvery, super.idleTimeout});

  final String room;

  /// Eigene Kennung im Raum (vom Server).
  String? peer;
  bool hostOnline = false;

  /// Neue Sitzung zum Host.
  void Function(PeerSocket socket)? onHostSocket;

  ChannelPeerSocket? _session;

  @override
  void onOpen() => sendFrame(RelayFrame.join(app: relayApp, room: room));

  void _openSession() {
    _session?.terminate();
    final s = ChannelPeerSocket(
      remote: 'relay:host',
      onSend: (d) => sendFrame(RelayFrame.toHost(d)),
      // Link schließt die Sitzung nur, wenn es nicht mehr verbunden sein will.
      onClose: () => unawaited(close()),
    );
    _session = s;
    setStatus(RelayStatus.online, 'Verbunden');
    onHostSocket?.call(s);
  }

  void _endSession() {
    _session?.terminate();
    _session = null;
  }

  @override
  void onFrame(RelayFrame f) {
    switch (f.type) {
      case 'joined':
        peer = f.str('peer');
        hostOnline = f.flag('hostOnline');
        succeeded();
        if (hostOnline) {
          _openSession();
        } else {
          setStatus(RelayStatus.hostOffline, 'Host offline – warte …');
        }
      case 'hostOnline':
        hostOnline = true;
        _openSession();
      case 'hostOffline':
        hostOnline = false;
        _endSession();
        setStatus(RelayStatus.hostOffline, 'Host offline – warte …');
      case 'd':
        final d = f.str('d');
        if (d != null) _session?.deliver(d);
      case 'closed':
        _endSession();
        fail(RelayStatus.closed, 'Der Host hat den Raum geschlossen.');
    }
  }

  @override
  void onError(RelayError? code, RelayFrame f) {
    switch (code) {
      case RelayError.full || RelayError.busy || RelayError.rate:
        retryLater(relayErrorText(code));
      case RelayError.noRoom:
        _endSession();
        fail(RelayStatus.closed, relayErrorText(code));
      default:
        _endSession();
        fail(RelayStatus.failed, relayErrorText(code));
    }
  }

  @override
  void onLost() => _endSession();
}

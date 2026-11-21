import 'dart:async';

/// Eine Verbindung zu einem Gegenüber (Gast aus Host-Sicht bzw. Host aus Gast-Sicht).
///
/// [Link] kennt nur diese Schnittstelle – ob darunter ein WebSocket im WLAN
/// (`lan_io.dart`) oder ein Kanal durch den Vermittlungs-Server (`relay.dart`) liegt,
/// ist für die Link-Logik egal.
abstract class PeerSocket {
  /// Eingehende Link-Nachrichten (JSON-Strings). Endet bei Trennung.
  Stream<String> get messages;

  /// Ausgehende Link-Nachricht (Fehler beim Senden werden still ignoriert).
  void send(String data);

  Future<void> close();

  /// Endet bei Trennung.
  Future<void> get done;

  /// IP (WLAN) bzw. "relay:p3" (online) – nur für Sperrliste/Logs.
  String get remote;
}

/// Einfache [PeerSocket]-Umsetzung über Callbacks (für virtuelle Kanäle und Tests).
class ChannelPeerSocket implements PeerSocket {
  ChannelPeerSocket({required this.remote, required void Function(String) onSend, void Function()? onClose})
      : _onSend = onSend, // ignore: prefer_initializing_formals
        _onClose = onClose; // ignore: prefer_initializing_formals

  @override
  final String remote;
  final void Function(String) _onSend;
  final void Function()? _onClose;
  final _in = StreamController<String>();
  final _done = Completer<void>();

  bool get isClosed => _done.isCompleted;

  /// Nachricht vom Gegenüber einspeisen.
  void deliver(String data) {
    if (!isClosed) _in.add(data);
  }

  /// Von außen getrennt (z. B. Gast weg, Server weg) – ohne [onClose] auszulösen.
  void terminate() {
    if (isClosed) return;
    _done.complete();
    _in.close();
  }

  @override
  Stream<String> get messages => _in.stream;

  @override
  void send(String data) {
    if (!isClosed) _onSend(data);
  }

  @override
  Future<void> close() async {
    if (isClosed) return;
    terminate();
    _onClose?.call();
  }

  @override
  Future<void> get done => _done.future;
}

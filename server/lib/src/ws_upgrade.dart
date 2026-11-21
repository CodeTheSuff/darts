import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const _guid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

/// Ergebnis eines WebSocket-Upgrades: die Verbindung und der Byte-Wächter darunter.
class UpgradedSocket {
  UpgradedSocket(this.ws, this.guard);
  final WebSocket ws;
  final GuardedSocket guard;
}

/// Führt den WebSocket-Handshake selbst aus (statt `WebSocketTransformer.upgrade`), damit
///  - **keine Kompression** ausgehandelt wird (keine „Deflate-Bomben“) und
///  - unter der WebSocket-Schicht ein [GuardedSocket] liegt, der eine Nachricht, die über viele
///    Fragmente immer größer wird, abbricht, **bevor** sie komplett im Speicher liegt.
///    (`maxPayloadLength` von dart:io gilt nur je Fragment, nicht je Nachricht.)
///
/// Liefert null, wenn die Anfrage kein gültiger Upgrade-Request ist (dann wurde schon mit 400 geantwortet).
Future<UpgradedSocket?> upgradeWebSocket(HttpRequest request, {required int maxMessageBytes}) async {
  final response = request.response;
  final key = request.headers.value('sec-websocket-key');
  if (!WebSocketTransformer.isUpgradeRequest(request) || key == null) {
    response
      ..statusCode = HttpStatus.badRequest
      ..headers.contentType = ContentType.text
      ..write('WebSocket erwartet');
    await response.close();
    return null;
  }
  final accept = base64.encode(sha1.convert(ascii.encode('$key$_guid')).bytes);
  response
    ..statusCode = HttpStatus.switchingProtocols
    ..headers.add(HttpHeaders.connectionHeader, 'Upgrade')
    ..headers.add(HttpHeaders.upgradeHeader, 'websocket')
    ..headers.add('Sec-WebSocket-Accept', accept)
    ..headers.contentLength = 0;
  final raw = await response.detachSocket();
  // UTF-8 kann bis zu 3 Bytes je Zeichen brauchen; dazu Platz für Rahmen-Header.
  final guard = GuardedSocket(raw, maxPendingBytes: maxMessageBytes * 3 + 64 * 1024);
  final ws = WebSocket.fromUpgradedSocket(
    guard,
    serverSide: true,
    compression: CompressionOptions.compressionOff,
    maxPayloadLength: maxMessageBytes * 3,
  );
  return UpgradedSocket(ws, guard);
}

/// Socket-Hülle, die eingehende Bytes seit der letzten fertig verarbeiteten Nachricht zählt.
///
/// Der Aufrufer meldet jede vollständig empfangene Nachricht mit [messageDone]. Kommen seitdem
/// mehr als [maxPendingBytes] an, wird die Verbindung hart getrennt.
class GuardedSocket extends StreamView<Uint8List> implements Socket {
  GuardedSocket._(this._inner, this.maxPendingBytes, StreamController<Uint8List> c)
      : _controller = c,
        super(c.stream);

  factory GuardedSocket(Socket inner, {required int maxPendingBytes}) {
    late GuardedSocket self;
    StreamSubscription<Uint8List>? sub;
    final c = StreamController<Uint8List>(
      sync: true,
      onListen: () {
        sub = inner.listen(
          (chunk) => self._onChunk(chunk),
          onError: (Object e, StackTrace s) => self._controller.addError(e, s),
          onDone: () => self._controller.close(),
          cancelOnError: false,
        );
      },
      onPause: () => sub?.pause(),
      onResume: () => sub?.resume(),
      onCancel: () => sub?.cancel(),
    );
    return self = GuardedSocket._(inner, maxPendingBytes, c);
  }

  final Socket _inner;
  final StreamController<Uint8List> _controller;
  final int maxPendingBytes;
  int _pending = 0;
  bool _overflowed = false;

  /// Wurde die Verbindung wegen zu großer Nachricht getrennt?
  bool get overflowed => _overflowed;

  void messageDone() => _pending = 0;

  void _onChunk(Uint8List chunk) {
    if (_overflowed) return;
    _pending += chunk.length;
    if (_pending > maxPendingBytes) {
      _overflowed = true;
      _inner.destroy();
      _controller.close();
      return;
    }
    _controller.add(chunk);
  }

  // ---- alles andere an den echten Socket durchreichen
  @override
  Encoding get encoding => _inner.encoding;
  @override
  set encoding(Encoding value) => _inner.encoding = value;
  @override
  void add(List<int> data) => _inner.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) => _inner.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => _inner.addStream(stream);
  @override
  Future<void> close() => _inner.close();
  @override
  Future<void> get done => _inner.done;
  @override
  Future<void> flush() => _inner.flush();
  @override
  void write(Object? object) => _inner.write(object);
  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) => _inner.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => _inner.writeCharCode(charCode);
  @override
  void writeln([Object? object = '']) => _inner.writeln(object);
  @override
  InternetAddress get address => _inner.address;
  @override
  InternetAddress get remoteAddress => _inner.remoteAddress;
  @override
  int get port => _inner.port;
  @override
  int get remotePort => _inner.remotePort;
  @override
  void destroy() => _inner.destroy();
  @override
  bool setOption(SocketOption option, bool enabled) => _inner.setOption(option, enabled);
  @override
  Uint8List getRawOption(RawSocketOption option) => _inner.getRawOption(option);
  @override
  void setRawOption(RawSocketOption option) => _inner.setRawOption(option);
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:darts_protocol/darts_protocol.dart';

/// Minimaler Vermittlungs-Server nur für Tests (vereinfacht nach docs/web_architektur.md, Abschnitt 3).
///
/// Der echte Server (Agent A, `server/`) hat zusätzlich TTL, Rate-Limit, Sperren usw.
/// Hier zählt nur das Verhalten, das die App sieht.
class TestRelay {
  TestRelay._(this._server);
  final HttpServer _server;

  int get port => _server.port;
  String get url => 'http://127.0.0.1:$port';

  final rooms = <String, TestRoom>{};
  int _nextPeer = 0;

  /// Älteste angenommene Protokollversion (größer als [relayProtocol] → `error update`).
  int minProtocol = 0;

  /// Gäste je Raum.
  int maxPeers = RelayLimits.maxPeersPerRoom;

  /// Nach dem Zurückholen des Raums dem Host die noch verbundenen Gäste als `peer+` melden.
  bool announceOnResume = true;

  /// Inhalt von /version.json.
  Map<String, dynamic> version = const VersionInfo(version: '3.0.0', build: 19, minProtocol: 3).toJson();

  /// Mitgeschnittene Frame-Typen (Client → Server).
  final received = <String>[];

  static Future<TestRelay> start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final r = TestRelay._(s);
    s.listen(r._onRequest);
    return r;
  }

  Future<void> stop() async {
    for (final room in rooms.values) {
      await room.host?.close();
      for (final g in room.guests.values) {
        await g.close();
      }
    }
    rooms.clear();
    await _server.close(force: true);
  }

  /// Verbindung des Hosts serverseitig kappen (wie Netzabbruch).
  Future<void> dropHost(String room) async => rooms[room]?.host?.close(1001);

  /// Wie der echte Server, wenn eine neue Host-Verbindung die alte ersetzt (Close-Code 4001).
  Future<void> replaceHost(String room) async => rooms[room]?.host?.close(4001);

  /// Verbindung eines Gasts serverseitig kappen.
  Future<void> dropGuest(String room, String peer) async => rooms[room]?.guests[peer]?.close(1001);

  Future<void> _onRequest(HttpRequest req) async {
    switch (req.uri.path) {
      case '/health':
        req.response.write('ok');
        await req.response.close();
        return;
      case '/version.json':
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(version));
        await req.response.close();
        return;
    }
    if (req.uri.path != relayPath || !WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final ws = await WebSocketTransformer.upgrade(req);
    _Conn? conn;
    ws.listen(
      (raw) {
        final f = RelayFrame.decode(raw);
        if (f == null) {
          _send(ws, RelayFrame.error(RelayError.bad));
          return;
        }
        received.add(f.type);
        if (f.type == 'ping') {
          _send(ws, RelayFrame.pong());
          return;
        }
        if (conn == null) {
          conn = _first(ws, f);
          return;
        }
        _relay(conn!, f);
      },
      onDone: () => _closed(ws, conn),
      onError: (_) => _closed(ws, conn),
      cancelOnError: true,
    );
  }

  _Conn? _first(WebSocket ws, RelayFrame f) {
    if ((f.integer('proto') ?? 0) < minProtocol) {
      _send(ws, RelayFrame.error(RelayError.update, 'zu alt', {'version': '3.1.0', 'apk': 'apk/Darts_3.1.0.apk'}));
      ws.close(1008);
      return null;
    }
    if (f.type == 'host') {
      final code = f.str('room'), token = f.str('token');
      if (code != null && token != null) {
        final room = rooms[code];
        if (room != null) {
          if (room.token != token) {
            _send(ws, RelayFrame.error(RelayError.token));
            ws.close(1008);
            return null;
          }
          room.host = ws;
          _send(ws, RelayFrame.hosted(code, token, resumed: true));
          for (final e in room.guests.entries) {
            _send(e.value, RelayFrame.hostOnline());
            if (announceOnResume) _send(ws, RelayFrame.peerJoined(e.key));
          }
          return _Conn(code, null);
        }
        if (RoomCode.isValid(code)) {
          // Raum frei/abgelaufen: mit demselben Code neu anlegen.
          final t = randomToken();
          rooms[code] = TestRoom(t)..host = ws;
          _send(ws, RelayFrame.hosted(code, t));
          return _Conn(code, null);
        }
      }
      var c = RoomCode.generate();
      while (rooms.containsKey(c)) {
        c = RoomCode.generate();
      }
      final t = randomToken();
      rooms[c] = TestRoom(t)..host = ws;
      _send(ws, RelayFrame.hosted(c, t));
      return _Conn(c, null);
    }
    if (f.type == 'join') {
      final code = f.str('room') ?? '';
      final room = rooms[code];
      if (room == null) {
        _send(ws, RelayFrame.error(RelayError.noRoom));
        ws.close(1008);
        return null;
      }
      if (room.guests.length >= maxPeers) {
        _send(ws, RelayFrame.error(RelayError.full));
        ws.close(1008);
        return null;
      }
      final id = 'p${++_nextPeer}';
      room.guests[id] = ws;
      _send(ws, RelayFrame.joined(id, hostOnline: room.host != null));
      final h = room.host;
      if (h != null) _send(h, RelayFrame.peerJoined(id));
      return _Conn(code, id);
    }
    _send(ws, RelayFrame.error(RelayError.bad));
    ws.close(1008);
    return null;
  }

  void _relay(_Conn c, RelayFrame f) {
    final room = rooms[c.room];
    if (room == null) return;
    if (c.peer == null) {
      switch (f.type) {
        case 'to':
          final g = room.guests[f.str('peer')];
          final d = f.str('d');
          if (g != null && d != null) _send(g, RelayFrame.toGuest(d));
        case 'all':
          final d = f.str('d');
          if (d == null) return;
          for (final g in room.guests.values) {
            _send(g, RelayFrame.toGuest(d));
          }
        case 'kick':
          room.guests.remove(f.str('peer'))?.close(4002);
      }
    } else if (f.type == 'd') {
      final h = room.host, d = f.str('d');
      if (h != null && d != null) _send(h, RelayFrame.from(c.peer!, d));
    }
  }

  void _closed(WebSocket ws, _Conn? c) {
    if (c == null) return;
    final room = rooms[c.room];
    if (room == null) return;
    if (c.peer == null) {
      if (room.host != ws) return;
      room.host = null;
      if (ws.closeCode == 4000) {
        rooms.remove(c.room);
        for (final g in room.guests.values) {
          _send(g, RelayFrame.closed());
          g.close(1000);
        }
        room.guests.clear();
      } else {
        for (final g in room.guests.values) {
          _send(g, RelayFrame.hostOffline());
        }
      }
    } else {
      if (room.guests[c.peer] == ws) room.guests.remove(c.peer);
      final h = room.host;
      if (h != null) _send(h, RelayFrame.peerLeft(c.peer!));
    }
  }

  static void _send(WebSocket ws, RelayFrame f) {
    try {
      ws.add(f.encode());
    } catch (_) {}
  }
}

class TestRoom {
  TestRoom(this.token);
  final String token;
  WebSocket? host;
  final guests = <String, WebSocket>{};
}

class _Conn {
  _Conn(this.room, this.peer);
  final String room;
  final String? peer;
}

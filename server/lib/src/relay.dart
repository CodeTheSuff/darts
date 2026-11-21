import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:darts_protocol/darts_protocol.dart';

import 'config.dart';
import 'log.dart';
import 'version_source.dart';
import 'ws_upgrade.dart';

/// Close-Codes, mit denen der Server Verbindungen beendet.
class CloseCodes {
  /// Host schließt den Raum bewusst (vom Client gesendet).
  static const hostClosesRoom = 4000;

  /// Host-Verbindung wurde durch eine neuere ersetzt.
  static const replaced = 4001;

  /// Gast wurde vom Host entfernt (`kick`).
  static const kicked = 4002;

  /// Zeitüberschreitung (kein `host`/`join` bzw. keine Aktivität).
  static const timeout = 4003;

  /// Raum geschlossen (nach `closed`).
  static const normal = WebSocketStatus.normalClosure;

  /// Fehler (nach `error`).
  static const policy = WebSocketStatus.policyViolation;

  /// Server fährt herunter.
  static const goingAway = WebSocketStatus.goingAway;
}

enum _Role { none, host, guest }

/// Ein Raum: nur Metadaten im Arbeitsspeicher (kein Spielstand, keine Namen).
class Room {
  Room(this.code, this.tokenHash, this.lastActivity);

  final String code;
  final List<int> tokenHash;
  int lastActivity;
  RelayConnection? host;
  final guests = <String, RelayConnection>{};
  int _nextPeer = 0;

  String nextPeerId() => 'p${++_nextPeer}';
}

/// Eine WebSocket-Verbindung (Host, Gast oder noch ohne `host`/`join`).
class RelayConnection {
  RelayConnection(this.ws, this.guard, this.ip, int now, double tokens)
      : connectedAt = now,
        lastSeen = now,
        _tokens = tokens,
        _lastRefill = now;

  final WebSocket ws;
  final GuardedSocket guard;
  final String ip;
  final int connectedAt;
  int lastSeen;
  _Role _role = _Role.none;
  Room? room;
  String? peer;
  bool closing = false;

  /// Nach `error update`: weitere Frames bis zum Trennen ignorieren.
  bool ignoreInput = false;

  double _tokens;
  int _lastRefill;

  void sendRaw(String s) {
    if (closing) return;
    try {
      ws.add(s);
    } catch (_) {}
  }

  void send(RelayFrame f) => sendRaw(f.encode());

  void close(int code, [String? reason]) {
    if (closing) return;
    closing = true;
    ws.close(code, reason).catchError((_) {});
  }
}

class _BadJoins {
  int count = 0;
  int lastAt = 0;
  int blockedUntil = 0;
}

/// Das Relais: ordnet Verbindungen Räumen zu und reicht Umschläge weiter.
/// Den Inhalt (`d`) versteht und speichert es nicht.
class RelayHub {
  RelayHub(this.config, this.log, this.versions);

  final ServerConfig config;
  final Log log;
  final VersionSource versions;

  final _rooms = <String, Room>{};
  final _conns = <RelayConnection>{};
  final _bad = <String, _BadJoins>{};
  final _clock = Stopwatch()..start();
  Timer? _ticker;

  int get roomCount => _rooms.length;
  int get connectionCount => _conns.length;

  /// Für Tests: gibt es diesen Raum?
  bool hasRoom(String code) => _rooms.containsKey(code);

  int get _now => _clock.elapsedMilliseconds;

  void start() {
    _ticker ??= Timer.periodic(config.tick, (_) => _onTick());
  }

  Future<void> shutdown() async {
    _ticker?.cancel();
    _ticker = null;
    for (final c in _conns.toList()) {
      _detach(c, closeCode: null, quiet: true);
      c.close(CloseCodes.goingAway, 'Server wird beendet');
    }
    _rooms.clear();
    // Kurz warten, damit die Close-Frames rausgehen.
    final pending = [for (final c in _conns) c.ws.done.timeout(const Duration(seconds: 2), onTimeout: () => null)];
    await Future.wait(pending).catchError((_) => <Object?>[]);
    for (final c in _conns.toList()) {
      c.guard.destroy();
    }
    _conns.clear();
  }

  /// Neue Verbindung nach dem Upgrade.
  void accept(UpgradedSocket s, String ip) {
    final c = RelayConnection(s.ws, s.guard, ip, _now, config.burst.toDouble());
    _conns.add(c);
    var finished = false;
    void done() {
      if (finished) return;
      finished = true;
      _conns.remove(c);
      _detach(c, closeCode: c.ws.closeCode);
      if (c.guard.overflowed) log.info('Verbindung getrennt: Nachricht zu groß');
    }

    s.ws.listen(
      (data) => _onMessage(c, data),
      onDone: done,
      onError: (Object _) {},
      cancelOnError: false,
    );
    s.ws.done.whenComplete(done).catchError((_) {});
  }

  // ------------------------------------------------------------------ Eingang

  void _onMessage(RelayConnection c, Object? data) {
    c.guard.messageDone();
    if (c.closing || c.ignoreInput) return;
    final now = _now;
    c.lastSeen = now;
    if (!_takeToken(c, now)) {
      log.info('Rate-Limit überschritten – Verbindung getrennt');
      _fail(c, RelayError.rate, 'Zu viele Nachrichten');
      return;
    }
    if (data is! String) {
      _fail(c, RelayError.bad, 'Nur Text-Frames');
      return;
    }
    if (data.length > config.maxFrameBytes) {
      log.info('Frame zu groß – Verbindung getrennt');
      _fail(c, RelayError.bad, 'Frame zu groß');
      return;
    }
    final f = RelayFrame.decode(data);
    if (f == null) {
      _fail(c, RelayError.bad, 'Kaputter Frame');
      return;
    }
    final room = c.room;
    if (room != null) room.lastActivity = now;
    switch (c._role) {
      case _Role.none:
        _hello(c, f);
      case _Role.host:
        _fromHost(c, room!, f);
      case _Role.guest:
        _fromGuest(c, room!, f);
    }
  }

  bool _takeToken(RelayConnection c, int now) {
    final elapsed = now - c._lastRefill;
    if (elapsed > 0) {
      c._tokens = (c._tokens + elapsed * config.messagesPerSecond / 1000).clamp(0, config.burst.toDouble());
      c._lastRefill = now;
    }
    if (c._tokens < 1) return false;
    c._tokens -= 1;
    return true;
  }

  void _hello(RelayConnection c, RelayFrame f) {
    if (f.type != 'host' && f.type != 'join') {
      _fail(c, RelayError.bad, 'Erster Frame muss host oder join sein');
      return;
    }
    final p = f.fields['proto'];
    final proto = p is num ? p.toInt() : 0;
    if (proto < config.minProtocol) {
      log.info('Veraltete App (Protokoll $proto) – Update-Hinweis gesendet');
      // Asynchron (Datei lesen); bis dahin nichts weiter annehmen.
      c.ignoreInput = true;
      _sendUpdateError(c);
      return;
    }
    if (f.type == 'host') {
      _host(c, f);
    } else {
      _join(c, f);
    }
  }

  Future<void> _sendUpdateError(RelayConnection c) async {
    final update = await versions.updateInfo().catchError((_) => null);
    c.send(RelayFrame.error(RelayError.update, 'Bitte die App aktualisieren', update));
    c.close(CloseCodes.policy, 'update');
  }

  void _host(RelayConnection c, RelayFrame f) {
    final roomIn = f.str('room');
    final tokenIn = f.str('token');
    if (roomIn != null && tokenIn != null) {
      if (_isBlocked(c.ip)) {
        _fail(c, RelayError.rate, 'Zu viele Fehlversuche – bitte später erneut');
        return;
      }
      final code = RoomCode.normalize(roomIn);
      final existing = _rooms[code];
      if (existing != null) {
        if (!_tokenMatches(existing, tokenIn)) {
          _countBad(c.ip);
          log.info('Falsches Host-Token für Raum ${Log.code(code)}');
          _fail(c, RelayError.token, 'Token passt nicht zum Raum');
          return;
        }
        _attachHost(c, existing, tokenIn, resumed: true);
        log.info('Raum ${Log.code(code)} zurückgeholt');
        return;
      }
      if (RoomCode.isValid(code) && _validToken(tokenIn)) {
        if (_rooms.length >= config.maxRooms) {
          log.warn('MAX_ROOMS erreicht');
          _fail(c, RelayError.busy, 'Server voll');
          return;
        }
        final room = Room(code, _hash(tokenIn), _now);
        _rooms[code] = room;
        _attachHost(c, room, tokenIn, resumed: false);
        log.info('Raum ${Log.code(code)} mit bisherigem Code neu angelegt (${_rooms.length} Räume)');
        return;
      }
      // Ungültige Angaben → einfach neuen Raum anlegen.
    }
    if (_rooms.length >= config.maxRooms) {
      log.warn('MAX_ROOMS erreicht');
      _fail(c, RelayError.busy, 'Server voll');
      return;
    }
    String code;
    var tries = 0;
    do {
      code = RoomCode.generate();
      if (++tries > 100) {
        _fail(c, RelayError.busy, 'Kein freier Raum-Code');
        return;
      }
    } while (_rooms.containsKey(code));
    final token = randomToken();
    final room = Room(code, _hash(token), _now);
    _rooms[code] = room;
    _attachHost(c, room, token, resumed: false);
    log.info('Raum ${Log.code(code)} erstellt (${_rooms.length} Räume)');
  }

  void _attachHost(RelayConnection c, Room room, String token, {required bool resumed}) {
    final old = room.host;
    c._role = _Role.host;
    c.room = room;
    room.host = c;
    room.lastActivity = _now;
    if (old != null && old != c) {
      old.room = null;
      old._role = _Role.none;
      old.close(CloseCodes.replaced, 'Neue Host-Verbindung');
      log.info('Host-Verbindung für Raum ${Log.code(room.code)} ersetzt');
    }
    c.send(RelayFrame.hosted(room.code, token, resumed: resumed));
    if (resumed) {
      // Der Host soll die schon verbundenen Gäste kennen (wie bei neuem Beitritt).
      for (final id in room.guests.keys) {
        c.send(RelayFrame.peerJoined(id));
      }
      final online = RelayFrame.hostOnline().encode();
      for (final g in room.guests.values) {
        g.sendRaw(online);
      }
    }
  }

  void _join(RelayConnection c, RelayFrame f) {
    if (_isBlocked(c.ip)) {
      _fail(c, RelayError.rate, 'Zu viele falsche Codes – bitte später erneut');
      return;
    }
    final code = RoomCode.normalize(f.str('room') ?? '');
    final room = _rooms[code];
    if (room == null) {
      _countBad(c.ip);
      log.debug('Beitritt zu unbekanntem Raum');
      _fail(c, RelayError.noRoom, 'Raum nicht gefunden');
      return;
    }
    if (room.guests.length >= config.maxPeersPerRoom) {
      log.info('Raum ${Log.code(code)} voll');
      _fail(c, RelayError.full, 'Raum ist voll');
      return;
    }
    final id = room.nextPeerId();
    c._role = _Role.guest;
    c.room = room;
    c.peer = id;
    room.guests[id] = c;
    room.lastActivity = _now;
    c.send(RelayFrame.joined(id, hostOnline: room.host != null));
    room.host?.send(RelayFrame.peerJoined(id));
    log.debug('Gast im Raum ${Log.code(code)} (${room.guests.length} Gäste)');
  }

  void _fromHost(RelayConnection c, Room room, RelayFrame f) {
    switch (f.type) {
      case 'to':
        final peer = f.str('peer');
        final d = f.str('d');
        if (peer == null || d == null) return _soft(c, 'to braucht peer und d');
        room.guests[peer]?.send(RelayFrame.toGuest(d));
      case 'all':
        final d = f.str('d');
        if (d == null) return _soft(c, 'all braucht d');
        final s = RelayFrame.toGuest(d).encode();
        for (final g in room.guests.values) {
          g.sendRaw(s);
        }
      case 'kick':
        final peer = f.str('peer');
        if (peer == null) return _soft(c, 'kick braucht peer');
        final g = room.guests[peer];
        if (g == null) return;
        _detach(g, closeCode: null);
        g.close(CloseCodes.kicked, 'Vom Host entfernt');
      case 'ping':
        c.send(RelayFrame.pong());
      default:
        _soft(c, 'Unerwarteter Frame');
    }
  }

  void _fromGuest(RelayConnection c, Room room, RelayFrame f) {
    switch (f.type) {
      case 'd':
        final d = f.str('d');
        if (d == null) return _soft(c, 'd braucht d');
        // Host offline → verwerfen.
        room.host?.send(RelayFrame.from(c.peer!, d));
      case 'ping':
        c.send(RelayFrame.pong());
      default:
        _soft(c, 'Unerwarteter Frame');
    }
  }

  // ------------------------------------------------------------------ Trennen / Räume

  /// Löst [c] aus seinem Raum. [closeCode] ist der Close-Code des Clients (4000 = Raum schließen).
  void _detach(RelayConnection c, {required int? closeCode, bool quiet = false}) {
    final room = c.room;
    if (room == null) return;
    c.room = null;
    room.lastActivity = _now;
    if (c._role == _Role.host && room.host == c) {
      room.host = null;
      if (quiet) return;
      if (closeCode == CloseCodes.hostClosesRoom) {
        _deleteRoom(room, 'vom Host geschlossen');
      } else {
        final off = RelayFrame.hostOffline().encode();
        for (final g in room.guests.values) {
          g.sendRaw(off);
        }
        log.debug('Host von Raum ${Log.code(room.code)} offline');
      }
    } else if (c._role == _Role.guest && room.guests[c.peer] == c) {
      room.guests.remove(c.peer);
      if (!quiet) room.host?.send(RelayFrame.peerLeft(c.peer!));
    }
  }

  void _deleteRoom(Room room, String why) {
    if (_rooms[room.code] == room) _rooms.remove(room.code);
    final closed = RelayFrame.closed().encode();
    final members = [?room.host, ...room.guests.values];
    room.host = null;
    room.guests.clear();
    for (final m in members) {
      m.room = null;
      m.sendRaw(closed);
      m.close(CloseCodes.normal, 'Raum geschlossen');
    }
    log.info('Raum ${Log.code(room.code)} gelöscht ($why, ${_rooms.length} Räume)');
  }

  void _onTick() {
    final now = _now;
    for (final c in _conns.toList()) {
      if (c.closing) {
        // Hängt der Close-Handshake (Gegenseite antwortet nicht): nach 10 s hart trennen.
        if (now - c.lastSeen > 10000 + config.idleTimeout.inMilliseconds) c.guard.destroy();
        continue;
      }
      if (c._role == _Role.none && now - c.connectedAt > config.helloTimeout.inMilliseconds) {
        log.debug('Hello-Timeout');
        c.close(CloseCodes.timeout, 'Kein host/join');
      } else if (now - c.lastSeen > config.idleTimeout.inMilliseconds) {
        log.debug('Idle-Timeout');
        _detach(c, closeCode: null);
        c.close(CloseCodes.timeout, 'Keine Aktivität');
      }
    }
    final ttl = config.roomTtl.inMilliseconds;
    for (final room in _rooms.values.toList()) {
      if (now - room.lastActivity > ttl) _deleteRoom(room, 'abgelaufen');
    }
    final keep = config.blockFor.inMilliseconds;
    _bad.removeWhere((_, b) => b.blockedUntil <= now && now - b.lastAt > keep);
  }

  // ------------------------------------------------------------------ Hilfen

  void _fail(RelayConnection c, RelayError code, String msg) {
    c.send(RelayFrame.error(code, msg));
    _detach(c, closeCode: null);
    c.close(CloseCodes.policy, code.name);
  }

  /// Fehler melden, Verbindung bleibt (strukturell gültiges JSON, aber unerwartet).
  void _soft(RelayConnection c, String msg) => c.send(RelayFrame.error(RelayError.bad, msg));

  void _countBad(String ip) {
    final now = _now;
    if (_bad.length > 100000) _bad.removeWhere((_, b) => b.blockedUntil <= now);
    final b = _bad.putIfAbsent(ip, _BadJoins.new);
    if (now - b.lastAt > config.blockFor.inMilliseconds) b.count = 0;
    b.count++;
    b.lastAt = now;
    if (b.count >= config.maxBadJoins && b.blockedUntil <= now) {
      b.blockedUntil = now + config.blockFor.inMilliseconds;
      b.count = 0;
      log.warn('Eine IP wurde nach zu vielen Fehlversuchen für ${config.blockFor.inMinutes} min gesperrt');
    }
  }

  bool _isBlocked(String ip) {
    final b = _bad[ip];
    return b != null && b.blockedUntil > _now;
  }

  static List<int> _hash(String token) => sha256.convert(utf8.encode(token)).bytes;

  static bool _validToken(String t) => t.length >= 16 && t.length <= 256 && RegExp(r'^[A-Za-z0-9_\-]+$').hasMatch(t);

  static bool _tokenMatches(Room room, String token) {
    final h = _hash(token);
    final ref = room.tokenHash;
    if (h.length != ref.length) return false;
    var diff = 0;
    for (var i = 0; i < h.length; i++) {
      diff |= h[i] ^ ref[i];
    }
    return diff == 0;
  }
}

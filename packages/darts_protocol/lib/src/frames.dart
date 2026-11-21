import 'dart:convert';

/// Protokollversion des Relais. Wird im ersten Frame gesendet; ist sie kleiner als
/// [VersionInfo.minProtocol] des Servers, antwortet er mit [RelayError.update].
const relayProtocol = 3;

/// WebSocket-Pfad auf dem Server.
const relayPath = '/ws';

/// Grenzen (Server prüft sie, Clients halten sich daran).
class RelayLimits {
  /// Größte erlaubte Nachricht (ein Turnier-Stand kann groß werden).
  static const maxFrameBytes = 4 * 1024 * 1024;

  /// Gäste je Raum (wie Link.maxPeers bei der WLAN-Kopplung).
  static const maxPeersPerRoom = 8;

  /// Nachrichten je Verbindung und Sekunde (Ausreißer bis [burst] erlaubt).
  static const messagesPerSecond = 40;
  static const burst = 200;

  /// Falsche Raum-Codes je IP, bevor sie für [blockFor] gesperrt wird.
  static const maxBadJoins = 10;
  static const blockFor = Duration(minutes: 10);

  /// Ohne ersten Frame (`host`/`join`) innerhalb dieser Zeit wird getrennt.
  static const helloTimeout = Duration(seconds: 10);

  /// Lebenszeichen (Ping) – die Clients senden alle [pingEvery] ein `ping`.
  static const pingEvery = Duration(seconds: 15);
  static const idleTimeout = Duration(seconds: 45);
}

/// Alle Frames sind JSON-Objekte mit dem Typ im Feld `r`.
///
/// Client → Server
///   {r:'host', proto, app, room?, token?}   Raum öffnen (oder mit room+token zurückholen)
///   {r:'join', proto, app, room}            einem Raum als Gast beitreten
///   {r:'to', peer, d}                        Host → ein Gast   (d = Link-Nachricht als JSON-String)
///   {r:'all', d}                             Host → alle Gäste
///   {r:'d', d}                               Gast → Host
///   {r:'kick', peer}                         Host trennt einen Gast
///   {r:'ping'}
///
/// Server → Client
///   {r:'hosted', room, token, resumed}       Raum gehört dir (resumed = zurückgeholt)
///   {r:'joined', peer, hostOnline}           du bist Gast `peer`
///   {r:'peer+', peer}  {r:'peer-', peer}      (an Host) Gast verbunden / getrennt
///   {r:'from', peer, d}                      (an Host) Nachricht eines Gasts
///   {r:'d', d}                               (an Gast) Nachricht des Hosts
///   {r:'hostOffline'} {r:'hostOnline'}       (an Gäste) Host weg / wieder da
///   {r:'closed'}                             Raum wurde geschlossen
///   {r:'error', code, msg, update?}          siehe [RelayError]
///   {r:'pong'}
class RelayFrame {
  RelayFrame(this.type, [Map<String, dynamic>? fields]) : fields = fields ?? {};

  final String type;
  final Map<String, dynamic> fields;

  // ---- Client → Server
  static RelayFrame host({required String app, String? room, String? token}) =>
      RelayFrame('host', {'proto': relayProtocol, 'app': app, 'room': ?room, 'token': ?token});
  static RelayFrame join({required String app, required String room}) =>
      RelayFrame('join', {'proto': relayProtocol, 'app': app, 'room': room});
  static RelayFrame to(String peer, String data) => RelayFrame('to', {'peer': peer, 'd': data});
  static RelayFrame all(String data) => RelayFrame('all', {'d': data});
  static RelayFrame toHost(String data) => RelayFrame('d', {'d': data});
  static RelayFrame kick(String peer) => RelayFrame('kick', {'peer': peer});
  static RelayFrame ping() => RelayFrame('ping');

  // ---- Server → Client
  static RelayFrame hosted(String room, String token, {bool resumed = false}) =>
      RelayFrame('hosted', {'room': room, 'token': token, 'resumed': resumed});
  static RelayFrame joined(String peer, {required bool hostOnline}) =>
      RelayFrame('joined', {'peer': peer, 'hostOnline': hostOnline});
  static RelayFrame peerJoined(String peer) => RelayFrame('peer+', {'peer': peer});
  static RelayFrame peerLeft(String peer) => RelayFrame('peer-', {'peer': peer});
  static RelayFrame from(String peer, String data) => RelayFrame('from', {'peer': peer, 'd': data});
  static RelayFrame toGuest(String data) => RelayFrame('d', {'d': data});
  static RelayFrame hostOffline() => RelayFrame('hostOffline');
  static RelayFrame hostOnline() => RelayFrame('hostOnline');
  static RelayFrame closed() => RelayFrame('closed');
  static RelayFrame pong() => RelayFrame('pong');
  static RelayFrame error(RelayError code, [String? msg, Map<String, dynamic>? update]) =>
      RelayFrame('error', {'code': code.name, 'msg': ?msg, 'update': ?update});

  String? str(String key) => fields[key] is String ? fields[key] as String : null;
  int? integer(String key) => (fields[key] as num?)?.toInt();
  bool flag(String key) => fields[key] == true;

  String encode() => jsonEncode({'r': type, ...fields});

  /// Liefert null bei kaputtem/zu großem Inhalt.
  static RelayFrame? decode(Object? raw) {
    if (raw is! String || raw.length > RelayLimits.maxFrameBytes) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map || j['r'] is! String) return null;
      final m = Map<String, dynamic>.from(j);
      final t = m.remove('r') as String;
      return RelayFrame(t, m);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'RelayFrame($type)';
}

/// Fehlercodes des Servers.
enum RelayError {
  /// Raum-Code unbekannt (oder abgelaufen).
  noRoom,

  /// Raum ist voll.
  full,

  /// App zu alt – `update` enthält {version, apk}.
  update,

  /// Zu viele Nachrichten / falsche Codes.
  rate,

  /// Unerwarteter Frame / kaputte Daten.
  bad,

  /// Host-Token passt nicht zum Raum.
  token,

  /// Server voll (MAX_ROOMS erreicht).
  busy,
}

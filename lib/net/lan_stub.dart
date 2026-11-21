import 'peer_socket.dart';

/// Web: keine WLAN-Kopplung (Browser können keine Server/UDP-Sockets öffnen).
/// Gleiche Schnittstelle wie `lan_io.dart`, aber alles „nicht verfügbar“.

const lanAvailable = false;

typedef LanGate = Future<int> Function(String ip, Map<String, String> query);

class LanServer {
  LanServer._();

  int get port => 0;

  static Future<LanServer> bind({
    required int preferredPort,
    required Map<String, dynamic>? Function() info,
    required LanGate gate,
    required void Function(PeerSocket socket, Map<String, String> query) onPeer,
  }) =>
      Future.error(UnsupportedError('Im Browser gibt es keine WLAN-Kopplung – bitte „Online“ nutzen.'));

  void announce(List<int> payload, Iterable<String> targets, int port) {}

  Future<void> close() async {}
}

Future<PeerSocket> lanConnect(String address, int port, String query, Duration timeout) =>
    Future.error(UnsupportedError('Im Browser gibt es keine WLAN-Kopplung.'));

class LanListener {
  static Future<LanListener?> bind(int port, void Function(String address, String payload) onMessage) async => null;

  void close() {}
}

class LanProber {
  LanProber(Duration connectTimeout);

  Future<Map<String, dynamic>?> info(String address, int port, {bool patient = false}) async => null;

  void close() {}
}

Future<List<(String, int)>> lanNetworks() async => const [];

Future<List<String>> lanLocalAddresses() async => const [];

Future<void> lanMulticast(bool acquire) async {}

import 'package:darts_protocol/darts_protocol.dart';
import 'package:darts_server/darts_server.dart';
import 'package:test/test.dart';

void main() {
  test('Standardwerte ohne Umgebungsvariablen', () {
    final c = ServerConfig.fromEnvironment({});
    expect(c.port, 8080);
    expect(c.host, '0.0.0.0');
    expect(c.publicUrl, '');
    expect(c.webDir, './web');
    expect(c.apkDir, './apk');
    expect(c.versionFile, './version.json');
    expect(c.roomTtl, const Duration(hours: 24));
    expect(c.maxRooms, 500);
    expect(c.maxPeersPerRoom, 8);
    expect(c.minProtocol, relayProtocol);
    expect(c.trustProxy, isFalse);
    expect(c.logLevel, LogLevel.info);
  });

  test('Umgebungsvariablen und Argumente', () {
    final c = ServerConfig.fromEnvironment({
      'PORT': '9000',
      'HOST': '127.0.0.1',
      'PUBLIC_URL': 'https://darts.example.org',
      'WEB_DIR': '/srv/web',
      'ROOM_TTL_HOURS': '0,5',
      'MAX_ROOMS': '20',
      'MAX_PEERS_PER_ROOM': '4',
      'MIN_PROTOCOL': '2',
      'TRUST_PROXY': 'true',
      'LOG_LEVEL': 'warn',
      'FREMD': 'egal',
    }, [
      '--port=9100',
      '--apk-dir=/srv/apk',
    ]);
    expect(c.port, 9100);
    expect(c.host, '127.0.0.1');
    expect(c.publicUrl, 'https://darts.example.org');
    expect(c.webDir, '/srv/web');
    expect(c.apkDir, '/srv/apk');
    expect(c.roomTtl, const Duration(minutes: 30));
    expect(c.maxRooms, 20);
    expect(c.maxPeersPerRoom, 4);
    expect(c.minProtocol, 2);
    expect(c.trustProxy, isTrue);
    expect(c.logLevel, LogLevel.warn);
  });

  test('Ungültige Werte → FormatException', () {
    expect(() => ServerConfig.fromEnvironment({'PORT': 'abc'}), throwsFormatException);
    expect(() => ServerConfig.fromEnvironment({'PORT': '70000'}), throwsFormatException);
    expect(() => ServerConfig.fromEnvironment({'TRUST_PROXY': 'vielleicht'}), throwsFormatException);
    expect(() => ServerConfig.fromEnvironment({'LOG_LEVEL': 'laut'}), throwsFormatException);
    expect(() => ServerConfig.fromEnvironment({'PUBLIC_URL': 'ftp://x'}), throwsFormatException);
    expect(() => ServerConfig.fromEnvironment({'ROOM_TTL_HOURS': '0'}), throwsFormatException);
    expect(() => ServerConfig.fromEnvironment({}, ['--unbekannt=1']), throwsFormatException);
  });
}

import 'package:darts_protocol/darts_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('Frames: hin und zurück', () {
    final f = RelayFrame.host(app: '3.0.0', room: 'ABC234', token: 'x');
    final back = RelayFrame.decode(f.encode())!;
    expect(back.type, 'host');
    expect(back.integer('proto'), relayProtocol);
    expect(back.str('room'), 'ABC234');
    final h = RelayFrame.decode(RelayFrame.host(app: '3.0.0').encode())!;
    expect(h.fields.containsKey('room'), isFalse);
  });

  test('Kaputte Frames werden verworfen', () {
    expect(RelayFrame.decode('kein json'), isNull);
    expect(RelayFrame.decode('{"x":1}'), isNull);
    expect(RelayFrame.decode(42), isNull);
    expect(RelayFrame.decode('x' * (RelayLimits.maxFrameBytes + 1)), isNull);
  });

  test('Raum-Codes', () {
    final c = RoomCode.generate();
    expect(RoomCode.isValid(c), isTrue);
    expect(RoomCode.normalize(' k7m-2qx '), 'K7M2QX');
    expect(RoomCode.isValid('K7M2QX'), isTrue);
    expect(RoomCode.isValid('K7M2Q0'), isFalse); // 0 nicht im Alphabet
    expect(RoomCode.pretty('K7M2QX'), 'K7M 2QX');
  });

  test('VersionInfo', () {
    const v = VersionInfo(version: '3.0.1', build: 20, minProtocol: 3, apkUrl: '/apk/Darts_3.0.1.apk');
    final back = VersionInfo.fromJson(v.toJson());
    expect(back.isNewerThan(19), isTrue);
    expect(back.isNewerThan(20), isFalse);
    expect(back.apkUrl, '/apk/Darts_3.0.1.apk');
  });
}

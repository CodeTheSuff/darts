import 'package:darts_counter/net/link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Netzanfang und Kurzadressen', () {
    expect(Link.networkPrefix('10.192.49.6', 19), '10.192.');
    expect(Link.networkPrefix('192.168.0.23', 24), '192.168.0.');
    expect(Link.shortAddress('10.192.63.187', '10.192.'), '63.187');
    expect(Link.completeAddress('63.187', '10.192.'), '10.192.63.187');
    expect(Link.completeAddress('10.192.63.187', '10.192.'), '10.192.63.187');
    expect(Link.completeAddress('23', '192.168.0.'), '192.168.0.23');
    expect(Link.completeAddress('63.187:47124', '10.192.'), '10.192.63.187:47124');
  });

  test('Suchtempo bleibt unter der Grenze der Nachbar-Tabelle (1024 Einträge, ~3 s je Adresse)', () {
    final perSecond = Link.scanBatch * 1000 / Link.scanTick.inMilliseconds;
    expect(perSecond * 3, lessThan(800));
  });
}

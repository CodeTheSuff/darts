import 'package:darts_counter/data/storage.dart';
import 'package:darts_counter/models/player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });

  LogEntry e(String pid, int t) => LogEntry(rid: 'r$t', oid: pid, pid: pid, t: t, mode: 'x01', d: PlayerStats());

  test('Statistik: zuletzt aktive Spieler oben, nie gespielt unten (Reihenfolge bleibt)', () {
    const a = Profile('a', 'Anna'), b = Profile('b', 'Ben'), c = Profile('c', 'Cleo'), d = Profile('d', 'Dora');
    Store.addEntries([e('a', 100), e('b', 300), e('a', 200), e('c', 50)]);
    expect(Store.lastPlayed(), {'a': 200, 'b': 300, 'c': 50});
    final sorted = Store.byLastPlayed(const [d, a, c, b]);
    expect(sorted.map((p) => p.id), ['b', 'a', 'c', 'd']);
    // Zwei nie gespielte behalten ihre Reihenfolge
    const x = Profile('x', 'X'), y = Profile('y', 'Y');
    expect(Store.byLastPlayed(const [y, x, b]).map((p) => p.id), ['b', 'y', 'x']);
  });
}

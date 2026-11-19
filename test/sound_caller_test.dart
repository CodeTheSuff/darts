import 'dart:async';

import 'package:darts_counter/data/sound.dart';
import 'package:darts_counter/data/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeVoice implements SoundVoice {
  static int created = 0;
  static int plays = 0;
  static int disposed = 0;
  _FakeVoice() {
    created++;
  }
  @override
  Future<void> load(String asset) async {}
  @override
  Future<void> play(double volume) async => plays++;
  @override
  Future<void> dispose() async => disposed++;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'sound': true});
    await Store.init();
  });

  test('500 Töne schnell hintereinander: feste Anzahl Player, nichts sammelt sich an', () async {
    await Sound.resetForTest();
    Sound.createVoice = _FakeVoice.new;
    _FakeVoice.created = 0;
    _FakeVoice.plays = 0;
    await Sound.preload();
    final fixed = Sound.voiceCount;
    expect(fixed, Sound.names.fold<int>(0, (a, n) => a + Sound.voicesFor(n)));
    for (var i = 0; i < 500; i++) {
      unawaited(Sound.play(i.isEven ? 'thunk' : 'ton'));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(_FakeVoice.plays, 500);
    expect(_FakeVoice.created, fixed, reason: 'keine neuen Player je Ton');
    expect(Sound.voiceCount, fixed);
    await Sound.resetForTest();
  });
}

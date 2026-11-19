import 'package:darts_counter/data/caller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Männerstimmen werden am Namen erkannt', () {
    expect(Caller.guessMale('en-gb-x-gbd-local'), true);
    expect(Caller.guessMale('en-gb-x-rjs-network'), true);
    expect(Caller.guessMale('de-de-x-deg-local'), true);
    expect(Caller.guessMale('en-gb-x-gba-local'), false);
    expect(Caller.guessMale('de-de-x-nfh-local'), false);
    expect(Caller.guessMale('en-GB-language#male_1-local'), true);
    expect(Caller.guessMale('en-GB-language#female_2-local'), false);
    expect(Caller.guessMale('de-DE-SMTm00'), true);
    expect(Caller.guessMale('irgendwas'), isNull);
  });
}

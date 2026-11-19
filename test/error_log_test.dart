import 'package:darts_counter/data/error_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Fehler mit Verlauf und Situation protokollieren und exportieren', () {
    ErrorLog.clear();
    ErrorLog.version = '9.9.9';
    ErrorLog.situation = () => 'Bildschirm: Test · Kopplung: Host';
    ErrorLog.crumb('Dart T20 von Simon');
    ErrorLog.record('error', 'Bad state: kaputt', StackTrace.current);
    final e = ErrorLog.entries.value.single;
    expect(e.title, 'Fehler');
    expect(e.situation, contains('Host'));
    expect(e.crumbs.single, endsWith('Dart T20 von Simon'));
    final text = ErrorLog.exportText();
    expect(text, contains('Bad state: kaputt'));
    expect(text, contains('Version 9.9.9'));
    expect(LogItem.fromJson(e.toJson()).message, e.message);
    for (var i = 0; i < 60; i++) {
      ErrorLog.record('stall', 'Ruckler $i');
    }
    expect(ErrorLog.entries.value.length, ErrorLog.maxEntries);
    expect(ErrorLog.entries.value.first.message, 'Ruckler 59');
  });
}

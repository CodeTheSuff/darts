// Erzeugt die Soundeffekte der App als WAV-Dateien (synthetisch).
// Aufruf: dart run tool/gen_sounds.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const sr = 22050;
final rnd = Random(7);

List<double> silence(double sec) => List.filled((sec * sr).round(), 0.0);

/// Ton mit ObertÃ¶nen und HÃ¼llkurve.
List<double> tone(double freq, double sec,
    {double attack = 0.01, double decay = 4, double vol = 0.5, double slideTo = 0, bool bright = false}) {
  final n = (sec * sr).round();
  final out = List<double>.filled(n, 0);
  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    final f = slideTo > 0 ? freq + (slideTo - freq) * (t / sec) : freq;
    phase += 2 * pi * f / sr;
    var s = sin(phase) + 0.35 * sin(2 * phase) + (bright ? 0.2 * sin(3 * phase) + 0.1 * sin(5 * phase) : 0.12 * sin(3 * phase));
    final env = (t < attack ? t / attack : 1.0) * exp(-decay * t);
    out[i] = s * env * vol;
  }
  return out;
}

/// Rauschimpuls (Explosion / Aufprall), tiefpassgefiltert.
List<double> noise(double sec, {double vol = 0.6, double decay = 6, double smooth = 0.85}) {
  final n = (sec * sr).round();
  final out = List<double>.filled(n, 0);
  var last = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    last = smooth * last + (1 - smooth) * (rnd.nextDouble() * 2 - 1);
    out[i] = last * exp(-decay * t) * vol * 3;
  }
  return out;
}

List<double> mix(List<List<double>> parts, List<double> offsets) {
  var len = 0;
  for (var i = 0; i < parts.length; i++) {
    len = max(len, (offsets[i] * sr).round() + parts[i].length);
  }
  final out = List<double>.filled(len, 0);
  for (var i = 0; i < parts.length; i++) {
    final o = (offsets[i] * sr).round();
    for (var j = 0; j < parts[i].length; j++) {
      out[o + j] += parts[i][j];
    }
  }
  return out;
}

void write(String name, List<double> s) {
  var peak = 0.0;
  for (final v in s) {
    peak = max(peak, v.abs());
  }
  final gain = peak > 0.95 ? 0.95 / peak : 1.0;
  final data = ByteData(44 + s.length * 2);
  void str(int o, String v) {
    for (var i = 0; i < v.length; i++) {
      data.setUint8(o + i, v.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + s.length * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sr, Endian.little);
  data.setUint32(28, sr * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, s.length * 2, Endian.little);
  for (var i = 0; i < s.length; i++) {
    data.setInt16(44 + i * 2, (s[i] * gain * 32767).round().clamp(-32768, 32767), Endian.little);
  }
  final f = File('assets/sounds/$name.wav');
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(data.buffer.asUint8List());
  stdout.writeln('${f.path}  ${(s.length / sr).toStringAsFixed(2)} s');
}

void main() {
  // Pfeil schlÃ¤gt ein: kurzer, dumpfer â€žThockâ€œ
  write('thunk', mix([noise(0.09, vol: 0.5, decay: 45, smooth: 0.6), tone(140, 0.1, decay: 40, vol: 0.5, slideTo: 80)], [0, 0]));

  // Bust: absteigender Ton
  write('bust', mix([tone(330, 0.5, decay: 3, vol: 0.4, slideTo: 150), tone(220, 0.5, decay: 3, vol: 0.3, slideTo: 100)], [0, 0.04]));

  // Leg / Checkout: kurzes Dur-Arpeggio
  write('leg', mix([
    tone(523, 0.5, decay: 5, vol: 0.4, bright: true),
    tone(659, 0.5, decay: 5, vol: 0.4, bright: true),
    tone(784, 0.8, decay: 3.5, vol: 0.45, bright: true),
  ], [0, 0.09, 0.18]));

  // 100+: Explosion + aufsteigende Fanfare
  write('ton', mix([
    noise(0.6, vol: 0.55, decay: 7),
    tone(392, 0.4, decay: 5, vol: 0.35, bright: true),
    tone(523, 0.4, decay: 5, vol: 0.35, bright: true),
    tone(659, 0.9, decay: 3, vol: 0.4, bright: true),
  ], [0, 0.15, 0.27, 0.39]));

  // 140+: doppelte Explosion, grÃ¶ÃŸere Fanfare
  write('ton40', mix([
    noise(0.7, vol: 0.6, decay: 6),
    noise(0.6, vol: 0.45, decay: 7),
    tone(392, 0.35, decay: 5, vol: 0.35, bright: true),
    tone(523, 0.35, decay: 5, vol: 0.35, bright: true),
    tone(659, 0.35, decay: 5, vol: 0.35, bright: true),
    tone(784, 1.2, decay: 2.2, vol: 0.45, bright: true),
    tone(1047, 1.2, decay: 2.2, vol: 0.25, bright: true),
  ], [0, 0.35, 0.15, 0.27, 0.39, 0.51, 0.51]));

  // 180: Feuerwerk + groÃŸe Fanfare
  final parts = <List<double>>[];
  final offs = <double>[];
  for (var i = 0; i < 6; i++) {
    parts.add(noise(0.8, vol: 0.5 + rnd.nextDouble() * 0.2, decay: 5 + rnd.nextDouble() * 3));
    offs.add(i * 0.42 + rnd.nextDouble() * 0.1);
  }
  final fan = [523.0, 659.0, 784.0, 1047.0];
  for (var i = 0; i < fan.length; i++) {
    parts.add(tone(fan[i], 0.3, decay: 4, vol: 0.35, bright: true));
    offs.add(0.2 + i * 0.12);
  }
  parts.add(tone(784, 2.2, decay: 1.2, vol: 0.4, bright: true));
  offs.add(0.75);
  parts.add(tone(1047, 2.2, decay: 1.2, vol: 0.35, bright: true));
  offs.add(0.75);
  parts.add(tone(1319, 2.2, decay: 1.2, vol: 0.25, bright: true));
  offs.add(0.75);
  write('max180', mix(parts, offs));

  // High Finish: funkelndes Arpeggio
  write('finish', mix([
    for (var i = 0; i < 6; i++) tone(<double>[523, 659, 784, 1047, 1319, 1568][i], 0.6, decay: 4, vol: 0.3, bright: true),
    noise(0.5, vol: 0.35, decay: 8),
  ], [0, 0.07, 0.14, 0.21, 0.28, 0.35, 0.0]));

  // Matchsieg: Fanfare
  write('win', mix([
    tone(523, 0.25, decay: 3, vol: 0.4, bright: true),
    tone(523, 0.25, decay: 3, vol: 0.4, bright: true),
    tone(523, 0.25, decay: 3, vol: 0.4, bright: true),
    tone(659, 1.4, decay: 1.5, vol: 0.45, bright: true),
    tone(784, 1.4, decay: 1.5, vol: 0.35, bright: true),
    noise(0.8, vol: 0.4, decay: 5),
  ], [0, 0.18, 0.36, 0.54, 0.54, 0.54]));

  silence(0); // unbenutzt, hÃ¤lt Helfer im Code
}

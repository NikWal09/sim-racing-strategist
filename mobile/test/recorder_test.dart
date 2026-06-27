/// Test nagrywania: okrążenie wyjazdowe nie jest zapisywane, a kolejne mierzone
/// okrążenie tak — zgodnie z zachowaniem `recorder.py`.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gt7_engineer_mobile/engineer/telemetry_recorder.dart';
import 'package:gt7_engineer_mobile/telemetry/gt7_packet.dart';

class _Clock {
  double t = 0;
  double call() => t;
  void tick([double dt = 0.06]) => t += dt;
}

Gt7Packet _pkt(int lap, double x, double z, {int lastLapMs = -1}) {
  return Gt7Packet()
    ..currentLap = lap
    ..position = [x, 0, z]
    ..speedMps = 120 / 3.6
    ..throttle = 200
    ..wheelRotationRad = 0.1
    ..tyreTemp = [80, 80, 80, 80]
    ..fuelCapacity = 60
    ..currentFuel = 50
    ..lastLapMs = lastLapMs
    ..carCode = 42
    ..onTrack = true;
}

List<List<double>> _loop({int n = 40, double r = 200}) =>
    [for (var i = 0; i < n; i++) [r * cos(2 * pi * i / n), r * sin(2 * pi * i / n)]];

void main() {
  test('out-lap pominiety, mierzone okrazenie zapisane', () {
    final clk = _Clock();
    final rec = TelemetryRecorder(RecordingConfig(), clock: clk.call);
    final pts = _loop();

    // Okrazenie wyjazdowe (lap 0).
    for (final p in pts) {
      rec.update(_pkt(0, p[0], p[1]));
      clk.tick();
    }
    // Przeciecie 0 -> 1 (out-lap NIE zapisany).
    final s1 = rec.update(_pkt(1, pts[0][0], pts[0][1]));
    clk.tick();
    expect(s1, isNull);

    // Okrazenie 1 (pelne).
    for (final p in pts) {
      rec.update(_pkt(1, p[0], p[1]));
      clk.tick();
    }
    // Przeciecie 1 -> 2 z czasem 95.000 -> zapis okrazenia 1.
    final saved = rec.update(_pkt(2, pts[0][0], pts[0][1], lastLapMs: 95000));

    expect(saved, isNotNull);
    expect(saved!.data['lap_ms'], 95000);
    expect(saved.data['lap_number'], 1);
    expect(saved.data['car_code'], 42);
    expect((saved.data['samples'] as List).length, greaterThanOrEqualTo(2));
    expect('${saved.data['track_key']}'.startsWith('L'), isTrue);
    expect(saved.filename.endsWith('95000ms.json'), isTrue);
  });
}

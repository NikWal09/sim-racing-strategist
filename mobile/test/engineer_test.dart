/// Test integracyjny inżyniera: po przejechaniu mierzonego okrążenia powstaje
/// komunikat o czasie/najlepszym okrążeniu; pierwszy pakiet daje "połączono".
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gt7_engineer_mobile/engineer/engineer_config.dart';
import 'package:gt7_engineer_mobile/engineer/race_engineer.dart';
import 'package:gt7_engineer_mobile/telemetry/gt7_packet.dart';

class _Clock {
  double t = 0;
  double call() => t;
  void tick([double dt = 0.06]) => t += dt;
}

Gt7Packet _pkt(int lap, double x, double z,
    {int lastLapMs = -1,
    int bestLapMs = -1,
    double speedKph = 120,
    int throttle = 255}) {
  return Gt7Packet()
    ..currentLap = lap
    ..totalLaps = 10
    ..position = [x, 0, z]
    ..velocity = [speedKph / 3.6, 0, 0]
    ..speedMps = speedKph / 3.6
    ..throttle = throttle
    ..wheelRotationRad = 0.1
    ..tyreTemp = [80, 80, 80, 80]
    ..fuelCapacity = 60
    ..currentFuel = 50
    ..lastLapMs = lastLapMs
    ..bestLapMs = bestLapMs
    ..carCode = 42
    ..onTrack = true
    ..positionInRace = 3
    ..totalCars = 12;
}

List<List<double>> _loop({int n = 40, double r = 200}) =>
    [for (var i = 0; i < n; i++) [r * cos(2 * pi * i / n), r * sin(2 * pi * i / n)]];

void main() {
  test('pierwszy pakiet na torze -> komunikat polaczenia', () {
    final clk = _Clock();
    final eng = RaceEngineer(EngineerConfig(), clock: clk.call);
    final out = eng.update(_pkt(1, 200, 0));
    expect(out, isNotEmpty);
  });

  test('mierzone okrazenie -> komunikat czasu (key lap_time)', () {
    final clk = _Clock();
    final eng = RaceEngineer(EngineerConfig(), clock: clk.call);
    final pts = _loop();

    eng.update(_pkt(1, pts[0][0], pts[0][1])); // polaczenie, start okr. 1
    clk.tick();
    for (final p in pts) {
      eng.update(_pkt(1, p[0], p[1]));
      clk.tick();
    }
    // Przeciecie linii 1 -> 2 z czasem 95.000 (i nowy najlepszy).
    final out =
        eng.update(_pkt(2, pts[0][0], pts[0][1], lastLapMs: 95000, bestLapMs: 95000));

    expect(out.any((a) => a.key == 'lap_time'), isTrue);
  });
}

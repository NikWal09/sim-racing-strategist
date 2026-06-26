/// Symulator telemetrii GT7 — tryb demo bez konsoli.
///
/// Generuje syntetyczne pakiety [Gt7Packet] z czestotliwoscia ~30 Hz, naladujac
/// realistyczny przejazd po owalnym torze: zmienna predkosc, RPM i biegi, ubywa
/// paliwo, rosna temperatury opon, naliczaja sie okrazenia i czasy. Sluzy do
/// podgladu i testow dashboardu / mowy, zanim podlaczymy prawdziwe PS5.
library;

import 'dart:async';
import 'dart:math';

import 'gt7_packet.dart';
import 'telemetry_source.dart';

class TelemetrySimulator implements TelemetrySource {
  TelemetrySimulator({this.hz = 30});

  final int hz;

  final StreamController<Gt7Packet> _controller =
      StreamController<Gt7Packet>.broadcast();
  Timer? _timer;
  double _t = 0.0; // czas symulacji [s]
  int _lap = 1;
  double _lapStart = 0.0;
  int _lastLapMs = -1;
  int _bestLapMs = -1;
  double _fuel = 60.0;
  final List<double> _tyre = [80, 80, 80, 80];

  // Owalny tor ~2 km: parametry do pozycji i "ksztaltu" predkosci.
  static const double _lapSeconds = 95.0; // ~1:35 na okrazenie

  @override
  Stream<Gt7Packet> get packets => _controller.stream;

  @override
  bool get isRunning => _timer != null;

  @override
  String get label => 'Tryb demo (symulator)';

  @override
  Future<void> start() async {
    if (_timer != null) return;
    final dt = 1.0 / hz;
    _timer = Timer.periodic(
      Duration(milliseconds: (1000 / hz).round()),
      (_) => _tick(dt),
    );
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _controller.close();
  }

  void _tick(double dt) {
    _t += dt;
    final phase = ((_t - _lapStart) / _lapSeconds).clamp(0.0, 1.0);
    final ang = 2 * pi * phase;

    // Predkosc: dwa proste + dwa zakrety (sinus), 80..260 km/h.
    final speedKph = 170 + 90 * sin(ang * 2 - pi / 2);
    final speedMps = speedKph / 3.6;

    // Pozycja na owalu (do przyszlej mapy toru).
    const rx = 500.0, rz = 300.0;
    final x = rx * cos(ang);
    final z = rz * sin(ang);

    // Bieg i RPM z predkosci (prosty model skrzyni 6-biegowej).
    final gear = (1 + (speedKph / 45)).clamp(1, 6).floor();
    final gearTop = gear * 45.0;
    final rpm = 2500 + 5500 * ((speedKph % 45) / 45).clamp(0.0, 1.0) +
        (speedKph > gearTop ? 800 : 0);

    // Gaz/hamulec z trendu predkosci.
    final accel = cos(ang * 2 - pi / 2);
    final throttle = (accel > 0 ? 180 + 75 * accel : 40).clamp(0, 255).round();
    final brake = (accel < -0.3 ? -180 * accel : 0).clamp(0, 255).round();

    // Kierownica: skret w zakretach.
    final steer = 0.4 * sin(ang * 2);

    // Paliwo ubywa, opony sie grzeja (mocniej w zakretach).
    _fuel = (_fuel - dt * 0.02).clamp(0.0, 60.0);
    final heat = 0.15 * (0.5 + 0.5 * sin(ang * 2).abs());
    for (var i = 0; i < 4; i++) {
      final target = 88 + (i % 2 == 0 ? 6 : 0) + 8 * sin(ang * 2).abs();
      _tyre[i] += (target - _tyre[i]) * heat * dt;
    }

    // Domkniecie okrazenia.
    if (phase >= 1.0) {
      _lastLapMs = ((_t - _lapStart) * 1000).round();
      if (_bestLapMs < 0 || _lastLapMs < _bestLapMs) _bestLapMs = _lastLapMs;
      _lap++;
      _lapStart = _t;
    }

    final p = Gt7Packet()
      ..position = [x, 0.0, z]
      ..velocity = [speedMps, 0, 0]
      ..speedMps = speedMps
      ..rpm = rpm.toDouble()
      ..currentFuel = _fuel
      ..fuelCapacity = 60.0
      ..gear = gear
      ..suggestedGear = 15
      ..throttle = throttle
      ..brake = brake
      ..wheelRotationRad = steer
      ..tyreTemp = [_tyre[0], _tyre[1], _tyre[2], _tyre[3]]
      ..currentLap = _lap
      ..totalLaps = 10
      ..lastLapMs = _lastLapMs
      ..bestLapMs = _bestLapMs
      ..positionInRace = 3
      ..totalCars = 12
      ..rpmAlertMin = 7000
      ..rpmAlertMax = 7800
      ..calcMaxSpeed = 280
      ..carCode = 1234
      ..onTrack = true;

    _controller.add(p);
  }
}

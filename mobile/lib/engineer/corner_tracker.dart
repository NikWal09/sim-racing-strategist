/// Auto-wykrywanie zakrętów i temperatury opon na każdym z nich — port
/// `gt7_engineer/engineer/corners.py`.
///
/// Sygnał "skręcam" z dwóch źródeł: kąt kierownicy (format B/~) oraz prędkość
/// kątowa toru jazdy (yaw) liczona ze zmiany wektora prędkości (każdy format).
/// Każdy zakręt dostaje numer, a dla każdego pamiętamy najwyższą temperaturę
/// opony i którą. Histereza wejścia/wyjścia zapobiega liczeniu zakrętu kilka razy.
library;

import 'dart:math' as math;

class CornerTracker {
  static const double enterSteerRad = 0.06;
  static const double exitSteerRad = 0.03;
  static const double enterYawDps = 14.0;
  static const double exitYawDps = 7.0;
  static const double minSpeedMps = 8.0;
  static const double minEnterS = 0.20;
  static const double minExitS = 0.45;
  static const double maxDtS = 0.5;

  double? _lastT;
  double? _heading;
  bool inCorner = false;
  double? _enterSince;
  double? _exitSince;
  int curCornerIdx = 0;
  double _curPeak = 0;
  int _curTyre = 0;
  final List<double> cornerPeak = [];
  final List<int> cornerTyre = [];
  int cornerCount = 0;
  int completedLaps = 0;
  (int, int, double)? _justFinished;

  CornerTracker() {
    reset();
  }

  void reset() {
    _lastT = null;
    _heading = null;
    inCorner = false;
    _enterSince = null;
    _exitSince = null;
    curCornerIdx = 0;
    _curPeak = 0;
    _curTyre = 0;
    cornerPeak.clear();
    cornerTyre.clear();
    cornerCount = 0;
    completedLaps = 0;
    _justFinished = null;
  }

  void update(List<double> pos, List<double> vel, double speedMps,
      double steerRad, List<double> tyreTemp, double now) {
    var yawDps = 0.0;
    double? dt = _lastT == null ? null : now - _lastT!;
    if (dt != null && (dt <= 0 || dt > maxDtS)) {
      _heading = null;
      dt = null;
    }
    _lastT = now;

    if (speedMps >= minSpeedMps && (vel[0].abs() + vel[2].abs()) > 1e-3) {
      final heading = math.atan2(vel[2], vel[0]);
      if (_heading != null && dt != null && dt != 0) {
        var d = heading - _heading!;
        while (d > math.pi) {
          d -= 2 * math.pi;
        }
        while (d < -math.pi) {
          d += 2 * math.pi;
        }
        yawDps = (d * 180 / math.pi / dt).abs();
      }
      _heading = heading;
    }

    final steer = steerRad.abs();
    final turnStrong = steer >= enterSteerRad || yawDps >= enterYawDps;
    final turnWeak = steer >= exitSteerRad || yawDps >= exitYawDps;

    if (!inCorner) {
      if (turnStrong) {
        _enterSince ??= now;
        if (now - _enterSince! >= minEnterS) _beginCorner();
      } else {
        _enterSince = null;
      }
    } else {
      _accumulate(tyreTemp);
      if (!turnWeak) {
        _exitSince ??= now;
        if (now - _exitSince! >= minExitS) _endCorner();
      } else {
        _exitSince = null;
      }
    }
  }

  void _beginCorner() {
    inCorner = true;
    _enterSince = null;
    _exitSince = null;
    curCornerIdx += 1;
    _curPeak = 0;
    _curTyre = 0;
  }

  void _accumulate(List<double> tyreTemp) {
    var idx = 0;
    for (var i = 1; i < 4; i++) {
      if (tyreTemp[i] > tyreTemp[idx]) idx = i;
    }
    final t = tyreTemp[idx];
    if (t > _curPeak) {
      _curPeak = t;
      _curTyre = idx;
    }
  }

  void _endCorner() {
    inCorner = false;
    _exitSince = null;
    final i = curCornerIdx - 1;
    if (i < 0) return;
    while (cornerPeak.length <= i) {
      cornerPeak.add(0);
      cornerTyre.add(0);
    }
    if (_curPeak > 0) {
      if (cornerPeak[i] > 0) {
        cornerPeak[i] = 0.6 * cornerPeak[i] + 0.4 * _curPeak;
      } else {
        cornerPeak[i] = _curPeak;
      }
      cornerTyre[i] = _curTyre;
    }
    _justFinished = (curCornerIdx, _curTyre, _curPeak);
  }

  void onLapComplete() {
    if (inCorner) _endCorner();
    if (curCornerIdx > 0) {
      cornerCount = curCornerIdx;
      completedLaps += 1;
    }
    curCornerIdx = 0;
    inCorner = false;
    _enterSince = null;
    _exitSince = null;
    _curPeak = 0;
    _curTyre = 0;
    _heading = null;
  }

  (int, int, double)? popJustFinished() {
    final jf = _justFinished;
    _justFinished = null;
    return jf;
  }

  (int, int, double)? hottestCorner() {
    if (completedLaps < 1 || !cornerPeak.any((v) => v > 0)) return null;
    var i = 0;
    for (var k = 1; k < cornerPeak.length; k++) {
      if (cornerPeak[k] > cornerPeak[i]) i = k;
    }
    return (i + 1, cornerTyre[i], cornerPeak[i]);
  }
}

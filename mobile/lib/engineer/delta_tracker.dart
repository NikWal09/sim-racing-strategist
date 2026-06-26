/// Delta do najlepszego okrążenia — liczona po POZYCJI na torze (port
/// `gt7_engineer/engineer/delta.py`).
///
/// Najlepsze okrążenie zapamiętujemy jako ślad próbek (x, y, z, czas_od_startu).
/// Dla bieżącej pozycji znajdujemy najbliższy punkt śladu (z rzutem na odcinek)
/// i odczytujemy czas referencyjny w tym miejscu. Delta = czas_teraz - czas_ref.
/// Ujemna = jedziesz szybciej. Komunikat czytamy tylko na prostej.
library;

import 'dart:math' as math;

class Sample {
  const Sample(this.x, this.y, this.z, this.t);
  final double x, y, z, t;
}

class DeltaTracker {
  DeltaTracker([this.minDeltaS = 0.15]) {
    reset();
  }

  double minDeltaS;

  static const double sampleEveryM = 5.0;
  static const int straightThrottle = 218;
  static const double straightMinSpeedKph = 90.0;
  static const double straightMinDurationS = 0.6;
  static const double straightMaxSteerRad = 0.12;
  static const double outlapMinStartKph = 60.0;
  static const double stoppedKph = 12.0;
  static const int searchBack = 5;
  static const int searchAhead = 150;

  double? _lastT;
  double? lapStartT;
  double lapDistance = 0;
  double _lastSampleDist = -1e9;
  List<Sample> curSamples = [];
  List<Sample>? ref;
  int? refMs;
  double? _curDelta;
  int _refIdx = 0;
  bool curValid = false;
  int _curLapNo = 0;
  double? _straightSince;
  bool _announcedOnStraight = false;

  void reset() {
    _lastT = null;
    lapStartT = null;
    lapDistance = 0;
    _lastSampleDist = -1e9;
    curSamples = [];
    ref = null;
    refMs = null;
    _curDelta = null;
    _refIdx = 0;
    curValid = false;
    _curLapNo = 0;
    _straightSince = null;
    _announcedOnStraight = false;
  }

  void startLap(double now, {double speedMps = 0, int lapNo = 0}) {
    lapStartT = now;
    lapDistance = 0;
    _lastSampleDist = -1e9;
    curSamples = [];
    _refIdx = 0;
    _curLapNo = lapNo;
    curValid = lapNo >= 2 && speedMps * 3.6 >= outlapMinStartKph;
  }

  void update(List<double> pos, double speedMps, double now, {int lapNo = 0}) {
    _curLapNo = lapNo;
    if (_lastT != null && lapStartT != null) {
      final dt = now - _lastT!;
      if (dt > 0) lapDistance += math.max(0.0, speedMps) * dt;
    }
    _lastT = now;

    if (speedMps * 3.6 < stoppedKph) curValid = false;

    if (lapStartT != null) {
      if (lapDistance - _lastSampleDist >= sampleEveryM) {
        curSamples.add(Sample(pos[0], pos[1], pos[2], now - lapStartT!));
        _lastSampleDist = lapDistance;
      }
    }
    _curDelta = _computeDelta(pos, now);
  }

  void onLapComplete(int lastLapMs, double now,
      {double speedMps = 0, int lapNo = 0}) {
    if (curValid && curSamples.isNotEmpty && lastLapMs > 0) {
      if (refMs == null || lastLapMs < refMs!) {
        ref = curSamples;
        refMs = lastLapMs;
      }
    }
    startLap(now, speedMps: speedMps, lapNo: lapNo);
  }

  double? currentDelta() => _curDelta;

  double? _computeDelta(List<double> pos, double now) {
    if (ref == null || ref!.isEmpty || lapStartT == null || _curLapNo < 2) {
      return null;
    }
    final refT = _refTimeAt(pos);
    if (refT == null) return null;
    return (now - lapStartT!) - refT;
  }

  double? _refTimeAt(List<double> pos) {
    final r = ref;
    if (r == null || r.length < 2) return null;
    final n = r.length;
    final i = _nearestInWindow(r, pos, n);
    _refIdx = i;
    double? bestD2;
    double bestT = r[i].t;
    for (final j in [i - 1, i]) {
      if (j >= 0 && j < n - 1) {
        final pr = _projSeg(pos, r[j], r[j + 1]);
        final t = r[j].t + pr.frac * (r[j + 1].t - r[j].t);
        if (bestD2 == null || pr.d2 < bestD2) {
          bestD2 = pr.d2;
          bestT = t;
        }
      }
    }
    return bestT;
  }

  int _nearestInWindow(List<Sample> r, List<double> pos, int n) {
    final px = pos[0], py = pos[1], pz = pos[2];
    final lo = math.max(0, _refIdx - searchBack);
    var hi = math.min(n, _refIdx + searchAhead);
    var bestI = lo;
    var best = double.infinity;
    for (var i = lo; i < hi; i++) {
      final s = r[i];
      final dx = s.x - px, dy = s.y - py, dz = s.z - pz;
      final d2 = dx * dx + dy * dy + dz * dz;
      if (d2 < best) {
        best = d2;
        bestI = i;
      }
    }
    if (bestI >= hi - 1 && hi < n) {
      final hi2 = math.min(n, bestI + searchAhead);
      for (var i = hi; i < hi2; i++) {
        final s = r[i];
        final dx = s.x - px, dy = s.y - py, dz = s.z - pz;
        final d2 = dx * dx + dy * dy + dz * dz;
        if (d2 < best) {
          best = d2;
          bestI = i;
        }
      }
    }
    return bestI;
  }

  ({double frac, double d2}) _projSeg(List<double> pos, Sample a, Sample b) {
    final px = pos[0], py = pos[1], pz = pos[2];
    final vx = b.x - a.x, vy = b.y - a.y, vz = b.z - a.z;
    final seg2 = vx * vx + vy * vy + vz * vz;
    if (seg2 <= 1e-9) {
      final dx = px - a.x, dy = py - a.y, dz = pz - a.z;
      return (frac: 0.0, d2: dx * dx + dy * dy + dz * dz);
    }
    var t = ((px - a.x) * vx + (py - a.y) * vy + (pz - a.z) * vz) / seg2;
    t = t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);
    final cx = a.x + t * vx, cy = a.y + t * vy, cz = a.z + t * vz;
    final dx = px - cx, dy = py - cy, dz = pz - cz;
    return (frac: t, d2: dx * dx + dy * dy + dz * dz);
  }

  // --- Wykrywanie prostej (bramka na komunikat) ---

  void updateStraight(int throttle, double steerRad, double speedKph, double now) {
    final steerOk = steerRad == 0.0 || steerRad.abs() <= straightMaxSteerRad;
    final straightNow = throttle >= straightThrottle &&
        speedKph >= straightMinSpeedKph &&
        steerOk;
    if (straightNow) {
      _straightSince ??= now;
    } else {
      _straightSince = null;
      _announcedOnStraight = false;
    }
  }

  bool canAnnounceStraight(double now) {
    if (_straightSince == null || _announcedOnStraight) return false;
    return now - _straightSince! >= straightMinDurationS;
  }

  void markAnnounced() => _announcedOnStraight = true;
}

/// Metadane wczytanej referencji (do UI i komunikatów).
class ReferenceInfo {
  ReferenceInfo({
    required this.carCode,
    required this.carName,
    required this.lapTime,
    required this.lapMs,
    required this.trackKey,
  });
  final int? carCode;
  final String carName;
  final String lapTime;
  final int lapMs;
  final String trackKey;
}

/// DeltaTracker ze STAŁĄ referencją z nagrania + sektory — port `reference.py`.
///
/// Różnice względem bazy: referencja nigdy nie jest nadpisywana najszybszym
/// kółkiem sesji; po przekroczeniu granicy sektora wystawia wynik sektora
/// (zmiana delty od początku sektora). Musi być w tej samej bibliotece co
/// [DeltaTracker], by sięgać do jego prywatnych pól (_curDelta, _refIdx).
class ReferenceDelta extends DeltaTracker {
  ReferenceDelta({double minDeltaS = 0.15, int sectors = 3})
      : sectors = math.max(1, sectors),
        super(minDeltaS);

  final int sectors;
  ReferenceInfo? info;
  List<int> _sectorBounds = [];
  int _sector = 0;
  double? _sectorStartDelta;
  (int, double)? _pendingSector;

  static const double resampleM = DeltaTracker.sampleEveryM;

  @override
  void reset() {
    // Referencja pochodzi z pliku i ma przetrwać resety (zmiana auta itd.) —
    // usuwa ją tylko clear(). Dlatego zachowujemy ref/refMs wokół super.reset().
    final keepRef = ref;
    final keepMs = refMs;
    super.reset();
    ref = keepRef;
    refMs = keepMs;
    _sector = 0;
    _sectorStartDelta = null;
    _pendingSector = null;
  }

  bool get loaded => ref != null && info != null;

  /// Ustawia nagrane okrążenie (mapa JSON recordera) jako referencję.
  /// Rzuca [ArgumentError], gdy nagranie jest niepoprawne.
  ReferenceInfo loadFromData(Map<String, dynamic> data) {
    final channels = (data['channels'] as List?)?.cast<String>() ?? const [];
    final rawSamples = (data['samples'] as List?) ?? const [];
    final lapMs = (data['lap_ms'] as num?)?.toInt() ?? 0;
    final it = channels.indexOf('t');
    final ix = channels.indexOf('x');
    final iy = channels.indexOf('y');
    final iz = channels.indexOf('z');
    if (it < 0 || ix < 0 || iy < 0 || iz < 0) {
      throw ArgumentError('Nagranie bez kanałów pozycji.');
    }
    if (rawSamples.length < 2 || lapMs <= 0) {
      throw ArgumentError('Nagranie nie zawiera pełnego okrążenia z czasem.');
    }
    final pts = <Sample>[
      for (final s in rawSamples)
        Sample((s[ix] as num).toDouble(), (s[iy] as num).toDouble(),
            (s[iz] as num).toDouble(), (s[it] as num).toDouble())
    ];
    final r = _resample(pts);
    if (r.length < 2) throw ArgumentError('Za mało próbek po przepróbkowaniu.');

    reset();
    ref = r;
    refMs = lapMs;
    _sectorBounds = _makeSectorBounds(r);
    info = ReferenceInfo(
      carCode: (data['car_code'] as num?)?.toInt(),
      carName: '${data['car_name'] ?? 'Auto ${data['car_code']}'}',
      lapTime: '${data['lap_time'] ?? '?'}',
      lapMs: lapMs,
      trackKey: '${data['track_key'] ?? '?'}',
    );
    return info!;
  }

  static List<Sample> _resample(List<Sample> pts) {
    final out = <Sample>[pts.first];
    for (var i = 1; i < pts.length; i++) {
      final p = pts[i];
      final last = out.last;
      final d = math.sqrt(math.pow(p.x - last.x, 2) +
          math.pow(p.y - last.y, 2) +
          math.pow(p.z - last.z, 2));
      if (d >= resampleM) out.add(p);
    }
    return out;
  }

  List<int> _makeSectorBounds(List<Sample> r) {
    final totalT = r.last.t;
    final bounds = <int>[];
    var k = 1;
    for (var i = 0; i < r.length; i++) {
      if (k >= sectors) break;
      if (r[i].t >= totalT * k / sectors) {
        bounds.add(i);
        k++;
      }
    }
    return bounds;
  }

  void clear() {
    info = null;
    _sectorBounds = [];
    ref = null;
    refMs = null;
    reset();
  }

  @override
  void onLapComplete(int lastLapMs, double now,
      {double speedMps = 0, int lapNo = 0}) {
    // NIE nadpisujemy referencji; ostatni sektor kończy się na linii mety.
    (int, double)? pending;
    if (_sectorBounds.isNotEmpty &&
        _sector >= _sectorBounds.length &&
        _curDelta != null &&
        _sectorStartDelta != null) {
      pending = (sectors, _curDelta! - _sectorStartDelta!);
    }
    startLap(now, speedMps: speedMps, lapNo: lapNo);
    if (pending != null) _pendingSector = pending;
  }

  @override
  void startLap(double now, {double speedMps = 0, int lapNo = 0}) {
    super.startLap(now, speedMps: speedMps, lapNo: lapNo);
    _sector = 0;
    _sectorStartDelta = null;
    _pendingSector = null;
  }

  @override
  void update(List<double> pos, double speedMps, double now, {int lapNo = 0}) {
    super.update(pos, speedMps, now, lapNo: lapNo);
    _checkSector();
  }

  void _checkSector() {
    if (_sectorBounds.isEmpty) return;
    final d = _curDelta;
    if (d != null && _sectorStartDelta == null) _sectorStartDelta = d;
    if (_sector >= _sectorBounds.length) return;
    if (_refIdx >= _sectorBounds[_sector]) {
      final sectorNo = _sector + 1;
      _sector++;
      if (d != null && _sectorStartDelta != null) {
        _pendingSector = (sectorNo, d - _sectorStartDelta!);
      }
      _sectorStartDelta = d;
    }
  }

  /// (numer_sektora 1.., zmiana_delty[s]) ostatnio zamkniętego sektora.
  /// Dodatnia = strata do referencji. null, gdy nic się nie zamknęło.
  (int, double)? popSectorResult() {
    final r = _pendingSector;
    _pendingSector = null;
    return r;
  }
}

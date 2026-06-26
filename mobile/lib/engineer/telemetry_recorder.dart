/// Nagrywanie telemetrii per-okrążenie (w stylu Garage 61) — port
/// `gt7_engineer/engineer/recorder.py`.
///
/// Buforuje próbki bieżącego okrążenia i po przecięciu linii start/meta zwraca
/// gotowe dane poprawnego okrążenia (mapę JSON + sugerowaną nazwę pliku). Zapis
/// na dysk robi [RecordingStore]. Segmentacja jak w analyzerze: liczymy na
/// inkrementach current_lap, a pit/cofnięcie licznika/zmiana auta unieważnia bufor.
library;

import 'dart:math' as math;

import '../telemetry/gt7_packet.dart';

/// Kanały zapisywane dla każdej próbki (kolejność = kolejność w wierszu samples).
const List<String> recorderChannels = [
  't', 'x', 'y', 'z', 'speed_kph', 'throttle', 'brake', 'steering', 'gear',
  'rpm', 'tyre_fl', 'tyre_fr', 'tyre_rl', 'tyre_rr', 'fuel_pct',
];

/// Konfiguracja nagrywania (odpowiednik RecordingConfig).
class RecordingConfig {
  RecordingConfig({
    this.enabled = true,
    this.sampleHz = 20.0,
    this.minLapSeconds = 10.0,
  });
  bool enabled;
  double sampleHz;
  double minLapSeconds;
}

class _LapBuffer {
  _LapBuffer({this.startT = 0.0, this.clean = false});
  double startT;
  bool clean;
  final List<List<num>> samples = [];
  double lastSampleT = -1e9;
}

/// Wynik zamknięcia okrążenia gotowy do zapisu.
class RecordedLap {
  RecordedLap(this.data, this.filename);
  final Map<String, dynamic> data;
  final String filename;
}

class TelemetryRecorder {
  TelemetryRecorder(this.cfg, {double Function()? clock})
      : _clock = clock ?? (() => DateTime.now().microsecondsSinceEpoch / 1e6) {
    _minDt = cfg.sampleHz > 0 ? 1.0 / cfg.sampleHz : 0.0;
    _sessionId = _stamp();
  }

  final RecordingConfig cfg;
  final double Function() _clock;

  static const double fuelRefillEps = 0.05;
  static const double pitReturnMaxKph = 5.0;

  double _minDt = 0.05;
  _LapBuffer _buf = _LapBuffer();
  int? _curLap;
  int? _carCode;
  double? _lastFuel;
  late String _sessionId;

  String _stamp() {
    final n = DateTime.now();
    String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
    return '${n.year}${p(n.month)}${p(n.day)}_${p(n.hour)}${p(n.minute)}${p(n.second)}';
  }

  /// Wywołuj co pakiet. Zwraca dane okrążenia, gdy właśnie zamknięto poprawne
  /// okrążenie; w przeciwnym razie null.
  RecordedLap? update(Gt7Packet p) {
    if (!cfg.enabled) return null;
    if (p.paused || p.loading) return null;

    if (!p.onTrack) {
      _invalidate();
      return null;
    }

    if (_carCode == null) {
      _carCode = p.carCode;
    } else if (p.carCode != _carCode) {
      _carCode = p.carCode;
      _sessionId = _stamp();
      _curLap = null;
      _invalidate();
      _lastFuel = null;
    }

    final now = _clock();

    if (_lastFuel != null &&
        p.fuelCapacity > 0 &&
        p.currentFuel > _lastFuel! + fuelRefillEps &&
        p.speedKph <= pitReturnMaxKph) {
      _invalidate();
    }
    _lastFuel = p.currentFuel;

    RecordedLap? saved;

    if (_curLap == null) {
      _curLap = p.currentLap;
      _startBuffer(now, false);
    } else if (p.currentLap < _curLap!) {
      _curLap = p.currentLap;
      _startBuffer(now, false);
    } else if (p.currentLap > _curLap!) {
      final completed = _buf;
      final prevLapNo = _curLap!;
      _curLap = p.currentLap;
      if (_isSaveable(completed, p.lastLapMs)) {
        saved = _buildLap(completed, p.lastLapMs, prevLapNo);
      }
      _startBuffer(now, true);
    }

    _sample(p, now);
    return saved;
  }

  void _startBuffer(double now, bool clean) {
    _buf = _LapBuffer(startT: now, clean: clean);
  }

  void _invalidate() {
    _buf = _LapBuffer(startT: _clock(), clean: false);
  }

  void _sample(Gt7Packet p, double now) {
    if (_minDt > 0 && (now - _buf.lastSampleT) < _minDt) return;
    _buf.lastSampleT = now;
    double r(double v, int d) {
      final f = math.pow(10, d);
      return (v * f).round() / f;
    }

    _buf.samples.add([
      r(now - _buf.startT, 3),
      r(p.position[0], 3), r(p.position[1], 3), r(p.position[2], 3),
      r(p.speedKph, 2),
      r(p.throttle / 255.0, 4),
      r(p.brake / 255.0, 4),
      r(p.wheelRotationRad, 4),
      p.gear,
      r(p.rpm, 1),
      r(p.tyreTemp[0], 1), r(p.tyreTemp[1], 1),
      r(p.tyreTemp[2], 1), r(p.tyreTemp[3], 1),
      r(p.fuelPct, 2),
    ]);
  }

  bool _isSaveable(_LapBuffer buf, int lastLapMs) {
    if (!buf.clean) return false;
    if (lastLapMs <= 0) return false;
    if (buf.samples.length < 2) return false;
    if (lastLapMs < cfg.minLapSeconds * 1000) return false;
    return true;
  }

  static Map<String, double> fingerprint(List<List<num>> samples) {
    const xi = 1, zi = 3;
    var length = 0.0;
    for (var i = 1; i < samples.length; i++) {
      final dx = samples[i][xi] - samples[i - 1][xi];
      final dz = samples[i][zi] - samples[i - 1][zi];
      length += math.sqrt(dx * dx + dz * dz);
    }
    final xs = samples.map((s) => s[xi]).toList();
    final zs = samples.map((s) => s[zi]).toList();
    double rmax(List<num> v) => v.reduce(math.max).toDouble();
    double rmin(List<num> v) => v.reduce(math.min).toDouble();
    double r1(double v) => (v * 10).round() / 10;
    return {
      'length_m': r1(length),
      'width_m': r1(rmax(xs) - rmin(xs)),
      'height_m': r1(rmax(zs) - rmin(zs)),
    };
  }

  static String trackKey(Map<String, double> fp) {
    final ln = (fp['length_m']! / 50.0).round() * 50;
    final w = (fp['width_m']! / 20.0).round() * 20;
    final h = (fp['height_m']! / 20.0).round() * 20;
    return 'L$ln-W$w-H$h';
  }

  RecordedLap _buildLap(_LapBuffer buf, int lastLapMs, int lapNo) {
    final fp = fingerprint(buf.samples);
    final key = trackKey(fp);
    final n = DateTime.now();
    String p2(int v) => v.toString().padLeft(2, '0');
    final recordedAt =
        '${n.year}-${p2(n.month)}-${p2(n.day)}T${p2(n.hour)}:${p2(n.minute)}:${p2(n.second)}';
    final data = <String, dynamic>{
      'session_id': _sessionId,
      'car_code': _carCode,
      'car_name': 'Auto $_carCode',
      'lap_number': lapNo,
      'lap_ms': lastLapMs,
      'lap_time': Gt7Packet.formatLaptime(lastLapMs),
      'recorded_at': recordedAt,
      'track_key': key,
      'fingerprint': fp,
      'sample_hz': cfg.sampleHz,
      'channels': recorderChannels,
      'samples': buf.samples,
    };
    final lapStr = lapNo.toString().padLeft(3, '0');
    final filename = '${_sessionId}_${key}_lap${lapStr}_${lastLapMs}ms.json';
    return RecordedLap(data, filename);
  }
}

/// Podgląd telemetrii nagranego okrążenia — natywny odpowiednik strony HTML
/// z desktopu (`tools/telemetry_viewer.py`).
///
/// Mapa toru (nitka) kolorowana prędkością + wykresy kanałów (prędkość, gaz,
/// hamulec, kierownica) względem dystansu okrążenia.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engineer/recording_store.dart';
import 'theme.dart';

class TelemetryViewerScreen extends StatefulWidget {
  const TelemetryViewerScreen({
    super.key,
    required this.store,
    required this.path,
    required this.title,
  });

  final RecordingStore store;
  final String path;
  final String title;

  @override
  State<TelemetryViewerScreen> createState() => _TelemetryViewerScreenState();
}

class _TelemetryViewerScreenState extends State<TelemetryViewerScreen> {
  Map<String, dynamic>? _lap;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final lap = await widget.store.loadFull(widget.path);
      if (!mounted) return;
      setState(() => _lap = lap);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _error != null
          ? Center(
              child: Text('Błąd: $_error',
                  style: const TextStyle(color: AppColors.danger)))
          : _lap == null
              ? const Center(child: CircularProgressIndicator())
              : _content(_lap!),
    );
  }

  Widget _content(Map<String, dynamic> lap) {
    final channels = (lap['channels'] as List).cast<String>();
    final samples = (lap['samples'] as List)
        .map((s) => (s as List).map((v) => (v as num).toDouble()).toList())
        .toList();
    int idx(String name) => channels.indexOf(name);
    final xi = idx('x'), zi = idx('z'), si = idx('speed_kph');
    final ti = idx('throttle'), bi = idx('brake'), wi = idx('steering');

    final speeds = [for (final s in samples) s[si]];

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mapa toru (nitka) kolorowana prędkością.
          Expanded(
            flex: 5,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.panel,
                border: Border.all(color: AppColors.stroke),
                borderRadius: BorderRadius.circular(11),
              ),
              padding: const EdgeInsets.all(8),
              child: CustomPaint(
                painter: _TrackPainter(samples, xi, zi, si),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Wykresy kanałów.
          Expanded(
            flex: 4,
            child: ListView(
              children: [
                _chart('Prędkość (km/h)', [for (final s in samples) s[si]],
                    AppColors.accent),
                _chart('Gaz', [for (final s in samples) s[ti]], AppColors.good,
                    minY: 0, maxY: 1),
                _chart('Hamulec', [for (final s in samples) s[bi]],
                    AppColors.danger,
                    minY: 0, maxY: 1),
                _chart('Kierownica', [for (final s in samples) s[wi]],
                    AppColors.accentRpm,
                    symmetric: true),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Vmax ${speeds.reduce(math.max).toStringAsFixed(0)} km/h · '
                    'próbek ${samples.length}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chart(String label, List<double> values, Color color,
      {double? minY, double? maxY, bool symmetric = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  color: AppColors.muted, fontSize: 11, letterSpacing: 1)),
          const SizedBox(height: 4),
          SizedBox(
            height: 56,
            child: CustomPaint(
              painter: _ChartPainter(values, color,
                  minY: minY, maxY: maxY, symmetric: symmetric),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rysuje ślad toru (x-z) kolorowany prędkością (niebieski -> czerwony).
class _TrackPainter extends CustomPainter {
  _TrackPainter(this.samples, this.xi, this.zi, this.si);
  final List<List<double>> samples;
  final int xi, zi, si;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;
    var minX = double.infinity, maxX = -double.infinity;
    var minZ = double.infinity, maxZ = -double.infinity;
    var minS = double.infinity, maxS = -double.infinity;
    for (final s in samples) {
      minX = math.min(minX, s[xi]);
      maxX = math.max(maxX, s[xi]);
      minZ = math.min(minZ, s[zi]);
      maxZ = math.max(maxZ, s[zi]);
      minS = math.min(minS, s[si]);
      maxS = math.max(maxS, s[si]);
    }
    final spanX = (maxX - minX).abs() < 1e-6 ? 1 : maxX - minX;
    final spanZ = (maxZ - minZ).abs() < 1e-6 ? 1 : maxZ - minZ;
    const pad = 10.0;
    final scale =
        math.min((size.width - 2 * pad) / spanX, (size.height - 2 * pad) / spanZ);
    final offX = (size.width - spanX * scale) / 2;
    final offZ = (size.height - spanZ * scale) / 2;

    Offset pt(List<double> s) => Offset(
          offX + (s[xi] - minX) * scale,
          // oś z w dół ekranu (odbicie, by mapa nie była "do góry nogami")
          size.height - (offZ + (s[zi] - minZ) * scale),
        );

    final spanS = (maxS - minS).abs() < 1e-6 ? 1 : maxS - minS;
    final paint = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < samples.length; i++) {
      final frac = ((samples[i][si] - minS) / spanS).clamp(0.0, 1.0);
      // niska prędkość = niebieski (hue 220), wysoka = czerwony (hue 0)
      paint.color = HSVColor.fromAHSV(1, 220 * (1 - frac), 0.85, 0.95).toColor();
      canvas.drawLine(pt(samples[i - 1]), pt(samples[i]), paint);
    }
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.samples != samples;
}

/// Prosty wykres liniowy kanału względem indeksu próbki.
class _ChartPainter extends CustomPainter {
  _ChartPainter(this.values, this.color,
      {this.minY, this.maxY, this.symmetric = false});
  final List<double> values;
  final Color color;
  final double? minY, maxY;
  final bool symmetric;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    double lo, hi;
    if (minY != null && maxY != null) {
      lo = minY!;
      hi = maxY!;
    } else if (symmetric) {
      final m = values.fold<double>(
          0, (a, b) => math.max(a, b.abs())).clamp(1e-6, double.infinity);
      lo = -m;
      hi = m;
    } else {
      lo = values.reduce(math.min);
      hi = values.reduce(math.max);
      if ((hi - lo).abs() < 1e-6) hi = lo + 1;
    }
    final span = hi - lo;

    // tło + linia zera (dla kierownicy)
    final bg = Paint()..color = const Color(0xFF0E1116);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)), bg);
    if (symmetric) {
      final yz = size.height - (0 - lo) / span * size.height;
      canvas.drawLine(Offset(0, yz), Offset(size.width, yz),
          Paint()..color = AppColors.stroke);
    }

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height -
          ((values[i] - lo) / span).clamp(0.0, 1.0) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6);
  }

  @override
  bool shouldRepaint(_ChartPainter old) => old.values != values;
}

/// Zegary dashboardu rysowane na canvasie (CustomPainter).
///
/// Zawiera poziomy pasek RPM (shift light) oraz par pasków pedałów. Kolory i
/// progi sa dobrane pod czytelnosc na telefonie lezacym obok kierownicy.
library;

import 'package:flutter/material.dart';

/// Poziomy pasek obrotow ze swiatlem zmiany biegu.
///
/// Wypelnienie 0..1 wg [rpm] / [maxRpm]. Powyzej [shiftFrac] segmenty robia sie
/// zolte, a przy [redlineFrac] - czerwone (sygnal do zmiany biegu).
class RpmBar extends StatelessWidget {
  const RpmBar({
    super.key,
    required this.rpm,
    required this.maxRpm,
    this.shiftFrac = 0.85,
    this.redlineFrac = 0.95,
    this.height = 26,
  });

  final double rpm;
  final double maxRpm;
  final double shiftFrac;
  final double redlineFrac;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _RpmBarPainter(
          frac: maxRpm > 0 ? (rpm / maxRpm).clamp(0.0, 1.0) : 0.0,
          shiftFrac: shiftFrac,
          redlineFrac: redlineFrac,
        ),
      ),
    );
  }
}

class _RpmBarPainter extends CustomPainter {
  _RpmBarPainter({
    required this.frac,
    required this.shiftFrac,
    required this.redlineFrac,
  });

  final double frac;
  final double shiftFrac;
  final double redlineFrac;

  static const int _segments = 24;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 3.0;
    final segW = (size.width - gap * (_segments - 1)) / _segments;
    final lit = (frac * _segments).round();

    for (var i = 0; i < _segments; i++) {
      final segFrac = (i + 1) / _segments;
      final on = i < lit;
      Color color;
      if (segFrac >= redlineFrac) {
        color = on ? Colors.redAccent : const Color(0xFF3A1414);
      } else if (segFrac >= shiftFrac) {
        color = on ? Colors.amber : const Color(0xFF3A3014);
      } else {
        color = on ? Colors.greenAccent : const Color(0xFF14331F);
      }
      final left = i * (segW + gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, 0, segW, size.height),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_RpmBarPainter old) =>
      old.frac != frac ||
      old.shiftFrac != shiftFrac ||
      old.redlineFrac != redlineFrac;
}

/// Pionowy pasek pedalu (gaz/hamulec), wartosc 0..1.
class PedalBar extends StatelessWidget {
  const PedalBar({
    super.key,
    required this.value,
    required this.color,
    required this.label,
  });

  final double value;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 22,
          height: 80,
          child: CustomPaint(
            painter: _PedalPainter(value: value.clamp(0.0, 1.0), color: color),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
      ],
    );
  }
}

class _PedalPainter extends CustomPainter {
  _PedalPainter({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(4),
    );
    canvas.drawRRect(bg, Paint()..color = const Color(0xFF1E1E1E));
    final h = size.height * value;
    final fill = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, size.height - h, size.width, h),
      const Radius.circular(4),
    );
    canvas.drawRRect(fill, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PedalPainter old) =>
      old.value != value || old.color != color;
}

/// Okragly zegar (CustomPainter) — port klasy CircularGauge z desktopu
/// (`gt7_gui_qt.py`). Luk otwarty na dole: start w pozycji ~7:30, 270° zgodnie
/// z ruchem wskazowek przez gore do ~4:30. Opcjonalna czerwona strefa (redline).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

class CircularGauge extends StatelessWidget {
  const CircularGauge({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    this.color = AppColors.accent,
    this.redlineFrac = 0.0,
  });

  final String label;
  final double value;
  final double max;
  final Color color;
  final double redlineFrac;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _GaugePainter(
          label: label,
          value: value,
          max: max < 1 ? 1 : max,
          color: color,
          redlineFrac: redlineFrac.clamp(0.0, 1.0),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.label,
    required this.value,
    required this.max,
    required this.color,
    required this.redlineFrac,
  });

  final String label;
  final double value;
  final double max;
  final Color color;
  final double redlineFrac;

  // Geometria luku (odpowiednik START_ANGLE=225 / FULL_SPAN=-270 z Qt).
  static const double _start = 135 * math.pi / 180; // ~7:30
  static const double _sweep = 270 * math.pi / 180; // 270° przez gore
  static const double _stroke = 13;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    const margin = 18.0;
    final r = (side - 2 * margin) / 2;
    final c = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: c, radius: r);

    // Tlo luku.
    canvas.drawArc(
      rect,
      _start,
      _sweep,
      false,
      Paint()
        ..color = AppColors.gaugeTrack
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round,
    );

    // Czerwona strefa (redline) na tle skali. strokeCap.round - żeby koniec
    // strefy sięgał dokładnie do zaokrąglonego końca łuku tła (inaczej zostaje
    // szary ogonek za czerwienią).
    if (redlineFrac > 0) {
      canvas.drawArc(
        rect,
        _start + _sweep * redlineFrac,
        _sweep * (1 - redlineFrac),
        false,
        Paint()
          ..color = AppColors.danger.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    // Podzialka: 9 kresek co 1/8 skali.
    final tickPaint = Paint()
      ..color = AppColors.tick
      ..strokeWidth = 2;
    for (var i = 0; i < 9; i++) {
      final a = _start + _sweep * (i / 8);
      final r1 = r - 18, r2 = r - 11;
      canvas.drawLine(
        Offset(c.dx + r1 * math.cos(a), c.dy + r1 * math.sin(a)),
        Offset(c.dx + r2 * math.cos(a), c.dy + r2 * math.sin(a)),
        tickPaint,
      );
    }

    // Luk wartosci (czerwienieje w strefie redline).
    final frac = (value / max).clamp(0.0, 1.0);
    final inRed = redlineFrac > 0 && frac >= redlineFrac;
    canvas.drawArc(
      rect,
      _start,
      _sweep * frac,
      false,
      Paint()
        ..color = inRed ? AppColors.danger : color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round,
    );

    // Wartosc (liczba).
    _text(
      canvas,
      value.toStringAsFixed(0),
      c.translate(0, -r * 0.08),
      TextStyle(
        color: inRed ? const Color(0xFFFF6E63) : Colors.white,
        fontSize: r * 0.42,
        fontWeight: FontWeight.bold,
      ),
    );

    // Etykieta.
    _text(
      canvas,
      label,
      c.translate(0, r * 0.42),
      const TextStyle(color: AppColors.muted, fontSize: 13),
    );
  }

  void _text(Canvas canvas, String s, Offset center, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value ||
      old.max != max ||
      old.color != color ||
      old.redlineFrac != redlineFrac ||
      old.label != label;
}

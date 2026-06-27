/// Okragly zegar (CustomPainter). Luk otwarty na dole: start ~7:30, 270° przez
/// gore. Opcjonalna czerwona strefa (redline). Kolory pochodzą ze skórki
/// dashboardu (przekazywane jawnie), z poświatą (glow) dla skórek neonowych.
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
    this.track = AppColors.gaugeTrack,
    this.tick = AppColors.tick,
    this.textColor = Colors.white,
    this.mutedColor = AppColors.muted,
    this.danger = AppColors.danger,
    this.glow = false,
  });

  final String label;
  final double value;
  final double max;
  final Color color;
  final double redlineFrac;
  final Color track, tick, textColor, mutedColor, danger;
  final bool glow;

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
          track: track,
          tick: tick,
          textColor: textColor,
          mutedColor: mutedColor,
          danger: danger,
          glow: glow,
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
    required this.track,
    required this.tick,
    required this.textColor,
    required this.mutedColor,
    required this.danger,
    required this.glow,
  });

  final String label;
  final double value;
  final double max;
  final Color color;
  final double redlineFrac;
  final Color track, tick, textColor, mutedColor, danger;
  final bool glow;

  static const double _start = 135 * math.pi / 180;
  static const double _sweep = 270 * math.pi / 180;
  static const double _stroke = 13;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    const margin = 18.0;
    final r = (side - 2 * margin) / 2;
    final c = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: c, radius: r);

    canvas.drawArc(
      rect,
      _start,
      _sweep,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round,
    );

    if (redlineFrac > 0) {
      canvas.drawArc(
        rect,
        _start + _sweep * redlineFrac,
        _sweep * (1 - redlineFrac),
        false,
        Paint()
          ..color = danger.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    final tickPaint = Paint()
      ..color = tick
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

    final frac = (value / max).clamp(0.0, 1.0);
    final inRed = redlineFrac > 0 && frac >= redlineFrac;
    final arcColor = inRed ? danger : color;
    if (glow) {
      canvas.drawArc(
        rect,
        _start,
        _sweep * frac,
        false,
        Paint()
          ..color = arcColor.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawArc(
      rect,
      _start,
      _sweep * frac,
      false,
      Paint()
        ..color = arcColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round,
    );

    _text(
      canvas,
      value.toStringAsFixed(0),
      c.translate(0, -r * 0.08),
      TextStyle(
        color: inRed ? Color.lerp(danger, Colors.white, 0.25) : textColor,
        fontSize: r * 0.42,
        fontWeight: FontWeight.bold,
      ),
    );

    _text(
      canvas,
      label,
      c.translate(0, r * 0.42),
      TextStyle(color: mutedColor, fontSize: 13),
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
      old.track != track ||
      old.glow != glow ||
      old.label != label;
}

/// Budowanie pojedynczych widgetów dashboardu z danych telemetrii.
///
/// Każdy [DashWidget] (typ + opcje) zamieniamy na gotowy widget Fluttera.
/// Kolory, gradienty, obrys, promień, poświata i tekstura pochodzą z aktywnej
/// SKÓRKI ([AppSettings.dashSkin]) — patrz handoff Część 3.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../app_state.dart';
import '../telemetry/gt7_packet.dart';
import '../ui/circular_gauge.dart';
import 'dash_skin.dart';
import 'dashboard_model.dart';

/// Aktywna skórka (skrót).
DashSkin get _s => AppSettings.instance.dashSkin;

/// Przykładowy pakiet telemetrii do żywych miniatur w bibliotece widgetów.
Gt7Packet sampleDashPacket() {
  final p = Gt7Packet();
  p.speedMps = 180 / 3.6;
  p.rpm = 7200;
  p.rpmAlertMax = 8500;
  p.rpmAlertMin = 7000;
  p.calcMaxSpeed = 320;
  p.gear = 4;
  p.suggestedGear = 5;
  p.currentFuel = 33;
  p.fuelCapacity = 60;
  p.tyreTemp = [86, 90, 96, 101];
  p.throttle = 205;
  p.brake = 0;
  p.wheelRotationRad = 0.45;
  p.currentLap = 3;
  p.totalLaps = 12;
  p.positionInRace = 4;
  p.totalCars = 16;
  p.lastLapMs = 92345;
  p.bestLapMs = 91870;
  p.waterTemp = 92;
  p.oilTemp = 104;
  p.oilPressure = 5.2;
  p.boost = 1.6;
  p.clutch = 1.0;
  p.energyRecovery = 0.3;
  p.bodyHeight = 65;
  p.timeOfDayMs = 14 * 3600000 + 25 * 60000;
  p.tcsActive = true;
  p.lights = true;
  return p;
}

Widget buildDashWidget(DashWidget w, Gt7Packet p, TelemetryController c) {
  final t = AppSettings.instance.t;
  switch (w.type) {
    case DashWidgetType.speedGauge:
      final rawMax = p.calcMaxSpeed > 0 ? p.calcMaxSpeed * 1.05 : 340.0;
      final sv = w.optStr('variant', 'zegar');
      if (sv == 'liczba') {
        return _bigPanel(_spdUnit(), _spd(p.speedKph).toStringAsFixed(0),
            color: _s.speed, fontSize: 44);
      }
      if (sv == 'pasek') {
        return _barGauge(_spdUnit(), _spd(p.speedKph), _spd(rawMax), _s.speed);
      }
      return _gauge(_spdUnit(), _spd(p.speedKph), _spd(rawMax), _s.speed);
    case DashWidgetType.rpmGauge:
      final max = p.rpmAlertMax > 0 ? p.rpmAlertMax * 1.02 : 9000.0;
      final rv = w.optStr('variant', 'zegar');
      if (rv == 'liczba') {
        return _bigPanel('RPM', p.rpm.toStringAsFixed(0),
            color: _s.rpm, fontSize: 40);
      }
      if (rv == 'pasek') {
        return _barGauge('RPM', p.rpm, max, _s.rpm, redlineFrac: 0.88);
      }
      return _gauge('RPM', p.rpm, max, _s.rpm, redlineFrac: 0.88);
    case DashWidgetType.gear:
      final gv = w.optStr('variant', 'duzy');
      final gStr = p.gear == 0 ? 'R' : (p.gear == 15 ? 'N' : '${p.gear}');
      final shift = p.rpmAlertMax > 0 ? p.rpm / p.rpmAlertMax : 0.0;
      final gColor = shift > 0.9 ? _s.danger : _s.text;
      if (gv == 'minimal') return _gearMinimal(gStr, gColor);
      if (gv == 'sugerowany') {
        return _gearSuggested(t('dash.gear'), gStr, gColor, p.suggestedGear);
      }
      return _bigPanel(t('dash.gear'), gStr, color: gColor);
    case DashWidgetType.delta:
      final d = c.currentDelta;
      return w.optStr('variant', 'pasek') == 'liczba'
          ? _deltaNumber(t('dash.delta'), d, w.gw)
          : _deltaBar(t('dash.delta'), d, w.gw);
    case DashWidgetType.deltaRef:
      final r = c.refLoaded ? c.refDelta : null;
      return _deltaNumber(t('dash.deltaRef'), r, w.gw);
    case DashWidgetType.speedNum:
      return _tile(t('dash.speed'),
          '${_spd(p.speedKph).toStringAsFixed(0)} ${_spdUnit()}');
    case DashWidgetType.rpmNum:
      return _tile('RPM', p.rpm.toStringAsFixed(0));
    case DashWidgetType.fuel:
      final fv = w.optStr('variant', w.gh >= 3 ? 'ring' : 'liczba');
      final fLabel = p.isElectric ? t('dash.battery') : t('dash.fuel');
      if (fv == 'ring') return _fuelRing(fLabel, p.fuelPct);
      if (fv == 'pasek') {
        return _barGauge(fLabel, p.fuelPct, 100, _fuelColor(p.fuelPct),
            valueText: '${p.fuelPct.toStringAsFixed(0)}%');
      }
      return _tile(
        fLabel,
        '${p.fuelPct.toStringAsFixed(1)} %',
        sub:
            '${p.currentFuel.toStringAsFixed(1)} / ${p.fuelCapacity.toStringAsFixed(0)}',
      );
    case DashWidgetType.lap:
      return _tile(t('dash.lap'), '${p.currentLap}/${p.totalLaps}');
    case DashWidgetType.position:
      return _tile(t('dash.position'), '${p.positionInRace}/${p.totalCars}');
    case DashWidgetType.lastLap:
      return _tile(t('dash.lastLap'), Gt7Packet.formatLaptime(p.lastLapMs));
    case DashWidgetType.bestLap:
      return _tile(t('dash.bestLap'), Gt7Packet.formatLaptime(p.bestLapMs));
    case DashWidgetType.tyres:
      final tv = w.optStr('variant', 'kafelki');
      if (tv == 'liczby') return _tyresText(p);
      if (tv == 'paski') return _tyreBars(p);
      return _tyreBoxes(p, w.optBool('showValue', true));
    case DashWidgetType.throttle:
      return w.optStr('variant', 'pionowy') == 'poziomy'
          ? _pedalHorizontal(t('dash.throttle'), p.throttle / 255.0, _s.good)
          : _pedal(t('dash.throttle'), p.throttle / 255.0, _s.good,
              w.optBool('showValue', false));
    case DashWidgetType.brake:
      return w.optStr('variant', 'pionowy') == 'poziomy'
          ? _pedalHorizontal(t('dash.brake'), p.brake / 255.0, _s.danger)
          : _pedal(t('dash.brake'), p.brake / 255.0, _s.danger,
              w.optBool('showValue', false));
    case DashWidgetType.steering:
      return _steering(p.wheelRotationRad);

    // --- Wyliczenia paliwa ---
    case DashWidgetType.fuelPerLap:
      final a = c.avgFuelPerLap;
      return _tile(t('dash.fuelPerLap'), a == null ? '—' : a.toStringAsFixed(2));
    case DashWidgetType.fuelLapsLeft:
      final l = c.fuelLapsRemaining;
      return _tile(
          t('dash.fuelLapsLeft'), l == null ? '—' : l.toStringAsFixed(1),
          valueColor: l == null
              ? null
              : (l < 2 ? _s.danger : (l < 4 ? _s.warn : _s.good)));
    case DashWidgetType.fuelMargin:
      final m = c.fuelMarginLaps;
      return _tile(
          t('dash.fuelMargin'),
          m == null
              ? '—'
              : '${m >= 0 ? '+' : ''}${m.toStringAsFixed(1)} ${t('dash.lapsUnit')}',
          valueColor: m == null ? null : (m >= 0 ? _s.good : _s.danger));
    case DashWidgetType.fuelTarget:
      return _fuelTarget(p, c, w.optInt('targetLaps', 5));

    // --- Mniej ważne dane ---
    case DashWidgetType.waterTemp:
      return _tile(t('dash.waterTemp'),
          '${_tmp(p.waterTemp).toStringAsFixed(0)} ${_tmpUnit()}');
    case DashWidgetType.oilTemp:
      return _tile(t('dash.oilTemp'),
          '${_tmp(p.oilTemp).toStringAsFixed(0)} ${_tmpUnit()}');
    case DashWidgetType.oilPressure:
      return _tile(t('dash.oilPressure'), p.oilPressure.toStringAsFixed(1));
    case DashWidgetType.boost:
      return _tile(t('dash.boost'),
          '${_prs(p.boostBar).toStringAsFixed(2)} ${_prsUnit()}');
    case DashWidgetType.energyRecovery:
      return _tile(t('dash.energyRecovery'), p.energyRecovery.toStringAsFixed(2));
    case DashWidgetType.bodyHeight:
      return _tile(t('dash.bodyHeight'), p.bodyHeight.toStringAsFixed(0));
    case DashWidgetType.clutch:
      return _tile(t('dash.clutch'), '${(p.clutch * 100).toStringAsFixed(0)} %');
    case DashWidgetType.suggestedGear:
      return _bigPanel(t('dash.suggested'),
          p.suggestedGear == 15 ? '–' : '${p.suggestedGear}',
          color: _s.rpm);
    case DashWidgetType.timeOfDay:
      return _tile(t('dash.timeOfDay'), _timeOfDay(p.timeOfDayMs));

    // --- Wskaźniki ---
    case DashWidgetType.indTcs:
      return _indicator('TCS', p.tcsActive, _s.warn);
    case DashWidgetType.indAsm:
      return _indicator('ASM', p.asmActive, _s.warn);
    case DashWidgetType.indHandbrake:
      return _indicator(t('dash.ind.handbrake'), p.handbrake, _s.danger);
    case DashWidgetType.indRevLimiter:
      return _indicator(t('dash.ind.revLimiter'), p.revLimiter, _s.danger);
    case DashWidgetType.indLights:
      return _indicator(t('dash.ind.lights'), p.lights, _s.speed);
  }
}

// --- Przeliczanie jednostek (metric/imperial) wg AppSettings ---
bool get _imperial => AppSettings.instance.imperial;
double _spd(double kph) => _imperial ? kph * 0.621371 : kph;
String _spdUnit() => _imperial ? 'mph' : 'km/h';
double _tmp(double c) => _imperial ? c * 9 / 5 + 32 : c;
String _tmpUnit() => _imperial ? '°F' : '°C';
double _prs(double bar) => _imperial ? bar * 14.5038 : bar;
String _prsUnit() => _imperial ? 'psi' : 'bar';

String _sec(double? v) =>
    v == null ? '—' : '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)} s';

Color _deltaColor(double? v) =>
    v == null ? _s.faint : (v < 0 ? _s.good : _s.danger);

String _timeOfDay(int ms) {
  if (ms <= 0) return '—';
  final totalSec = ms ~/ 1000;
  final h = (totalSec ~/ 3600) % 24;
  final m = (totalSec ~/ 60) % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

TextStyle _labelStyle({double size = 11, double spacing = 1}) =>
    TextStyle(color: _s.muted, fontSize: size, letterSpacing: spacing);

/// Zegar (CircularGauge) ze skórki.
Widget _gauge(String label, double value, double max, Color color,
    {double redlineFrac = 0.0}) {
  return CircularGauge(
    label: label,
    value: value,
    max: max,
    color: color,
    redlineFrac: redlineFrac,
    track: _s.track,
    tick: _s.faint,
    textColor: _s.text,
    mutedColor: _s.muted,
    danger: _s.danger,
    glow: _s.glow,
  );
}

/// Panel z dużą wartością (bieg, delta) — wyśrodkowany, skaluje treść.
Widget _bigPanel(String title, String value,
    {required Color color, double fontSize = 48}) {
  return _frame(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: _labelStyle(size: 12, spacing: 0)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ],
      ),
    ),
  );
}

/// Kafelek tytuł+wartość.
Widget _tile(String title, String value, {String? sub, Color? valueColor}) {
  return _frame(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    align: Alignment.centerLeft,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title.toUpperCase(), style: _labelStyle()),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: valueColor ?? _s.text)),
        ),
        if (sub != null)
          Text(sub, style: TextStyle(color: _s.faint, fontSize: 11)),
      ],
    ),
  );
}

/// Cel paliwowy.
Widget _fuelTarget(Gt7Packet p, TelemetryController c, int targetLaps) {
  final t = AppSettings.instance.t;
  final avg = c.avgFuelPerLap;
  final need = avg == null ? null : avg * targetLaps;
  final diff = need == null ? null : p.currentFuel - need;
  return _frame(
    scale: true,
    padding: const EdgeInsets.all(10),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${t('dash.target')}: $targetLaps ${t('dash.lapsUpper')}',
            style: _labelStyle()),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
              need == null
                  ? '—'
                  : '${need.toStringAsFixed(1)} ${t('dash.need')}',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: _s.text)),
        ),
        if (diff != null)
          Text(
            '${diff >= 0 ? t('dash.surplus') : t('dash.short')}${diff.toStringAsFixed(1)}',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: diff >= 0 ? _s.good : _s.danger),
          ),
      ],
    ),
  );
}

Widget _pedal(String label, double value, Color color, bool showValue) {
  return _frame(
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (_, cons) => SizedBox(
                width: 26,
                height: cons.maxHeight,
                child: CustomPaint(painter: _FillPainter(value, color, _s.track)),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(showValue ? '${(value * 100).toStringAsFixed(0)}%' : label,
              style: _labelStyle(spacing: 0)),
        ],
      ),
    ),
  );
}

Widget _steering(double rad) {
  final v = (rad / 2.6).clamp(-1.0, 1.0);
  return _frame(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(AppSettings.instance.t('dash.steering'),
              style: _labelStyle(spacing: 0)),
          const SizedBox(height: 8),
          SizedBox(
            height: 16,
            child: LayoutBuilder(
              builder: (_, cons) => CustomPaint(
                size: Size(cons.maxWidth, 16),
                painter: _SteeringPainter(v, _s.track, _s.speed, _s.faint),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Lampka wskaźnika.
Widget _indicator(String label, bool on, Color color) {
  return _frame(
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? color : _s.track,
            boxShadow: on
                ? [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 8)]
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: on ? _s.text : _s.muted)),
        ),
      ],
    ),
  );
}

/// Kolor opony wg temperatury (HSL hue 210→0, sat 0.64, jasność 0.54, 60→108°C).
Color _tyreTempColor(double tempC) {
  final f = ((tempC - 60) / 48).clamp(0.0, 1.0);
  return HSLColor.fromAHSL(1, 210 * (1 - f), 0.64, 0.54).toColor();
}

Widget _tyresText(Gt7Packet p) {
  const names = ['LP', 'PP', 'LT', 'PT'];
  return _frame(
    scale: true,
    padding: const EdgeInsets.all(10),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${AppSettings.instance.t('dash.tyresTitle')} (${_tmpUnit()})',
            style: _labelStyle()),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < 4; i++)
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${names[i]}: ',
                        style: TextStyle(color: _s.faint, fontSize: 12)),
                    Text(_tmp(p.tyreTemp[i]).toStringAsFixed(0),
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _tyreTempColor(p.tyreTemp[i]))),
                  ],
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

/// Opony jako 4 kolorowane kafelki (układ jak w aucie).
Widget _tyreBoxes(Gt7Packet p, bool showValue) {
  Widget box(int i) {
    final c = _tyreTempColor(p.tyreTemp[i]);
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(c, Colors.white, 0.22)!,
              c,
              Color.lerp(c, Colors.black, 0.16)!,
            ],
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: showValue
            ? FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(_tmp(p.tyreTemp[i]).toStringAsFixed(0),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                        fontSize: 18)),
              )
            : null,
      ),
    );
  }

  return _frame(
    fill: true,
    padding: const EdgeInsets.all(6),
    child: Column(
      children: [
        Expanded(child: Row(children: [box(0), box(1)])),
        Expanded(child: Row(children: [box(2), box(3)])),
      ],
    ),
  );
}

// =====================================================================
//  Warianty paskowe (Część 1)
// =====================================================================

Widget _barGauge(String label, double value, double max, Color color,
    {double? redlineFrac, String? valueText}) {
  final frac = max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0;
  final inRed = redlineFrac != null && frac >= redlineFrac;
  final c = inRed ? _s.danger : color;
  return _frame(
    scale: true,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(label.toUpperCase(),
                  overflow: TextOverflow.ellipsis, style: _labelStyle()),
            ),
            const SizedBox(width: 6),
            Text(valueText ?? value.toStringAsFixed(0),
                style: TextStyle(
                    color: c, fontSize: 28, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
            height: 11,
            child: CustomPaint(
                painter: _BarPainter(
                    frac, c, redlineFrac, _s.track, _s.danger, _s.glow))),
      ],
    ),
  );
}

Widget _gearMinimal(String gear, Color color) {
  return _frame(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(gear,
          style: TextStyle(
              fontSize: 60, fontWeight: FontWeight.w800, color: color)),
    ),
  );
}

Widget _gearSuggested(String label, String gear, Color color, int suggested) {
  final sug = suggested == 15 ? null : '$suggested';
  return Stack(
    children: [
      Positioned.fill(child: _bigPanel(label, gear, color: color)),
      if (sug != null)
        Positioned(
          top: 6,
          right: 8,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_drop_up, size: 16, color: _s.rpm),
              Text(sug,
                  style: TextStyle(
                      color: _s.rpm,
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
    ],
  );
}

Widget _deltaBar(String label, double? d, int gw) {
  final t = AppSettings.instance.t;
  final narrow = gw < 4;
  final faster = d != null && d < 0;
  final color = _deltaColor(d);
  return _frame(
    scale: true,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(narrow ? t('dash.deltaShort') : label.toUpperCase(),
                style: _labelStyle()),
            if (!narrow && d != null)
              Text(faster ? t('dash.faster') : t('dash.slower'),
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
          ],
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(_sec(d),
              style: TextStyle(
                  fontSize: narrow ? 28 : 38,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ),
        const SizedBox(height: 6),
        SizedBox(
            height: 9,
            child: CustomPaint(
                painter:
                    _DeltaBarPainter(d, _s.track, _s.faint, _s.good, _s.danger))),
      ],
    ),
  );
}

Widget _deltaNumber(String label, double? d, int gw) {
  final t = AppSettings.instance.t;
  final narrow = gw < 4;
  final color = _deltaColor(d);
  return _frame(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(narrow ? t('dash.deltaShort') : label.toUpperCase(),
              style: _labelStyle(size: 12, spacing: 0)),
          Text(_sec(d),
              style: TextStyle(
                  fontSize: narrow ? 28 : 34,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ],
      ),
    ),
  );
}

Color _fuelColor(double pct) =>
    pct < 15 ? _s.danger : (pct < 30 ? _s.warn : _s.good);

Widget _fuelRing(String label, double pct) {
  final color = _fuelColor(pct);
  return _frame(
    child: LayoutBuilder(
      builder: (_, cons) => CustomPaint(
        size: Size(cons.maxWidth, cons.maxHeight),
        painter: _RingPainter(
          frac: (pct / 100).clamp(0.0, 1.0),
          color: color,
          centerText: '${pct.toStringAsFixed(0)}%',
          label: label.toUpperCase(),
          track: _s.track,
          textColor: _s.text,
          labelColor: _s.muted,
          glow: _s.glow,
        ),
      ),
    ),
  );
}

Widget _tyreBars(Gt7Packet p) {
  const names = ['LP', 'PP', 'LT', 'PT'];
  Widget row(int i) {
    final temp = p.tyreTemp[i];
    final frac = ((temp - 60) / 48).clamp(0.0, 1.0);
    final color = _tyreTempColor(temp);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child:
                Text(names[i], style: TextStyle(color: _s.faint, fontSize: 11)),
          ),
          Expanded(
            child: SizedBox(
              height: 9,
              child: CustomPaint(
                  painter: _BarPainter(frac, color, null, _s.track, _s.danger,
                      false)),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 34,
            child: Text(_tmp(temp).toStringAsFixed(0),
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  return _frame(
    scale: true,
    padding: const EdgeInsets.all(10),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [for (var i = 0; i < 4; i++) row(i)],
    ),
  );
}

Widget _pedalHorizontal(String label, double value, Color color) {
  final v = value.clamp(0.0, 1.0);
  return _frame(
    scale: true,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label.toUpperCase(), style: _labelStyle()),
            Text('${(v * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                    color: color, fontSize: 20, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
            height: 11,
            child: CustomPaint(
                painter: _BarPainter(v, color, null, _s.track, _s.danger, false))),
      ],
    ),
  );
}

// =====================================================================
//  Paintery (kolory ze skórki przekazywane jawnie -> poprawny repaint)
// =====================================================================

class _BarPainter extends CustomPainter {
  _BarPainter(this.frac, this.color, this.redlineFrac, this.track, this.danger,
      this.glow);
  final double frac;
  final Color color;
  final double? redlineFrac;
  final Color track;
  final Color danger;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    const r = Radius.circular(6);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = track);
    final w = (size.width * frac).clamp(0.0, size.width);
    if (w > 0) {
      final fillRect =
          RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, size.height), r);
      if (glow) {
        canvas.drawRRect(
            fillRect,
            Paint()
              ..color = color.withValues(alpha: 0.8)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      }
      canvas.drawRRect(fillRect, Paint()..color = color);
    }
    if (redlineFrac != null) {
      final x = size.width * redlineFrac!;
      canvas.drawRect(Rect.fromLTWH(x - 1, 0, 2, size.height),
          Paint()..color = danger.withValues(alpha: 0.6));
    }
  }

  @override
  bool shouldRepaint(_BarPainter o) =>
      o.frac != frac ||
      o.color != color ||
      o.redlineFrac != redlineFrac ||
      o.track != track ||
      o.glow != glow;
}

class _DeltaBarPainter extends CustomPainter {
  _DeltaBarPainter(this.d, this.track, this.tick, this.good, this.danger);
  final double? d;
  final Color track, tick, good, danger;

  @override
  void paint(Canvas canvas, Size size) {
    const r = Radius.circular(5);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = track);
    final cx = size.width / 2;
    canvas.drawRect(
        Rect.fromLTWH(cx - 1, 0, 2, size.height), Paint()..color = tick);
    if (d == null || d == 0) return;
    final len = d!.abs().clamp(0.0, 1.0) * (size.width / 2);
    final color = d! < 0 ? good : danger;
    final rect = d! < 0
        ? Rect.fromLTWH(cx - len, 0, len, size.height)
        : Rect.fromLTWH(cx, 0, len, size.height);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, r), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DeltaBarPainter o) =>
      o.d != d || o.track != track || o.good != good || o.danger != danger;
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.frac,
    required this.color,
    required this.centerText,
    required this.label,
    required this.track,
    required this.textColor,
    required this.labelColor,
    required this.glow,
  });
  final double frac;
  final Color color;
  final String centerText;
  final String label;
  final Color track, textColor, labelColor;
  final bool glow;

  static const double _start = 135 * math.pi / 180;
  static const double _sweep = 270 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.shortestSide - 26) / 2;
    if (r <= 0) return;
    final ctr = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: ctr, radius: r);
    final trackP = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep, false, trackP);
    if (glow) {
      canvas.drawArc(
          rect,
          _start,
          _sweep * frac,
          false,
          Paint()
            ..color = color.withValues(alpha: 0.8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 10
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    }
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep * frac, false, fill);
    _text(canvas, centerText, ctr.translate(0, -r * 0.06),
        TextStyle(color: textColor, fontSize: r * 0.42, fontWeight: FontWeight.bold));
    _text(canvas, label, ctr.translate(0, r * 0.42),
        TextStyle(color: labelColor, fontSize: 11));
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
  bool shouldRepaint(_RingPainter o) =>
      o.frac != frac ||
      o.color != color ||
      o.centerText != centerText ||
      o.track != track ||
      o.glow != glow;
}

class _FillPainter extends CustomPainter {
  _FillPainter(this.value, this.color, this.track);
  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final bg =
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4));
    canvas.drawRRect(bg, Paint()..color = track);
    final h = size.height * value.clamp(0.0, 1.0);
    final fill = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, size.height - h, size.width, h),
      const Radius.circular(4),
    );
    canvas.drawRRect(fill, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_FillPainter o) =>
      o.value != value || o.color != color || o.track != track;
}

class _SteeringPainter extends CustomPainter {
  _SteeringPainter(this.value, this.track, this.accent, this.faint);
  final double value;
  final Color track, accent, faint;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final trackP = Paint()
      ..color = track
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), trackP);
    final cx = size.width / 2;
    final x = cx + (size.width / 2) * value;
    final fill = Paint()
      ..color = accent
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, cy), Offset(x, cy), fill);
    canvas.drawCircle(Offset(cx, cy), 2, Paint()..color = faint);
  }

  @override
  bool shouldRepaint(_SteeringPainter o) =>
      o.value != value || o.accent != accent || o.track != track;
}

// =====================================================================
//  Ramka kafelka + tekstura włókna węglowego
// =====================================================================

Widget _frame({
  required Widget child,
  EdgeInsets? padding,
  Alignment? align = Alignment.center,
  bool fill = false,
  bool scale = false,
}) {
  final s = _s;
  Widget content = child;
  if (scale) {
    content = LayoutBuilder(
      builder: (_, cons) => FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
            width: cons.maxWidth.isFinite ? cons.maxWidth : 200.0, child: child),
      ),
    );
  }
  final radius = BorderRadius.circular(s.radius);
  // Tekstura splotu węglowego pod zawartością (skórka Carbon Fiber).
  if (s.carbon) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF15171B),
        border: Border.all(color: s.border),
        borderRadius: radius,
        boxShadow: s.tileShadow,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            const Positioned.fill(
              child: CustomPaint(
                painter: DashCarbonPainter(
                    cell: 9,
                    base: Color(0xFF15171B),
                    light: Color(0xFF262A30),
                    dark: Color(0xFF15171B)),
              ),
            ),
            Container(
                alignment: (fill || scale) ? null : align,
                padding: padding,
                child: content),
          ],
        ),
      ),
    );
  }
  return Container(
    alignment: (fill || scale) ? null : align,
    padding: padding,
    decoration: BoxDecoration(
      gradient: s.tile,
      border: Border.all(color: s.border),
      borderRadius: radius,
      boxShadow: s.tileShadow,
    ),
    child: content,
  );
}

/// Tekstura włókna węglowego — splot 2×2: szachownica komórek, w której kierunek
/// przekątnego połysku zmienia się co kratkę (jak w prawdziwym carbonie).
class DashCarbonPainter extends CustomPainter {
  const DashCarbonPainter({
    this.cell = 14,
    this.base = const Color(0xFF0F1115),
    this.light = const Color(0xFF1B1D22),
    this.dark = const Color(0xFF0B0D11),
  });
  final double cell;
  final Color base, light, dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    for (var yi = 0; yi * cell < size.height; yi++) {
      for (var xi = 0; xi * cell < size.width; xi++) {
        final r = Rect.fromLTWH(xi * cell, yi * cell, cell, cell);
        final even = (xi + yi).isEven;
        final g = LinearGradient(
          begin: even ? Alignment.topLeft : Alignment.topRight,
          end: even ? Alignment.bottomRight : Alignment.bottomLeft,
          colors: [light, dark],
        );
        canvas.drawRect(r, Paint()..shader = g.createShader(r));
      }
    }
    // delikatny pionowy połysk u góry
    final sheen = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x14FFFFFF), Color(0x00000000)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sheen);
  }

  @override
  bool shouldRepaint(DashCarbonPainter o) =>
      o.cell != cell || o.base != base || o.light != light || o.dark != dark;
}

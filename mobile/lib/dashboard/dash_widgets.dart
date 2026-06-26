/// Budowanie pojedynczych widgetów dashboardu z danych telemetrii.
///
/// Każdy [DashWidget] (typ + opcje) zamieniamy na gotowy widget Fluttera,
/// reużywając istniejących elementów. Funkcja jest "głupia" — tylko prezentacja;
/// dane bierze z pakietu i kontrolera, wygląd z [DashWidget.options].
library;

import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../app_state.dart';
import '../telemetry/gt7_packet.dart';
import '../ui/circular_gauge.dart';
import '../ui/theme.dart';
import 'dashboard_model.dart';

Widget buildDashWidget(DashWidget w, Gt7Packet p, TelemetryController c) {
  final t = AppSettings.instance.t;
  switch (w.type) {
    case DashWidgetType.speedGauge:
      final rawMax = p.calcMaxSpeed > 0 ? p.calcMaxSpeed * 1.05 : 340.0;
      if (w.optStr('variant', 'zegar') == 'liczba') {
        return _bigPanel(_spdUnit(), _spd(p.speedKph).toStringAsFixed(0),
            color: AppColors.accent, fontSize: 44);
      }
      return CircularGauge(
          label: _spdUnit(),
          value: _spd(p.speedKph),
          max: _spd(rawMax),
          color: AppColors.accent);
    case DashWidgetType.rpmGauge:
      final max = p.rpmAlertMax > 0 ? p.rpmAlertMax * 1.02 : 9000.0;
      if (w.optStr('variant', 'zegar') == 'liczba') {
        return _bigPanel('RPM', p.rpm.toStringAsFixed(0),
            color: AppColors.accentRpm, fontSize: 40);
      }
      return CircularGauge(
          label: 'RPM',
          value: p.rpm,
          max: max,
          color: AppColors.accentRpm,
          redlineFrac: 0.88);
    case DashWidgetType.gear:
      return _bigPanel(
          t('dash.gear'), p.gear == 0 ? 'R' : (p.gear == 15 ? 'N' : '${p.gear}'),
          color: Colors.white);
    case DashWidgetType.delta:
      final d = c.currentDelta;
      return _bigPanel(t('dash.delta'), _sec(d),
          color: _deltaColor(d), fontSize: 34);
    case DashWidgetType.deltaRef:
      final r = c.refLoaded ? c.refDelta : null;
      return _bigPanel(t('dash.deltaRef'), _sec(r),
          color: _deltaColor(r), fontSize: 30);
    case DashWidgetType.speedNum:
      return _tile(t('dash.speed'),
          '${_spd(p.speedKph).toStringAsFixed(0)} ${_spdUnit()}');
    case DashWidgetType.rpmNum:
      return _tile('RPM', p.rpm.toStringAsFixed(0));
    case DashWidgetType.fuel:
      return _tile(
        p.isElectric ? t('dash.battery') : t('dash.fuel'),
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
      return w.optStr('variant', 'liczby') == 'kafelki'
          ? _tyreBoxes(p, w.optBool('showValue', true))
          : _tyresText(p);
    case DashWidgetType.throttle:
      return _pedal(t('dash.throttle'), p.throttle / 255.0, AppColors.good,
          w.optBool('showValue', false));
    case DashWidgetType.brake:
      return _pedal(t('dash.brake'), p.brake / 255.0, AppColors.danger,
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
              ? Colors.white
              : (l < 2 ? AppColors.danger : (l < 4 ? AppColors.warn : AppColors.good)));
    case DashWidgetType.fuelMargin:
      final m = c.fuelMarginLaps;
      return _tile(
          t('dash.fuelMargin'),
          m == null
              ? '—'
              : '${m >= 0 ? '+' : ''}${m.toStringAsFixed(1)} ${t('dash.lapsUnit')}',
          valueColor: m == null
              ? Colors.white
              : (m >= 0 ? AppColors.good : AppColors.danger));
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
          color: AppColors.accentRpm);
    case DashWidgetType.timeOfDay:
      return _tile(t('dash.timeOfDay'), _timeOfDay(p.timeOfDayMs));

    // --- Wskaźniki ---
    case DashWidgetType.indTcs:
      return _indicator('TCS', p.tcsActive, AppColors.warn);
    case DashWidgetType.indAsm:
      return _indicator('ASM', p.asmActive, AppColors.warn);
    case DashWidgetType.indHandbrake:
      return _indicator(t('dash.ind.handbrake'), p.handbrake, AppColors.danger);
    case DashWidgetType.indRevLimiter:
      return _indicator(
          t('dash.ind.revLimiter'), p.revLimiter, AppColors.danger);
    case DashWidgetType.indLights:
      return _indicator(t('dash.ind.lights'), p.lights, AppColors.accent);
  }
}

// --- Przeliczanie jednostek (metric/imperial) wg AppSettings ---
bool get _imperial => AppSettings.instance.imperial;
double _spd(double kph) => _imperial ? kph * 0.621371 : kph; // km/h -> mph
String _spdUnit() => _imperial ? 'mph' : 'km/h';
double _tmp(double c) => _imperial ? c * 9 / 5 + 32 : c; // °C -> °F
String _tmpUnit() => _imperial ? '°F' : '°C';
double _prs(double bar) => _imperial ? bar * 14.5038 : bar; // bar -> psi
String _prsUnit() => _imperial ? 'psi' : 'bar';

String _sec(double? v) =>
    v == null ? '—' : '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)} s';

Color _deltaColor(double? v) => v == null
    ? AppColors.muted2
    : (v < 0 ? AppColors.good : AppColors.danger);

String _timeOfDay(int ms) {
  if (ms <= 0) return '—';
  final totalSec = ms ~/ 1000;
  final h = (totalSec ~/ 3600) % 24;
  final m = (totalSec ~/ 60) % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
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
          Text(title,
              style: const TextStyle(color: AppColors.muted2, fontSize: 12)),
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

/// Kafelek tytuł+wartość (jak InfoTile, ale wypełnia całą komórkę).
Widget _tile(String title, String value,
    {String? sub, Color valueColor = Colors.white}) {
  return _frame(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    align: Alignment.centerLeft,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title.toUpperCase(),
            style: const TextStyle(
                color: AppColors.muted, fontSize: 11, letterSpacing: 1)),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: valueColor)),
        ),
        if (sub != null)
          Text(sub,
              style: const TextStyle(color: AppColors.muted2, fontSize: 11)),
      ],
    ),
  );
}

/// Cel paliwowy: ile paliwa potrzeba na N okrążeń i nadwyżka/niedobór względem
/// obecnego stanu. N ustawia użytkownik w opcjach widgetu.
Widget _fuelTarget(Gt7Packet p, TelemetryController c, int targetLaps) {
  final t = AppSettings.instance.t;
  final avg = c.avgFuelPerLap;
  final need = avg == null ? null : avg * targetLaps;
  final diff = need == null ? null : p.currentFuel - need;
  return _frame(
    padding: const EdgeInsets.all(10),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${t('dash.target')}: $targetLaps ${t('dash.lapsUpper')}',
            style: const TextStyle(
                color: AppColors.muted, fontSize: 11, letterSpacing: 1)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
              need == null
                  ? '—'
                  : '${need.toStringAsFixed(1)} ${t('dash.need')}',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
        ),
        if (diff != null)
          Text(
            '${diff >= 0 ? t('dash.surplus') : t('dash.short')}${diff.toStringAsFixed(1)}',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: diff >= 0 ? AppColors.good : AppColors.danger),
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
                child: CustomPaint(painter: _FillPainter(value, color)),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(showValue ? '${(value * 100).toStringAsFixed(0)}%' : label,
              style: const TextStyle(color: AppColors.muted2, fontSize: 11)),
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
              style: const TextStyle(color: AppColors.muted2, fontSize: 11)),
          const SizedBox(height: 8),
          SizedBox(
            height: 16,
            child: LayoutBuilder(
              builder: (_, cons) => CustomPaint(
                size: Size(cons.maxWidth, 16),
                painter: _SteeringPainter(v),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Lampka wskaźnika: świeci [color] gdy [on], inaczej przygaszona.
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
            color: on ? color : const Color(0xFF2A2A2A),
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
                  color: on ? Colors.white : AppColors.muted)),
        ),
      ],
    ),
  );
}

const _tyreWarn = 95.0;
Color _tyreColor(double t) {
  if (t >= _tyreWarn) return AppColors.danger;
  if (t >= _tyreWarn - 15) return AppColors.warn;
  return AppColors.good;
}

/// Płynny (ciągły) kolor opony wg temperatury — barwa przechodzi po odcieniu
/// HSV od zimnego niebiesko-zielonego, przez optymalną zieleń, po gorącą czerwień.
/// Dzięki temu kolor zmienia się stopniowo, bez skoków między progami.
Color _tyreColorSmooth(double t) {
  const lo = 60.0, hi = 108.0; // zakres roboczy temperatur opon
  final f = ((t - lo) / (hi - lo)).clamp(0.0, 1.0);
  final hue = 210.0 * (1 - f); // 210° (chłód) -> 0° (czerwień)
  return HSVColor.fromAHSV(1, hue, 0.68, 0.92).toColor();
}

Widget _tyresText(Gt7Packet p) {
  const names = ['LP', 'PP', 'LT', 'PT'];
  return _frame(
    padding: const EdgeInsets.all(10),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${AppSettings.instance.t('dash.tyresTitle')} (${_tmpUnit()})',
            style: const TextStyle(
                color: AppColors.muted, fontSize: 11, letterSpacing: 1)),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < 4; i++)
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${names[i]}: ',
                        style: const TextStyle(
                            color: AppColors.muted2, fontSize: 12)),
                    Text(_tmp(p.tyreTemp[i]).toStringAsFixed(0),
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _tyreColor(p.tyreTemp[i]))),
                  ],
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

/// Opony jako 4 kolorowane kafelki (układ jak w aucie: FL FR / RL RR).
/// Opcjonalnie z liczbą temperatury.
Widget _tyreBoxes(Gt7Packet p, bool showValue) {
  Widget box(int i) {
    final c = _tyreColorSmooth(p.tyreTemp[i]);
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          // Delikatny gradient w kafelku - płynniejszy, mniej "płaski" wygląd.
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
        Expanded(child: Row(children: [box(0), box(1)])), // przód
        Expanded(child: Row(children: [box(2), box(3)])), // tył
      ],
    ),
  );
}

/// Wspólna ramka panelu (tło + obrys + zaokrąglenie). [fill] = bez wyrównania,
/// żeby dziecko mogło wypełnić całą komórkę (np. kafelki opon).
Widget _frame({
  required Widget child,
  EdgeInsets? padding,
  Alignment? align = Alignment.center,
  bool fill = false,
}) {
  return Container(
    alignment: fill ? null : align,
    padding: padding,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.tileTop, AppColors.tileBottom],
      ),
      border: Border.all(color: AppColors.tileBorder),
      borderRadius: BorderRadius.circular(11),
    ),
    child: child,
  );
}

class _FillPainter extends CustomPainter {
  _FillPainter(this.value, this.color);
  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = RRect.fromRectAndRadius(
        Offset.zero & size, const Radius.circular(4));
    canvas.drawRRect(bg, Paint()..color = const Color(0xFF1E1E1E));
    final h = size.height * value.clamp(0.0, 1.0);
    final fill = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, size.height - h, size.width, h),
      const Radius.circular(4),
    );
    canvas.drawRRect(fill, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_FillPainter old) =>
      old.value != value || old.color != color;
}

class _SteeringPainter extends CustomPainter {
  _SteeringPainter(this.value); // -1..1
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final track = Paint()
      ..color = const Color(0xFF1E1E1E)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), track);
    final cx = size.width / 2;
    final x = cx + (size.width / 2) * value;
    final fill = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, cy), Offset(x, cy), fill);
    canvas.drawCircle(Offset(cx, cy), 2, Paint()..color = AppColors.muted2);
  }

  @override
  bool shouldRepaint(_SteeringPainter old) => old.value != value;
}

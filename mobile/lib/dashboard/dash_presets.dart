/// Gotowe układy ekranów (presety) — odpowiednik galerii presetów z makiety.
///
/// Każdy preset to lista widgetów z pozycją/rozmiarem (siatka 12×8) i opcjami.
/// Przy dodaniu tworzony jest nowy ekran z świeżymi id (patrz preview_tab).
library;

import 'dashboard_model.dart';

class DashPresetW {
  const DashPresetW(this.type, this.gx, this.gy, this.gw, this.gh,
      [this.options]);
  final DashWidgetType type;
  final int gx, gy, gw, gh;
  final Map<String, dynamic>? options;
}

class DashPreset {
  const DashPreset(this.nameKey, this.widgets);
  final String nameKey;
  final List<DashPresetW> widgets;
}

const List<DashPreset> kDashPresets = [
  // 1. Wyścig — klasyczny układ wyścigowy.
  DashPreset('preset.race', [
    DashPresetW(DashWidgetType.speedGauge, 0, 0, 3, 4),
    DashPresetW(DashWidgetType.gear, 5, 0, 2, 2),
    DashPresetW(DashWidgetType.delta, 4, 2, 4, 2, {'variant': 'pasek'}),
    DashPresetW(DashWidgetType.rpmGauge, 9, 0, 3, 4),
    DashPresetW(DashWidgetType.fuel, 0, 4, 3, 2),
    DashPresetW(DashWidgetType.lap, 3, 4, 2, 2),
    DashPresetW(DashWidgetType.position, 5, 4, 2, 2),
    DashPresetW(DashWidgetType.lastLap, 7, 4, 3, 2),
    DashPresetW(DashWidgetType.bestLap, 10, 4, 2, 2),
    DashPresetW(DashWidgetType.tyres, 0, 6, 12, 2),
  ]),
  // 2. Kwalifikacje — duża delta + czasy.
  DashPreset('preset.quali', [
    DashPresetW(DashWidgetType.speedGauge, 0, 0, 3, 4),
    DashPresetW(DashWidgetType.delta, 3, 0, 6, 4, {'variant': 'pasek'}),
    DashPresetW(DashWidgetType.rpmGauge, 9, 0, 3, 4),
    DashPresetW(DashWidgetType.lastLap, 0, 4, 3, 2),
    DashPresetW(DashWidgetType.bestLap, 3, 4, 3, 2),
    DashPresetW(DashWidgetType.deltaRef, 6, 4, 3, 2, {'variant': 'liczba'}),
    DashPresetW(DashWidgetType.position, 9, 4, 3, 2),
    DashPresetW(DashWidgetType.tyres, 0, 6, 12, 2, {'variant': 'paski'}),
  ]),
  // 3. Opony i paliwo — strategia.
  DashPreset('preset.tyresFuel', [
    DashPresetW(DashWidgetType.tyres, 0, 0, 6, 4,
        {'variant': 'kafelki', 'showValue': true}),
    DashPresetW(DashWidgetType.fuel, 6, 0, 3, 4, {'variant': 'ring'}),
    DashPresetW(DashWidgetType.fuelLapsLeft, 9, 0, 3, 2),
    DashPresetW(DashWidgetType.fuelPerLap, 9, 2, 3, 2),
    DashPresetW(DashWidgetType.waterTemp, 0, 4, 3, 2),
    DashPresetW(DashWidgetType.oilTemp, 3, 4, 3, 2),
    DashPresetW(DashWidgetType.fuelMargin, 6, 4, 3, 2),
    DashPresetW(DashWidgetType.fuelTarget, 9, 4, 3, 2, {'targetLaps': 10}),
    DashPresetW(DashWidgetType.throttle, 0, 6, 2, 2, {'variant': 'poziomy'}),
    DashPresetW(DashWidgetType.brake, 2, 6, 2, 2, {'variant': 'poziomy'}),
    DashPresetW(DashWidgetType.boost, 4, 6, 4, 2),
    DashPresetW(DashWidgetType.oilPressure, 8, 6, 4, 2),
  ]),
  // 4. Minimal — tylko najważniejsze.
  DashPreset('preset.minimal', [
    DashPresetW(DashWidgetType.speedGauge, 0, 0, 4, 5),
    DashPresetW(DashWidgetType.gear, 4, 0, 4, 5, {'variant': 'minimal'}),
    DashPresetW(DashWidgetType.rpmGauge, 8, 0, 4, 5),
    DashPresetW(DashWidgetType.delta, 0, 5, 12, 3, {'variant': 'pasek'}),
  ]),
  // 5. Wejścia kierowcy — gaz/hamulec/kierownica.
  DashPreset('preset.inputs', [
    DashPresetW(DashWidgetType.throttle, 0, 0, 2, 6, {'variant': 'pionowy'}),
    DashPresetW(DashWidgetType.brake, 2, 0, 2, 6, {'variant': 'pionowy'}),
    DashPresetW(DashWidgetType.steering, 4, 0, 8, 2),
    DashPresetW(DashWidgetType.gear, 4, 2, 4, 4, {'variant': 'duzy'}),
    DashPresetW(DashWidgetType.speedNum, 8, 2, 4, 2),
    DashPresetW(DashWidgetType.rpmNum, 8, 4, 4, 2),
    DashPresetW(DashWidgetType.delta, 0, 6, 12, 2, {'variant': 'pasek'}),
  ]),
];

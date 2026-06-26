/// Model konfigurowalnego Podglądu (dashboardu).
///
/// Dashboard = lista ekranów; każdy ekran to zbiór widgetów ułożonych na siatce
/// 12 kolumn × 8 wierszy. Widget zajmuje prostokąt komórek (gx,gy + gw,gh) i ma
/// własne opcje ([DashWidget.options]) — wariant wyglądu, pokazywanie liczb,
/// parametry (np. cel paliwowy). Wszystko serializuje się do JSON i zapisuje
/// lokalnie ([DashboardStore]).
library;

import '../app_settings.dart';

/// Stała geometria siatki edytora.
const int kGridCols = 12;
const int kGridRows = 8;

/// Typy widgetów, które można położyć na dashboardzie.
enum DashWidgetType {
  // Podstawowe
  speedGauge,
  rpmGauge,
  gear,
  delta,
  deltaRef,
  speedNum,
  rpmNum,
  fuel,
  lap,
  position,
  lastLap,
  bestLap,
  tyres,
  throttle,
  brake,
  steering,
  // Wyliczenia paliwa (inżynier)
  fuelPerLap,
  fuelLapsLeft,
  fuelMargin,
  fuelTarget,
  // Mniej ważne dane z pakietu
  waterTemp,
  oilTemp,
  oilPressure,
  boost,
  energyRecovery,
  bodyHeight,
  clutch,
  suggestedGear,
  timeOfDay,
  // Wskaźniki (lampki) flag
  indTcs,
  indAsm,
  indHandbrake,
  indRevLimiter,
  indLights,
}

/// Czytelna, przetłumaczona nazwa typu (do palety i list).
String dashTypeLabel(DashWidgetType t) =>
    AppSettings.instance.t('dashtype.${t.name}');

/// Przetłumaczona etykieta wariantu wyglądu (wartość pozostaje stała w zapisie).
String dashVariantLabel(String variant) =>
    AppSettings.instance.t('variant.$variant');

/// Domyślny rozmiar nowo dodawanego widgetu (w komórkach siatki).
({int w, int h}) dashTypeDefaultSize(DashWidgetType t) {
  switch (t) {
    case DashWidgetType.speedGauge:
    case DashWidgetType.rpmGauge:
      return (w: 3, h: 4);
    case DashWidgetType.tyres:
      return (w: 12, h: 2);
    case DashWidgetType.gear:
      return (w: 2, h: 3);
    case DashWidgetType.throttle:
    case DashWidgetType.brake:
    case DashWidgetType.steering:
      return (w: 2, h: 4);
    case DashWidgetType.indTcs:
    case DashWidgetType.indAsm:
    case DashWidgetType.indHandbrake:
    case DashWidgetType.indRevLimiter:
    case DashWidgetType.indLights:
      return (w: 2, h: 1);
    case DashWidgetType.fuelTarget:
      return (w: 3, h: 3);
    default:
      return (w: 3, h: 2);
  }
}

/// Czy typ ma alternatywne warianty wyglądu (do dialogu opcji).
List<String> dashTypeVariants(DashWidgetType t) {
  switch (t) {
    case DashWidgetType.tyres:
      return ['liczby', 'kafelki'];
    case DashWidgetType.speedGauge:
    case DashWidgetType.rpmGauge:
      return ['zegar', 'liczba'];
    default:
      return const [];
  }
}

/// Czy typ obsługuje przełącznik „pokazuj liczbę".
bool dashTypeHasShowValue(DashWidgetType t) =>
    t == DashWidgetType.tyres ||
    t == DashWidgetType.throttle ||
    t == DashWidgetType.brake;

class DashWidget {
  DashWidget({
    required this.id,
    required this.type,
    required this.gx,
    required this.gy,
    required this.gw,
    required this.gh,
    Map<String, dynamic>? options,
  }) : options = options ?? {};

  final int id;
  DashWidgetType type;
  int gx; // kolumna lewego-górnego rogu (0..kGridCols-1)
  int gy; // wiersz (0..kGridRows-1)
  int gw; // szerokość w komórkach
  int gh; // wysokość w komórkach

  /// Per-widgetowe ustawienia wyglądu/zachowania (wariant, showValue, cel...).
  final Map<String, dynamic> options;

  String optStr(String k, String dft) => '${options[k] ?? dft}';
  bool optBool(String k, bool dft) => (options[k] as bool?) ?? dft;
  int optInt(String k, int dft) => (options[k] as num?)?.toInt() ?? dft;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'gx': gx,
        'gy': gy,
        'gw': gw,
        'gh': gh,
        if (options.isNotEmpty) 'options': options,
      };

  static DashWidget fromJson(Map<String, dynamic> m) {
    final type = DashWidgetType.values.firstWhere(
      (t) => t.name == m['type'],
      orElse: () => DashWidgetType.gear,
    );
    return DashWidget(
      id: (m['id'] as num?)?.toInt() ?? 0,
      type: type,
      gx: (m['gx'] as num?)?.toInt() ?? 0,
      gy: (m['gy'] as num?)?.toInt() ?? 0,
      gw: (m['gw'] as num?)?.toInt() ?? 3,
      gh: (m['gh'] as num?)?.toInt() ?? 2,
      options: (m['options'] as Map?)?.cast<String, dynamic>() ?? {},
    );
  }
}

class DashScreen {
  DashScreen({required this.name, required this.widgets});

  String name;
  List<DashWidget> widgets;

  Map<String, dynamic> toJson() =>
      {'name': name, 'widgets': widgets.map((w) => w.toJson()).toList()};

  static DashScreen fromJson(Map<String, dynamic> m) => DashScreen(
        name: '${m['name'] ?? 'Ekran'}',
        widgets: ((m['widgets'] as List?) ?? [])
            .map((e) => DashWidget.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class DashboardConfig {
  DashboardConfig({required this.screens, this.activeIndex = 0});

  List<DashScreen> screens;
  int activeIndex;

  /// Najwyższe użyte id + 1 (do nadawania nowym widgetom unikalnych id).
  int nextWidgetId() {
    var maxId = 0;
    for (final s in screens) {
      for (final w in s.widgets) {
        if (w.id > maxId) maxId = w.id;
      }
    }
    return maxId + 1;
  }

  Map<String, dynamic> toJson() => {
        'activeIndex': activeIndex,
        'screens': screens.map((s) => s.toJson()).toList(),
      };

  static DashboardConfig fromJson(Map<String, dynamic> m) {
    final screens = ((m['screens'] as List?) ?? [])
        .map((e) => DashScreen.fromJson(e as Map<String, dynamic>))
        .toList();
    if (screens.isEmpty) return defaultConfig();
    var idx = (m['activeIndex'] as num?)?.toInt() ?? 0;
    if (idx < 0 || idx >= screens.length) idx = 0;
    return DashboardConfig(screens: screens, activeIndex: idx);
  }

  /// Domyślny układ — odwzorowuje dotychczasowy stały Podgląd.
  static DashboardConfig defaultConfig() {
    var id = 0;
    DashWidget w(DashWidgetType t, int gx, int gy, int gw, int gh) =>
        DashWidget(id: ++id, type: t, gx: gx, gy: gy, gw: gw, gh: gh);
    return DashboardConfig(
      activeIndex: 0,
      screens: [
        DashScreen(name: AppSettings.instance.t('dash.defaultScreen'), widgets: [
          w(DashWidgetType.speedGauge, 0, 0, 3, 4),
          w(DashWidgetType.gear, 5, 0, 2, 2),
          w(DashWidgetType.delta, 4, 2, 4, 2),
          w(DashWidgetType.rpmGauge, 9, 0, 3, 4),
          w(DashWidgetType.fuel, 0, 4, 3, 2),
          w(DashWidgetType.lap, 3, 4, 2, 2),
          w(DashWidgetType.position, 5, 4, 2, 2),
          w(DashWidgetType.lastLap, 7, 4, 3, 2),
          w(DashWidgetType.bestLap, 10, 4, 2, 2),
          w(DashWidgetType.tyres, 0, 6, 12, 2),
        ]),
      ],
    );
  }
}

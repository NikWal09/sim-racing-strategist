/// Kalkulator stintu — czysta, bezstanowa logika paliwa i opon.
///
/// Jedno źródło prawdy dla obliczeń: używa go zarówno żywy inżynier
/// (`RaceEngineer._fuelStrategy`), jak i ekran „Stint" (tryb Auto i Ręczny).
/// Bez zależności od Fluttera — łatwe do testowania.
///
/// Paliwo liczone jest dokładnie (poziom mierzony z telemetrii). Opony są
/// SZACUNKOWE: GT7 nie udostępnia mieszanki ani zużycia w pakiecie UDP, więc
/// bazujemy na wybranej mieszance, jej żywotności i liczbie przejechanych
/// okrążeń; temperatury służą tylko do alarmu o przegrzaniu.
library;

/// Wejście do obliczeń paliwa. Wartości pochodzą z sesji lub od użytkownika.
class FuelInput {
  /// Pojemność zbiornika [l]. 0 dla aut elektrycznych (kalkulator nie ma sensu).
  final double tankL;

  /// Aktualne paliwo [l] (lub na starcie planowanego stintu).
  final double currentL;

  /// Średnie zużycie na okrążenie [l].
  final double perLapL;

  /// Liczba okrążeń pozostałych do końca wyścigu.
  final int lapsRemaining;

  const FuelInput({
    required this.tankL,
    required this.currentL,
    required this.perLapL,
    required this.lapsRemaining,
  });
}

/// Wynik kalkulacji paliwa. Wszystkie pola wyliczone deterministycznie z [FuelInput].
class FuelPlan {
  /// Ile okrążeń przejedziemy na obecnym paliwie (currentL / perLapL).
  final double lapsLeftOnFuel;

  /// Paliwo potrzebne do mety z marginesem [l] ((lapsRemaining + margin) * perLapL).
  final double neededWithMarginL;

  /// Brakujące paliwo do mety [l] (z marginesem). 0, jeśli starczy.
  final double deficitL;

  /// Ile dolać na pit stopie [l] — deficyt przycięty do pojemności zbiornika.
  final double refuelL;

  /// Brakujące paliwo jako procent pojemności zbiornika [%].
  final double refuelPct;

  /// Ile oszczędzać na okrążenie [l], żeby dojechać bez tankowania (0, jeśli starczy).
  final double savePerLapL;

  /// Zapas paliwa względem mety wyrażony w okrążeniach (BEZ marginesu).
  /// Dodatni = starczy z zapasem; ujemny = zabraknie.
  final double spareLaps;

  /// Czy dojedzie do mety bez tankowania (z uwzględnieniem marginesu).
  final bool finishesWithoutPit;

  const FuelPlan({
    required this.lapsLeftOnFuel,
    required this.neededWithMarginL,
    required this.deficitL,
    required this.refuelL,
    required this.refuelPct,
    required this.savePerLapL,
    required this.spareLaps,
    required this.finishesWithoutPit,
  });
}

/// Wejście do szacunku opon. GT7 nie daje zużycia, więc opieramy się na liczbie
/// okrążeń na komplecie i szacowanej żywotności mieszanki.
class TyreInput {
  /// Ile okrążeń przejechano na obecnym komplecie.
  final int lapsOnSet;

  /// Szacowana żywotność kompletu [okrążenia] (z mieszanki / ustawienia).
  final int estLifeLaps;

  /// Temperatury opon [°C] (FL, FR, RL, RR). Pusta lista = brak danych.
  final List<double> tempC;

  /// Próg przegrzania [°C].
  final double tempWarnC;

  const TyreInput({
    required this.lapsOnSet,
    required this.estLifeLaps,
    this.tempC = const [],
    this.tempWarnC = 110.0,
  });
}

/// Wynik szacunku opon.
class TyrePlan {
  /// Pozostała „żywotność" 0..1 (1 = nowe, 0 = wyczerpane).
  final double lifeLeftFrac;

  /// Szacowane pozostałe okrążenia na komplecie (>= 0).
  final int lapsLeftEst;

  /// Czy któraś opona przekroczyła próg temperatury.
  final bool overheating;

  /// Indeks najgorętszej opony (0..3) lub -1, gdy brak przegrzania/danych.
  final int hottestIndex;

  const TyrePlan({
    required this.lifeLeftFrac,
    required this.lapsLeftEst,
    required this.overheating,
    required this.hottestIndex,
  });
}

class StintCalculator {
  /// Próg liczbowy, poniżej którego deficyt uznajemy za zerowy (szum zmiennoprzec.).
  static const double eps = 0.01;

  /// Szacunek stanu opon (patrz uwaga w nagłówku — to estymata, nie pomiar).
  static TyrePlan tyre(TyreInput i) {
    final life = i.estLifeLaps > 0 ? i.estLifeLaps : 1;
    final lapsLeft = life - i.lapsOnSet;
    final frac = (lapsLeft / life).clamp(0.0, 1.0).toDouble();

    var hottest = -1;
    var maxT = double.negativeInfinity;
    for (var k = 0; k < i.tempC.length; k++) {
      if (i.tempC[k] > maxT) {
        maxT = i.tempC[k];
        hottest = k;
      }
    }
    final overheating = hottest >= 0 && maxT >= i.tempWarnC;

    return TyrePlan(
      lifeLeftFrac: frac,
      lapsLeftEst: lapsLeft > 0 ? lapsLeft : 0,
      overheating: overheating,
      hottestIndex: overheating ? hottest : -1,
    );
  }

  /// Oblicza plan paliwa. [marginLaps] = rezerwa bezpieczeństwa w okrążeniach
  /// (np. 0.5 okrążenia). Zgodne z dotychczasową logiką `_fuelStrategy`.
  static FuelPlan fuel(FuelInput i, {double marginLaps = 0.5}) {
    final perLap = i.perLapL;
    final lapsRem = i.lapsRemaining;

    final lapsLeftOnFuel = perLap > 0 ? i.currentL / perLap : 0.0;
    final neededWithMargin = (lapsRem + marginLaps) * perLap;
    final rawDeficit = neededWithMargin - i.currentL;
    final finishes = rawDeficit <= eps;

    final deficitL = finishes ? 0.0 : rawDeficit;

    // Ile dolać: deficyt przycięty do pojemności zbiornika (nie zatankujesz więcej).
    final refuelL =
        finishes ? 0.0 : (i.tankL > 0 ? deficitL.clamp(0.0, i.tankL) : deficitL);
    final refuelPct = (!finishes && i.tankL > 0) ? 100.0 * deficitL / i.tankL : 0.0;

    // Ile oszczędzać/okrążenie, by dociągnąć bez tankowania (jak w _fuelStrategy:
    // requiredAvg = currentL / lapsRemaining; save = perLap - requiredAvg).
    double savePerLap = 0.0;
    if (!finishes && lapsRem > 0 && perLap > 0) {
      final requiredAvg = i.currentL / lapsRem;
      savePerLap = perLap - requiredAvg;
      if (savePerLap < 0) savePerLap = 0.0;
    }

    // Zapas w okrążeniach BEZ marginesu (jak gałąź „starczy do mety" w _fuelStrategy).
    final spareLaps =
        perLap > 0 ? (i.currentL - lapsRem * perLap) / perLap : 0.0;

    return FuelPlan(
      lapsLeftOnFuel: lapsLeftOnFuel,
      neededWithMarginL: neededWithMargin,
      deficitL: deficitL,
      refuelL: refuelL,
      refuelPct: refuelPct,
      savePerLapL: savePerLap,
      spareLaps: spareLaps,
      finishesWithoutPit: finishes,
    );
  }
}

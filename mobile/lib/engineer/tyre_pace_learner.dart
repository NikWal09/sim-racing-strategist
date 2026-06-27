/// Auto-pomiar tempa mieszanek z jazdy.
///
/// Dla każdej mieszanki zbiera próbki (wiek opony [okr.], czas okrążenia [s])
/// i dopasowuje prostą: czas = base + deg * wiek (regresja liniowa MNK).
/// Daje to szacowane: tempo na świeżej oponie (base) i degradację (deg).
/// Maksymalny zaobserwowany wiek służy jako podpowiedź żywotności.
///
/// Bez zależności od Fluttera — łatwe do testowania.
library;

class MeasuredProfile {
  final double basePaceS; // tempo na świeżej oponie [s]
  final double degPerLapS; // degradacja [s/okrążenie]
  final int sampleLaps; // liczba okrążeń w pomiarze
  final int maxAgeLaps; // najwyższy zaobserwowany wiek opony (podpowiedź życia)
  const MeasuredProfile({
    required this.basePaceS,
    required this.degPerLapS,
    required this.sampleLaps,
    required this.maxAgeLaps,
  });
}

class _Acc {
  int n = 0;
  double sx = 0, sy = 0, sxy = 0, sxx = 0;
  int maxAge = 0;

  void add(int age, double y) {
    final x = age.toDouble();
    n++;
    sx += x;
    sy += y;
    sxy += x * y;
    sxx += x * x;
    if (age > maxAge) maxAge = age;
  }

  MeasuredProfile? profile() {
    if (n <= 0) return null;
    final mean = sy / n;
    if (n == 1) {
      // jedno okrążenie — brak nachylenia, tempo = średnia
      return MeasuredProfile(
          basePaceS: mean, degPerLapS: 0, sampleLaps: n, maxAgeLaps: maxAge);
    }
    final denom = n * sxx - sx * sx;
    double base, deg;
    if (denom.abs() < 1e-9) {
      // wszystkie próbki w tym samym wieku — brak degradacji do oszacowania
      base = mean;
      deg = 0;
    } else {
      deg = (n * sxy - sx * sy) / denom;
      base = (sy - deg * sx) / n;
    }
    return MeasuredProfile(
      basePaceS: base,
      degPerLapS: deg,
      sampleLaps: n,
      maxAgeLaps: maxAge,
    );
  }
}

class TyrePaceLearner {
  final Map<String, _Acc> _byCompound = {};

  /// Dodaje okrążenie: [compoundId], wiek opony [ageLaps] (0 = pierwsze na
  /// komplecie), czas okrążenia [lapTimeS]. Odrzuca nierealne wartości.
  void addLap(String compoundId, int ageLaps, double lapTimeS) {
    if (ageLaps < 0) return;
    if (lapTimeS < 20 || lapTimeS > 1200) return; // odsiew śmieci/out-lapów
    (_byCompound[compoundId] ??= _Acc()).add(ageLaps, lapTimeS);
  }

  MeasuredProfile? profileFor(String compoundId) =>
      _byCompound[compoundId]?.profile();

  bool hasData(String compoundId) =>
      (_byCompound[compoundId]?.n ?? 0) > 0;

  void reset(String compoundId) => _byCompound.remove(compoundId);

  void resetAll() => _byCompound.clear();
}

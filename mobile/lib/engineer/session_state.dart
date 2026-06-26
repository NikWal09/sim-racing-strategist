/// Stan sesji wyścigowej — port `SessionState` z `gt7_engineer/engineer/state.py`.
/// Przechowuje to, czego pojedynczy pakiet nie zawiera: historię i trendy.
library;

class SessionState {
  bool connected = false;
  int? carCode;

  int currentLap = 0;
  int bestLapMs = -1;
  int lastPosition = 0;

  double? fuelAtLapStart;

  /// Zużycie z ostatnich okrążeń (krocząca średnia). Ograniczone do [fuelWindow].
  final List<double> fuelPerLapHistory = [];
  int fuelWindow = 3;

  void addFuelSample(double used) {
    fuelPerLapHistory.add(used);
    if (fuelPerLapHistory.length > fuelWindow) {
      fuelPerLapHistory.removeRange(0, fuelPerLapHistory.length - fuelWindow);
    }
  }

  void reset() {
    currentLap = 0;
    bestLapMs = -1;
    lastPosition = 0;
    fuelAtLapStart = null;
    fuelPerLapHistory.clear();
  }

  double? get avgFuelPerLap {
    final vals = fuelPerLapHistory.where((v) => v > 0).toList();
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  double? lapsRemainingOnFuel(double currentFuel) {
    final avg = avgFuelPerLap;
    if (avg == null || avg <= 0) return null;
    return currentFuel / avg;
  }
}

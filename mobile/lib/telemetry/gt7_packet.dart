/// Reprezentacja sparsowanego pakietu telemetrii GT7.
///
/// Port modelu z `gt7_engineer/telemetry/packet.py`. Wszystkie predkosci i
/// temperatury w jednostkach SI z gry; wlasciwosci pomocnicze przeliczaja je na
/// czytelniejsze (km/h itd.).
library;

class Gt7Packet {
  int packetId = 0;

  // Pozycja i ruch (x, y, z).
  List<double> position = [0.0, 0.0, 0.0];
  List<double> velocity = [0.0, 0.0, 0.0];
  double speedMps = 0.0; // predkosc wzdluz toru jazdy [m/s]
  double rpm = 0.0;
  double bodyHeight = 0.0;

  // Naped / paliwo.
  double currentFuel = 0.0; // aktualny poziom paliwa
  double fuelCapacity = 0.0; // pojemnosc zbiornika (0 dla aut elektrycznych)
  double boost = 0.0; // surowa wartosc; bar = boost - 1
  int gear = 0; // aktualny bieg (0 = wsteczny/R, 15 = luz/N, 1..n = do przodu)
  int suggestedGear = 0; // sugerowany bieg (15 = brak sugestii)
  int throttle = 0; // 0-255
  int brake = 0; // 0-255
  double clutch = 0.0;
  double clutchEngaged = 0.0;
  double rpmAfterClutch = 0.0;

  // Plyny / temperatury.
  double oilPressure = 0.0;
  double waterTemp = 0.0;
  double oilTemp = 0.0;
  List<double> tyreTemp = [0.0, 0.0, 0.0, 0.0]; // FL, FR, RL, RR

  // Kola / opony.
  List<double> wheelSpeed = [0.0, 0.0, 0.0, 0.0];
  List<double> tyreRadius = [0.0, 0.0, 0.0, 0.0];
  List<double> suspension = [0.0, 0.0, 0.0, 0.0];

  // Wyscig / okrazenia.
  int currentLap = 0;
  int totalLaps = 0;
  int bestLapMs = -1;
  int lastLapMs = -1;
  int timeOfDayMs = 0;
  int positionInRace = 0;
  int totalCars = 0;
  int rpmAlertMin = 0;
  int rpmAlertMax = 0;
  int calcMaxSpeed = 0;

  int carCode = 0;

  // Dodatkowe pola ruchu nadwozia - tylko formaty 'B' i '~' (0.0 dla 'A').
  double wheelRotationRad = 0.0; // fizyczny kat skretu kierownicy [rad]
  double forceFeedback = 0.0;
  double sway = 0.0;
  double heave = 0.0;
  double surge = 0.0;

  // Pola dostepne tylko w formacie '~' (0 dla 'A'/'B').
  int throttleRaw = 0; // niefiltrowany gaz 0-255 (widac dzialanie TCS)
  int brakeRaw = 0; // niefiltrowany hamulec 0-255 (widac dzialanie ABS)
  double energyRecovery = 0.0;

  // Flagi (rozpakowane z 16-bitowego pola).
  bool onTrack = false;
  bool paused = false;
  bool loading = false;
  bool inGear = false;
  bool hasTurbo = false;
  bool revLimiter = false;
  bool handbrake = false;
  bool lights = false;
  bool highBeam = false;
  bool lowBeam = false;
  bool asmActive = false;
  bool tcsActive = false;

  // --- Wlasciwosci pomocnicze ---

  double get speedKph => speedMps * 3.6;

  double get boostBar => boost - 1.0;

  double get fuelPct {
    if (fuelCapacity <= 0) return 0.0;
    return 100.0 * currentFuel / fuelCapacity;
  }

  /// Auta elektryczne raportuja pojemnosc zbiornika = 100 i "paliwo" jako %.
  bool get isElectric => fuelCapacity == 100.0;

  /// Zamienia czas w ms na 'M:SS.mmm'. -1 / brak -> '--'.
  static String formatLaptime(int? ms) {
    if (ms == null || ms < 0) return '--';
    final minutes = ms ~/ 60000;
    final rem = ms % 60000;
    final seconds = rem ~/ 1000;
    final millis = rem % 1000;
    final ss = seconds.toString().padLeft(2, '0');
    final mmm = millis.toString().padLeft(3, '0');
    return '$minutes:$ss.$mmm';
  }
}

/// Konfiguracja inżyniera (progi i przełączniki) — port `EngineerConfig` z
/// `gt7_engineer/config.py`. Domyślne wartości takie same jak na desktopie.
library;

class EngineerConfig {
  EngineerConfig({
    this.fuelWarningLaps = 3.0,
    this.fuelCriticalLaps = 1.5,
    this.pitWindowLaps = 2.0,
    this.minLapsForFuelCalc = 1,
    this.tyreTempWarning = 110.0,
    this.announceLapTimes = true,
    this.announcePositionChanges = true,
    this.announceBestLap = true,
    this.announceFuelStrategy = true,
    this.fuelTargetMarginLaps = 0.5,
    this.fuelMaxMessagesPerLap = 1,
    this.announceFuelOkToFinish = false,
    this.announceCornerTyres = true,
    this.cornerTempWarning = 95.0,
    this.announceDelta = true,
    this.deltaMinSeconds = 0.15,
    this.announceRefSectors = true,
    this.refSectors = 3,
    this.refSectorMinSeconds = 0.3,
    this.fuelShowPercent = true,
    this.fuelShowAvg = true,
    this.fuelShowLapsLeft = true,
    this.fuelAvgWindow = 3,
  });

  double fuelWarningLaps;
  double fuelCriticalLaps;
  double pitWindowLaps;
  int minLapsForFuelCalc;
  double tyreTempWarning;
  bool announceLapTimes;
  bool announcePositionChanges;
  bool announceBestLap;
  bool announceFuelStrategy;
  double fuelTargetMarginLaps;
  int fuelMaxMessagesPerLap;
  bool announceFuelOkToFinish;
  bool announceCornerTyres;
  double cornerTempWarning;
  bool announceDelta;
  double deltaMinSeconds;
  bool announceRefSectors;
  int refSectors;
  double refSectorMinSeconds;
  bool fuelShowPercent;
  bool fuelShowAvg;
  bool fuelShowLapsLeft;
  int fuelAvgWindow;
}

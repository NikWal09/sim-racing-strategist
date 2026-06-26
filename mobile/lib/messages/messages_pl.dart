/// Polskie komunikaty inżyniera + formatowanie liczb pod TTS.
///
/// Port z `gt7_engineer/engineer/messages/pl.py` i `base.py`. Teksty wypowiadane
/// używają pełnych polskich znaków (ą, ć, ę, ł, ń, ó, ś, ź, ż) — neuronowe i
/// systemowe głosy PL wymawiają je poprawnie. Wiele metod losuje wariant, żeby
/// inżynier brzmiał mniej robotycznie.
library;

import 'dart:math';

final Random _rng = Random();

/// Polska odmiana: 1 -> one, 2-4 (poza 12-14) -> few, reszta -> many.
String pluralPl(int n, String one, String few, String many) {
  n = n.abs();
  if (n == 1) return one;
  final m10 = n % 10, m100 = n % 100;
  if (m10 >= 2 && m10 <= 4 && !(m100 >= 12 && m100 <= 14)) return few;
  return many;
}

String lapsWord(num n) => pluralPl(n.round(), 'okrążenie', 'okrążenia', 'okrążeń');

/// Liczba do wypowiedzenia: całkowite bez ułamka, reszta z 'przecinek X'.
String numberPl(double value) {
  final rounded = (value * 10).round() / 10;
  if ((rounded - rounded.roundToDouble()).abs() < 0.05) {
    return rounded.round().toString();
  }
  final whole = rounded.truncate();
  final tenths = ((rounded - whole).abs() * 10).round();
  return '$whole przecinek $tenths';
}

/// Czas okrążenia w ms -> wypowiadalny po polsku, np. '1 minuta 23 i 4 sekundy'.
String formatLaptimeSpoken(int ms) {
  if (ms < 0) return 'brak czasu';
  final minutes = ms ~/ 60000;
  final rem = ms % 60000;
  final seconds = rem / 1000.0;
  var secWhole = seconds.truncate();
  var tenths = ((seconds - secWhole) * 10).round();
  if (tenths == 10) {
    secWhole += 1;
    tenths = 0;
  }
  final secPart = '$secWhole i $tenths';
  if (minutes > 0) {
    final minWord = pluralPl(minutes, 'minuta', 'minuty', 'minut');
    return '$minutes $minWord $secPart sekundy';
  }
  return '$secPart sekundy';
}

/// Polskie komunikaty inżyniera. Metody zwracają gotowy do wypowiedzenia tekst.
class PolishMessages {
  /// Nazwy naroźników opon w kolejności telemetrii: FL, FR, RL, RR.
  static const List<String> corners = [
    'lewa przednia',
    'prawa przednia',
    'lewa tylna',
    'prawa tylna',
  ];

  String _pick(List<String> variants) => variants[_rng.nextInt(variants.length)];

  String number(double v) => numberPl(v);
  String laptime(int ms) => formatLaptimeSpoken(ms);

  String radioCheck() => _pick([
        'Radio check. Inżynier na łączach, słyszysz mnie?',
        'Sprawdzam radio. Jestem z tobą.',
        'Radio check. Łączność działa.',
      ]);

  String connected() => _pick([
        'Telemetria połączona. Inżynier na łączach.',
        'Jestem z tobą. Telemetria działa.',
        'Połączenie nawiązane. Powodzenia na torze.',
      ]);

  String lapTime(int lastMs) {
    final t = laptime(lastMs);
    return _pick([
      'Ostatnie okrążenie: $t.',
      'Czas okrążenia $t.',
      'Kółko za $t.',
    ]);
  }

  String bestLap(int bestMs) {
    final t = laptime(bestMs);
    return _pick([
      'Najlepsze okrążenie! $t.',
      'Rekord sesji! $t.',
      'Świetnie, najszybsze kółko: $t.',
    ]);
  }

  String fuelLapsLeft(double laps) {
    final n = number(laps), w = lapsWord(laps);
    return _pick([
      'Paliwa wystarczy na około $n $w.',
      'Na zbiorniku około $n $w.',
    ]);
  }

  String fuelWarning(double laps) {
    final n = number(laps), w = lapsWord(laps);
    return _pick([
      'Uwaga, paliwo. Zostało około $n $w.',
      'Pilnuj paliwa, około $n $w do końca zbiornika.',
    ]);
  }

  String fuelCritical(double laps) {
    final n = number(laps), w = lapsWord(laps);
    return _pick([
      'Krytyczny poziom paliwa! Około $n $w.',
      'Paliwo na wykończeniu! Tylko około $n $w.',
    ]);
  }

  String fuelOkToFinish(double marginLaps) {
    final n = number(marginLaps), w = lapsWord(marginLaps);
    return _pick([
      'Paliwa wystarczy do mety, zapas około $n $w.',
      'Spokojnie z paliwem, na koniec zostanie około $n $w.',
    ]);
  }

  String fuelRunsOut(int lap) => _pick([
        'Tym tempem paliwa starczy do okrążenia $lap.',
        'Bez oszczędzania dojedziesz na paliwie do okrążenia $lap.',
      ]);

  String fuelSavePerLap(double amount) {
    final n = number(amount);
    return _pick([
      'Oszczędzaj około $n paliwa na okrążenie, żeby dojechać.',
      'Zejdź z gazu, trzeba około $n mniej na kółko.',
    ]);
  }

  String fuelRefuelPct(double pct) {
    final n = number(pct);
    return _pick([
      'Dotankuj około $n procent, żeby dojechać do mety.',
      'Na pit stopie wlej około $n procent zbiornika.',
    ]);
  }

  String gainedPosition(int pos) => _pick([
        'Brawo! Awans na pozycję $pos.',
        'Wyprzedzenie! Jesteś $pos.',
        'Dobra robota, pozycja $pos.',
      ]);

  String lostPosition(int pos) => _pick([
        'Strata pozycji. Jesteś $pos.',
        'Przepuścili cię, teraz $pos.',
      ]);

  String lastLap() => _pick([
        'Ostatnie okrążenie! Daj z siebie wszystko.',
        'Ostatnie kółko, zostaw serce na torze.',
      ]);

  String deltaAhead(double seconds) {
    final n = number(seconds);
    return _pick([
      '$n sekundy do przodu.',
      'Jesteś o $n szybciej od najlepszego.',
      'Zysk $n sekundy do rekordu.',
    ]);
  }

  String deltaBehind(double seconds) {
    final n = number(seconds);
    return _pick([
      '$n sekundy z tyłu.',
      'Tracisz $n do najlepszego.',
      'Strata $n sekundy do rekordu.',
    ]);
  }

  String refSectorLoss(int sector, double seconds) {
    final n = number(seconds);
    return _pick([
      'Tracisz $n sekundy w sektorze $sector do referencji.',
      'Sektor $sector: strata $n sekundy do okrążenia referencyjnego.',
      'W sektorze $sector oddajesz $n sekundy do referencji.',
    ]);
  }

  String refSectorGain(int sector, double seconds) {
    final n = number(seconds);
    return _pick([
      'Zyskujesz $n sekundy do referencji w sektorze $sector.',
      'Sektor $sector: $n sekundy szybciej od referencji.',
      'Świetny sektor $sector, $n sekundy do przodu.',
    ]);
  }

  String tyreHot(String corner, double temp) {
    final n = number(temp);
    return _pick([
      'Gorąca opona $corner, $n stopni.',
      'Przegrzewa się opona $corner, $n stopni.',
    ]);
  }

  String tyreCornerHot(int cornerNo, String tyre, double temp) {
    final n = number(temp);
    return _pick([
      'Na zakręcie $cornerNo przegrzałeś oponę $tyre, $n stopni.',
      'Zakręt $cornerNo: opona $tyre doszła do $n stopni, za gorąca.',
      'Uwaga, na $cornerNo zakręcie opona $tyre ma $n stopni.',
    ]);
  }

  String tyreCornerWorst(int cornerNo, String tyre, double temp) {
    final n = number(temp);
    return _pick([
      'Opony najmocniej grzeją się na zakręcie $cornerNo: $tyre, około $n stopni.',
      'Najgorętszy dla opon jest zakręt $cornerNo, opona $tyre, około $n stopni.',
    ]);
  }

  String finished(int pos, int total) {
    if (pos > 0) {
      final tail = total > 0 ? ' z $total.' : '.';
      return 'Meta! Kończysz na pozycji $pos$tail';
    }
    return 'Meta! Dobra robota.';
  }

  String position(int pos, int total) =>
      total > 0 ? 'Pozycja $pos z $total.' : 'Pozycja $pos.';
}

/// Lista przykładowych komunikatów do zakładki "Test głosów" (etykieta + funkcja
/// generująca świeży tekst — wariant losuje się przy każdym odtworzeniu).
List<({String label, String Function() build})> voiceSamples(PolishMessages m) {
  final rr = PolishMessages.corners[3];
  return [
    (label: 'Radio check', build: () => m.radioCheck()),
    (label: 'Połączenie', build: () => m.connected()),
    (label: 'Czas okrążenia', build: () => m.lapTime(92567)),
    (label: 'Najlepsze okrążenie', build: () => m.bestLap(91234)),
    (label: 'Paliwo - zostało', build: () => m.fuelLapsLeft(3.4)),
    (label: 'Paliwo - ostrzeżenie', build: () => m.fuelWarning(2.4)),
    (label: 'Paliwo - krytyczne', build: () => m.fuelCritical(1.2)),
    (label: 'Paliwo - starczy do mety', build: () => m.fuelOkToFinish(0.8)),
    (label: 'Paliwo - do którego okr.', build: () => m.fuelRunsOut(8)),
    (label: 'Paliwo - ile oszczędzać', build: () => m.fuelSavePerLap(0.3)),
    (label: 'Paliwo - ile dotankować', build: () => m.fuelRefuelPct(12.5)),
    (label: 'Delta - szybciej', build: () => m.deltaAhead(0.3)),
    (label: 'Delta - wolniej', build: () => m.deltaBehind(0.7)),
    (label: 'Awans pozycji', build: () => m.gainedPosition(3)),
    (label: 'Strata pozycji', build: () => m.lostPosition(5)),
    (label: 'Ostatnie okrążenie', build: () => m.lastLap()),
    (label: 'Gorąca opona', build: () => m.tyreHot(rr, 112.0)),
    (label: 'Gorący zakręt', build: () => m.tyreCornerHot(3, rr, 122.0)),
    (label: 'Najgorętszy zakręt', build: () => m.tyreCornerWorst(7, rr, 128.0)),
    (label: 'Meta', build: () => m.finished(1, 16)),
    (label: 'Pozycja', build: () => m.position(4, 16)),
  ];
}

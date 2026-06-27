/// Optymalizator strategii oponowej — czysta, bezstanowa logika.
///
/// Model: każdy stint zaczyna się na świeżych oponach. Czas okrążenia rośnie
/// liniowo z wiekiem opony (degradacja). Stint o długości L na mieszance:
///   t(L) = L*base + deg*L*(L-1)/2
/// Strategia = lista stintów (mieszanka + długość) pokrywająca dystans wyścigu;
/// każdy stint nie dłuższy niż żywotność mieszanki; liczba pit stopów = stinty-1.
/// Całkowity czas = suma czasów stintów + pit stopy * strata na pit stopie.
///
/// Optymalny podział okrążeń między stinty (przy wypukłym koszcie) wyznaczamy
/// zachłannie po koszcie krańcowym — zweryfikowane względem pełnego przeglądu.
library;

class CompoundProfile {
  final String id; // RS / RM / RH / RI / RW
  final double basePaceS; // czas okrążenia na świeżej oponie [s]
  final double degPerLapS; // przyrost czasu na każde okrążenie wieku opony [s]
  final int lifeLaps; // maks. użytecznych okrążeń w jednym stincie

  const CompoundProfile({
    required this.id,
    required this.basePaceS,
    required this.degPerLapS,
    required this.lifeLaps,
  });

  /// Czas stintu o długości [laps] (świeże opony na starcie stintu).
  double stintTimeS(int laps) =>
      laps * basePaceS + degPerLapS * laps * (laps - 1) / 2.0;

  /// Koszt dołożenia okrążenia, gdy stint ma już [currentLen] okrążeń.
  double marginalS(int currentLen) => basePaceS + degPerLapS * currentLen;
}

class StintLeg {
  final String compoundId;
  final int laps;
  const StintLeg(this.compoundId, this.laps);
}

class StrategyOption {
  final List<StintLeg> legs;
  final int stops;
  final double totalTimeS;
  const StrategyOption(this.legs, this.stops, this.totalTimeS);
}

class StrategyInput {
  final int raceLaps;
  final double pitLossS;
  final List<CompoundProfile> compounds; // tylko dostępne (zaznaczone)
  final bool requireTwoCompounds; // wymóg użycia min. 2 różnych mieszanek
  final int maxStops;

  const StrategyInput({
    required this.raceLaps,
    required this.pitLossS,
    required this.compounds,
    this.requireTwoCompounds = false,
    this.maxStops = 4,
  });
}

class StrategyCalculator {
  /// Zwraca [topN] najszybszych strategii (rosnąco po czasie).
  static List<StrategyOption> rank(StrategyInput input, {int topN = 6}) {
    final n = input.raceLaps;
    final comps = input.compounds;
    if (n <= 0 || comps.isEmpty) return const [];

    final maxStints = (input.maxStops + 1).clamp(1, n);
    final results = <StrategyOption>[];

    for (var m = 1; m <= maxStints; m++) {
      _forEachMultiset(comps, m, (combo) {
        if (input.requireTwoCompounds &&
            combo.map((c) => c.id).toSet().length < 2) {
          return;
        }
        var capSum = 0;
        for (final c in combo) {
          capSum += c.lifeLaps;
        }
        if (capSum < n) return; // za mało żywotności, by pokryć dystans
        if (m > n) return; // więcej stintów niż okrążeń

        // Każdy stint ma min. 1 okrążenie; resztę rozdajemy zachłannie po
        // koszcie krańcowym (najtańsze dołożenie okrążenia).
        final lens = List<int>.filled(m, 1);
        var remaining = n - m;
        var ok = true;
        while (remaining > 0) {
          var bi = -1;
          var best = double.infinity;
          for (var i = 0; i < m; i++) {
            if (lens[i] >= combo[i].lifeLaps) continue;
            final marg = combo[i].marginalS(lens[i]);
            if (marg < best) {
              best = marg;
              bi = i;
            }
          }
          if (bi < 0) {
            ok = false;
            break;
          }
          lens[bi]++;
          remaining--;
        }
        if (!ok) return;

        var total = (m - 1) * input.pitLossS;
        for (var i = 0; i < m; i++) {
          total += combo[i].stintTimeS(lens[i]);
        }
        results.add(StrategyOption(
          [for (var i = 0; i < m; i++) StintLeg(combo[i].id, lens[i])],
          m - 1,
          total,
        ));
      });
    }

    results.sort((a, b) => a.totalTimeS.compareTo(b.totalTimeS));
    return results.take(topN).toList();
  }

  /// Iteruje po multizbiorach (kombinacjach z powtórzeniami) mieszanek
  /// rozmiaru [m]. Kolejność stintów nie wpływa na czas, więc multizbiór wystarcza.
  static void _forEachMultiset(
    List<CompoundProfile> comps,
    int m,
    void Function(List<CompoundProfile>) cb,
  ) {
    final acc = <CompoundProfile>[];
    void rec(int start, int left) {
      if (left == 0) {
        cb(acc);
        return;
      }
      for (var i = start; i < comps.length; i++) {
        acc.add(comps[i]);
        rec(i, left - 1); // i (nie i+1) -> powtórzenia dozwolone
        acc.removeLast();
      }
    }

    rec(0, m);
  }
}

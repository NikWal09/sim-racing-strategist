// Testy optymalizatora strategii. Uruchom: `flutter test`.
// Wartości oczekiwane policzone niezależnie (greedy zweryfikowany brute-force'em).
import 'package:flutter_test/flutter_test.dart';
import 'package:gt7_engineer_mobile/engineer/strategy_calculator.dart';

const rs = CompoundProfile(id: 'RS', basePaceS: 94.0, degPerLapS: 0.25, lifeLaps: 8);
const rm = CompoundProfile(id: 'RM', basePaceS: 95.0, degPerLapS: 0.12, lifeLaps: 14);
const rh = CompoundProfile(id: 'RH', basePaceS: 96.2, degPerLapS: 0.06, lifeLaps: 22);

void main() {
  group('StrategyCalculator.rank', () {
    test('20 okrążeń, 3 mieszanki -> najlepsza RS8 + RM12 (1 stop)', () {
      final r = StrategyCalculator.rank(const StrategyInput(
        raceLaps: 20,
        pitLossS: 22.0,
        compounds: [rs, rm, rh],
      ));
      expect(r, isNotEmpty);
      final best = r.first;
      expect(best.totalTimeS, closeTo(1928.92, 0.01));
      expect(best.stops, 1);
      expect(best.legs.length, 2);
      expect(best.legs.map((l) => l.compoundId).toSet(), {'RS', 'RM'});
      expect(best.legs.map((l) => l.laps).reduce((a, b) => a + b), 20);
      // wyniki posortowane rosnąco po czasie
      for (var i = 1; i < r.length; i++) {
        expect(r[i].totalTimeS, greaterThanOrEqualTo(r[i - 1].totalTimeS));
      }
    });

    test('tylko RM, 20 okrążeń -> 10+10 (1 stop)', () {
      final r = StrategyCalculator.rank(const StrategyInput(
        raceLaps: 20,
        pitLossS: 22.0,
        compounds: [rm],
      ));
      final best = r.first;
      expect(best.totalTimeS, closeTo(1932.8, 0.01));
      expect(best.stops, 1);
      expect(best.legs.map((l) => l.laps).toList(), [10, 10]);
    });

    test('8 okrążeń -> jeden stint RS, 0 stopów', () {
      final r = StrategyCalculator.rank(const StrategyInput(
        raceLaps: 8,
        pitLossS: 22.0,
        compounds: [rs, rm, rh],
      ));
      final best = r.first;
      expect(best.stops, 0);
      expect(best.legs.single.compoundId, 'RS');
      expect(best.totalTimeS, closeTo(759.0, 0.01));
    });

    test('wymóg 2 mieszanek przy jednej dostępnej -> brak strategii', () {
      final r = StrategyCalculator.rank(const StrategyInput(
        raceLaps: 20,
        pitLossS: 22.0,
        compounds: [rm],
        requireTwoCompounds: true,
      ));
      expect(r, isEmpty);
    });

    test('za mało żywotności na dystans -> brak strategii', () {
      final r = StrategyCalculator.rank(const StrategyInput(
        raceLaps: 30,
        pitLossS: 22.0,
        compounds: [rs], // życie 8, maks 3 stinty (maxStops 2) = 24 < 30
        maxStops: 2,
      ));
      expect(r, isEmpty);
    });
  });
}

// Testy logiki paliwa StintCalculator. Uruchom: `flutter test`.
//
// Scenariusze i wartości oczekiwane zweryfikowane niezależnie (port wzorów),
// zgodne z dotychczasową logiką inżyniera (race_engineer._fuelStrategy).
import 'package:flutter_test/flutter_test.dart';
import 'package:gt7_engineer_mobile/engineer/stint_calculator.dart';

void main() {
  group('StintCalculator.fuel', () {
    test('starcza z zapasem -> brak deficytu, dodatni zapas okrążeń', () {
      final p = StintCalculator.fuel(
        const FuelInput(tankL: 60, currentL: 40, perLapL: 3.0, lapsRemaining: 10),
        marginLaps: 0.5,
      );
      expect(p.finishesWithoutPit, isTrue);
      expect(p.deficitL, 0.0);
      expect(p.refuelL, 0.0);
      expect(p.savePerLapL, 0.0);
      expect(p.spareLaps, closeTo(3.333, 0.001)); // (40 - 10*3)/3
      expect(p.lapsLeftOnFuel, closeTo(13.333, 0.001)); // 40/3
    });

    test('brakuje paliwa -> deficyt, dolewka i procent', () {
      final p = StintCalculator.fuel(
        const FuelInput(tankL: 60, currentL: 33.5, perLapL: 3.0, lapsRemaining: 11),
        marginLaps: 0.5,
      );
      expect(p.finishesWithoutPit, isFalse);
      // needed = (11+0.5)*3 = 34.5; deficit = 1.0
      expect(p.deficitL, closeTo(1.0, 1e-9));
      expect(p.refuelL, closeTo(1.0, 1e-9));
      expect(p.refuelPct, closeTo(100.0 * 1.0 / 60.0, 1e-9)); // ~1.667%
    });

    test('save/okrążenie liczone, gdy realnie da się dociągnąć', () {
      // duży deficyt: 18 okr., 45 l, 2.5 l/okr
      final p = StintCalculator.fuel(
        const FuelInput(tankL: 45, currentL: 45, perLapL: 2.5, lapsRemaining: 18),
        marginLaps: 0.5,
      );
      expect(p.finishesWithoutPit, isFalse);
      // required = 45/18 = 2.5 -> save = 2.5 - 2.5 = 0 (na granicy), więc 0
      expect(p.savePerLapL, closeTo(0.0, 1e-9));
      // refuel% = 100 * ((18.5*2.5)-45)/45 = 100*1.25/45 ~ 2.778%
      expect(p.refuelPct, closeTo(2.778, 0.001));
    });

    test('dolewka przycięta do pojemności zbiornika', () {
      final p = StintCalculator.fuel(
        const FuelInput(tankL: 20, currentL: 2, perLapL: 3.0, lapsRemaining: 20),
        marginLaps: 0.5,
      );
      expect(p.finishesWithoutPit, isFalse);
      // deficyt ogromny, ale dolejesz max tyle, ile mieści zbiornik
      expect(p.refuelL, 20.0);
    });

    test('auto elektryczne / perLap=0 -> bez wyjątków', () {
      final p = StintCalculator.fuel(
        const FuelInput(tankL: 0, currentL: 0, perLapL: 0, lapsRemaining: 10),
      );
      expect(p.lapsLeftOnFuel, 0.0);
      expect(p.refuelPct, 0.0);
    });
  });

  group('StintCalculator.tyre', () {
    test('nowy komplet -> pełna żywotność', () {
      final t = StintCalculator.tyre(
          const TyreInput(lapsOnSet: 0, estLifeLaps: 14));
      expect(t.lifeLeftFrac, 1.0);
      expect(t.lapsLeftEst, 14);
      expect(t.overheating, isFalse);
    });

    test('w połowie stintu -> ~50% i połowa okrążeń', () {
      final t = StintCalculator.tyre(
          const TyreInput(lapsOnSet: 7, estLifeLaps: 14));
      expect(t.lifeLeftFrac, closeTo(0.5, 1e-9));
      expect(t.lapsLeftEst, 7);
    });

    test('przejechane ponad żywotność -> 0, bez wartości ujemnych', () {
      final t = StintCalculator.tyre(
          const TyreInput(lapsOnSet: 20, estLifeLaps: 14));
      expect(t.lifeLeftFrac, 0.0);
      expect(t.lapsLeftEst, 0);
    });

    test('przegrzanie wykrywa najgorętszą oponę', () {
      final t = StintCalculator.tyre(const TyreInput(
        lapsOnSet: 3,
        estLifeLaps: 14,
        tempC: [95, 112, 88, 90], // FR przekracza próg
        tempWarnC: 110,
      ));
      expect(t.overheating, isTrue);
      expect(t.hottestIndex, 1);
    });

    test('temperatury poniżej progu -> brak alarmu', () {
      final t = StintCalculator.tyre(const TyreInput(
        lapsOnSet: 3,
        estLifeLaps: 14,
        tempC: [95, 100, 88, 90],
        tempWarnC: 110,
      ));
      expect(t.overheating, isFalse);
      expect(t.hottestIndex, -1);
    });
  });
}

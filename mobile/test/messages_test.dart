/// Test formatowania komunikatów PL — wartości oczekiwane wzięte z wersji
/// Pythona (`gt7_engineer/engineer/messages/pl.py`), żeby port był wierny.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gt7_engineer_mobile/messages/messages_pl.dart';

void main() {
  test('numberPl', () {
    expect(numberPl(3.4), '3 przecinek 4');
    expect(numberPl(1.2), '1 przecinek 2');
    expect(numberPl(12.5), '12 przecinek 5');
    expect(numberPl(0.3), '0 przecinek 3');
    expect(numberPl(112.0), '112');
  });

  test('lapsWord (odmiana)', () {
    expect(lapsWord(1.2), 'okrążenie'); // round(1.2)=1
    expect(lapsWord(2.4), 'okrążenia'); // round(2.4)=2
    expect(lapsWord(5), 'okrążeń');
    expect(lapsWord(0.3), 'okrążeń'); // round(0.3)=0
  });

  test('pluralPl', () {
    expect(pluralPl(1, 'minuta', 'minuty', 'minut'), 'minuta');
    expect(pluralPl(2, 'minuta', 'minuty', 'minut'), 'minuty');
    expect(pluralPl(5, 'minuta', 'minuty', 'minut'), 'minut');
    expect(pluralPl(12, 'minuta', 'minuty', 'minut'), 'minut');
    expect(pluralPl(22, 'minuta', 'minuty', 'minut'), 'minuty');
  });

  test('formatLaptimeSpoken', () {
    expect(formatLaptimeSpoken(92567), '1 minuta 32 i 6 sekundy');
    expect(formatLaptimeSpoken(91234), '1 minuta 31 i 2 sekundy');
    expect(formatLaptimeSpoken(60000), '1 minuta 0 i 0 sekundy');
    expect(formatLaptimeSpoken(59999), '60 i 0 sekundy');
    expect(formatLaptimeSpoken(123456), '2 minuty 3 i 5 sekundy');
    expect(formatLaptimeSpoken(-1), 'brak czasu');
  });
}

/// Test portu dekodera: deszyfruje realny wektor wygenerowany enkoderem
/// Pythona (`gt7_engineer/telemetry/encoder.py`) i sprawdza sparsowane pola.
///
/// Wektor to pakiet formatu 'B' (316 B) o znanych wartosciach, zaszyfrowany
/// dokladnie tak jak robi to GT7 (IV w bajtach 0x40..0x43). Jesli ten test
/// przechodzi, port Salsa20 + offsety bajtow zgadzaja sie z wersja Pythona.
///
/// Uruchom: flutter test  (lub: dart test)
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gt7_engineer_mobile/telemetry/decoder.dart';
import 'package:gt7_engineer_mobile/telemetry/gt7_packet.dart';

// Pakiet 'B' wygenerowany w Pythonie (iv=0x12345678) o polach:
// speed_mps=55.5, rpm=7200, fuel 42/60, gear 4 (sugerowany 5), throttle 200,
// brake 10, lap 3/10, best 95123 ms, last 96456 ms, P2/12, car 1234,
// opony 85/86/87/88, on_track, wheel_rotation_rad=0.25.
const String _vectorB =
    'VnJUvjXY3sRmGq1/Y+KLSFIUeI10H+iU3KM0wsVvqD2YouDiy+UQvV4hWv+9J8y/'
    'GjHHkcQhCu87670R/zcwkHhWNBIZuQ1ga4wVrW2ylY+59OI0zY94vTWqG4oTaRX'
    'kzViRq82gLt057v/Ki3eMcALVj4mZI1YV34BaGntlcK5FIoZJZD3UnbFtjNa9AK'
    'ZZgL7lOaNc6+XQt3sB+jHnMvtrD/rbkudI4PRj0Ckag9QD3D+WNTwWe3R967Vdy'
    '0QNacmyfN+R5b6FEio3wYj2MvsLd8pbJUuuefOvtU/A/1GwjzM9EgTzuSL7OuEi'
    'CyomKrr50ihzsXqGpDjCU1NHda1sTqcOfPbwKvAFxVZUkaAuGRCs9Do3UZqvAcv'
    'brynqOwb5UjrH13CVHIYptYttImRPhbzludLmcHO9gg==';

void main() {
  test('dekoduje realny pakiet B i parsuje pola', () {
    final data = Uint8List.fromList(base64.decode(_vectorB));
    expect(data.length, 0x13C); // 316 bajtow

    final decrypted = decryptPacket(data, 'B');
    expect(decrypted, isNotNull, reason: 'magic G7S0 powinien sie zgadzac');

    final p = parsePacket(decrypted!, 'B');
    expect(p.speedMps, closeTo(55.5, 1e-3));
    expect(p.speedKph, closeTo(199.8, 1e-2));
    expect(p.rpm, closeTo(7200.0, 1e-1));
    expect(p.currentFuel, closeTo(42.0, 1e-3));
    expect(p.fuelCapacity, closeTo(60.0, 1e-3));
    expect(p.fuelPct, closeTo(70.0, 1e-3));
    expect(p.gear, 4);
    expect(p.suggestedGear, 5);
    expect(p.throttle, 200);
    expect(p.brake, 10);
    expect(p.currentLap, 3);
    expect(p.totalLaps, 10);
    expect(p.bestLapMs, 95123);
    expect(p.lastLapMs, 96456);
    expect(p.positionInRace, 2);
    expect(p.totalCars, 12);
    expect(p.carCode, 1234);
    expect(p.onTrack, isTrue);
    expect(p.tyreTemp[0], closeTo(85.0, 1e-3));
    expect(p.tyreTemp[3], closeTo(88.0, 1e-3));
    expect(p.wheelRotationRad, closeTo(0.25, 1e-4)); // pole formatu 'B'
  });

  test('zly format (zla stala XOR) -> null', () {
    final data = Uint8List.fromList(base64.decode(_vectorB));
    // Pakiet jest formatu 'B'; sprobuj odczytac jako '~' (inna stala XOR i
    // wiekszy oczekiwany rozmiar) -> magic sie nie zgodzi lub za krotki.
    expect(decryptPacket(data, '~'), isNull);
  });

  test('formatLaptime formatuje poprawnie', () {
    expect(Gt7Packet.formatLaptime(95123), '1:35.123');
    expect(Gt7Packet.formatLaptime(96456), '1:36.456');
    expect(Gt7Packet.formatLaptime(-1), '--');
    expect(Gt7Packet.formatLaptime(null), '--');
  });
}

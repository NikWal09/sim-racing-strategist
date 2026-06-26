/// Wspolny interfejs zrodla telemetrii.
///
/// Dashboard nie wie, czy dane plyna z realnego PlayStation ([Gt7Listener]),
/// czy z symulatora ([TelemetrySimulator]) - oba spelniaja ten kontrakt. Dzieki
/// temu UI da sie testowac bez konsoli (tryb demo).
library;

import 'gt7_packet.dart';

abstract class TelemetrySource {
  /// Strumien sparsowanych pakietow telemetrii.
  Stream<Gt7Packet> get packets;

  /// Czy zrodlo aktualnie dziala.
  bool get isRunning;

  /// Krotki opis zrodla (do paska statusu w UI).
  String get label;

  /// Uruchamia zrodlo (otwiera gniazdo / startuje generator).
  Future<void> start();

  /// Zatrzymuje zrodlo i zwalnia zasoby.
  Future<void> stop();
}

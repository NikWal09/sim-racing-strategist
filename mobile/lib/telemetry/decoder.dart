/// Deszyfrowanie (Salsa20) i parsowanie surowego pakietu UDP z GT7.
///
/// Port z `gt7_engineer/telemetry/decoder.py`. GT7 oferuje trzy formaty,
/// wybierane bajtem heartbeatu wysylanym na port 33739:
///
///   'A' -> 296 B (0x128) - podstawowy
///   'B' -> 316 B (0x13C) - + ruch nadwozia (kierownica, sway/heave/surge)
///   '~' -> 344 B (0x158) - + surowe (niefiltrowane) pedaly, odzysk energii
///
/// Kazdy format ma INNA stala XOR przy budowie nonce (patrz [formats]), ale ten
/// sam klucz bazowy i ten sam uklad pol bazowych (0x00..0x127).
library;

import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'gt7_packet.dart';

const int magic = 0x47375330; // "G7S0" little-endian
const int _ivOffset = 0x40;

/// Klucz deszyfrujacy - pierwsze 32 bajty stalej frazy.
final Uint8List _key = Uint8List.fromList(
  'Simulator Interface Packet GT7 ver 0.0'.codeUnits.sublist(0, 32),
);

/// Specyfikacja formatu telemetrii.
class Gt7Format {
  final int heartbeat; // bajt wysylany na port 33739, by zamowic dany format
  final int size; // oczekiwana dlugosc pakietu w bajtach
  final int ivXor; // stala XOR-owana z IV (rozna per format!)
  const Gt7Format(this.heartbeat, this.size, this.ivXor);
}

/// Trzy obslugiwane formaty. Klucz = znak formatu.
const Map<String, Gt7Format> formats = {
  'A': Gt7Format(0x41, 0x128, 0xDEADBEAF), // 'A'
  'B': Gt7Format(0x42, 0x13C, 0xDEADBEEF), // 'B'
  '~': Gt7Format(0x7E, 0x158, 0x55FABB4F), // '~'
};

/// Deszyfruje surowy pakiet UDP. Zwraca odszyfrowane bajty lub null.
///
/// null = pakiet za krotki albo niepoprawny pakiet GT7 (zly magic - np. uzyto
/// stalej XOR niewlasciwej dla danego formatu).
Uint8List? decryptPacket(Uint8List data, [String packetFormat = 'A']) {
  final spec = formats[packetFormat] ?? formats['A']!;
  if (data.length < spec.size) return null;

  final bd = ByteData.sublistView(data);
  final iv1 = bd.getUint32(_ivOffset, Endian.little);
  final iv2 = (iv1 ^ spec.ivXor) & 0xFFFFFFFF;

  // nonce (8 bajtow) = iv2_le(4) + iv1_le(4).
  final nonce = Uint8List(8);
  final nb = ByteData.sublistView(nonce);
  nb.setUint32(0, iv2, Endian.little);
  nb.setUint32(4, iv1, Endian.little);

  final engine = Salsa20Engine()
    ..init(false, ParametersWithIV(KeyParameter(_key), nonce));
  final decrypted = engine.process(data);

  final dd = ByteData.sublistView(decrypted);
  if (dd.getUint32(0, Endian.little) != magic) return null;
  return decrypted;
}

/// Parsuje odszyfrowane bajty do obiektu [Gt7Packet].
///
/// Pola bazowe (0x00..0x127) sa wspolne dla wszystkich formatow. Dla 'B'/'~'
/// doczytujemy dodatkowy blok ruchu nadwozia, a dla '~' surowe pedaly i odzysk
/// energii - jesli pakiet jest odpowiednio dlugi.
Gt7Packet parsePacket(Uint8List decrypted, [String packetFormat = 'A']) {
  final b = ByteData.sublistView(decrypted);
  double f(int o) => b.getFloat32(o, Endian.little);
  int i32(int o) => b.getInt32(o, Endian.little);
  int i16(int o) => b.getInt16(o, Endian.little);
  int u8(int o) => b.getUint8(o);

  final p = Gt7Packet();

  p.position = [f(0x04), f(0x08), f(0x0C)];
  p.velocity = [f(0x10), f(0x14), f(0x18)];
  p.bodyHeight = f(0x38);
  p.rpm = f(0x3C);

  p.currentFuel = f(0x44);
  p.fuelCapacity = f(0x48);
  p.speedMps = f(0x4C);
  p.boost = f(0x50);

  p.oilPressure = f(0x54);
  p.waterTemp = f(0x58);
  p.oilTemp = f(0x5C);
  p.tyreTemp = [f(0x60), f(0x64), f(0x68), f(0x6C)];

  p.packetId = i32(0x70);
  p.currentLap = i16(0x74);
  p.totalLaps = i16(0x76);
  p.bestLapMs = i32(0x78);
  p.lastLapMs = i32(0x7C);
  p.timeOfDayMs = i32(0x80);
  p.positionInRace = i16(0x84);
  p.totalCars = i16(0x86);
  p.rpmAlertMin = i16(0x88);
  p.rpmAlertMax = i16(0x8A);
  p.calcMaxSpeed = i16(0x8C);

  final flags = i16(0x8E);
  p.onTrack = (flags & 0x0001) != 0;
  p.paused = (flags & 0x0002) != 0;
  p.loading = (flags & 0x0004) != 0;
  p.inGear = (flags & 0x0008) != 0;
  p.hasTurbo = (flags & 0x0010) != 0;
  p.revLimiter = (flags & 0x0020) != 0;
  p.handbrake = (flags & 0x0040) != 0;
  p.lights = (flags & 0x0080) != 0;
  p.highBeam = (flags & 0x0100) != 0;
  p.lowBeam = (flags & 0x0200) != 0;
  p.asmActive = (flags & 0x0400) != 0;
  p.tcsActive = (flags & 0x0800) != 0;

  final gearByte = u8(0x90);
  p.gear = gearByte & 0x0F;
  p.suggestedGear = (gearByte >> 4) & 0x0F;
  p.throttle = u8(0x91);
  p.brake = u8(0x92);

  p.wheelSpeed = [f(0xA4), f(0xA8), f(0xAC), f(0xB0)];
  p.tyreRadius = [f(0xB4), f(0xB8), f(0xBC), f(0xC0)];
  p.suspension = [f(0xC4), f(0xC8), f(0xCC), f(0xD0)];

  p.clutch = f(0xF4);
  p.clutchEngaged = f(0xF8);
  p.rpmAfterClutch = f(0xFC);
  p.carCode = i32(0x124);

  // --- Dodatkowy blok ruchu nadwozia (formaty 'B' i '~') ---
  if ((packetFormat == 'B' || packetFormat == '~') &&
      decrypted.length >= 0x13C) {
    p.wheelRotationRad = f(0x128);
    p.forceFeedback = f(0x12C);
    p.sway = f(0x130);
    p.heave = f(0x134);
    p.surge = f(0x138);
  }

  // --- Surowe pedaly i odzysk energii (tylko format '~') ---
  if (packetFormat == '~' && decrypted.length >= 0x158) {
    p.throttleRaw = u8(0x13C);
    p.brakeRaw = u8(0x13D);
    p.energyRecovery = f(0x150);
  }

  return p;
}

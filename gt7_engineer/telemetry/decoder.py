"""Deszyfrowanie (Salsa20) i parsowanie surowego pakietu UDP z GT7.

Format pakietu odtworzony na podstawie publicznej inzynierii wstecznej
"Simulator Interface" Gran Turismo 7. GT7 oferuje trzy formaty, wybierane
bajtem heartbeatu wysylanym na port 33739:

    'A' -> 296 B (0x128) - podstawowy
    'B' -> 316 B (0x13C) - + ruch nadwozia (kierownica, sway/heave/surge)
    '~' -> 344 B (0x158) - + surowe (niefiltrowane) pedaly, odzysk energii

Kazdy format ma INNA stala XOR przy budowie nonce (patrz FORMATS), ale ten sam
klucz bazowy i ten sam uklad pol bazowych (0x00..0x127).
"""

from __future__ import annotations

import struct

from salsa20 import Salsa20_xor

from .packet import GT7Packet

PACKET_SIZE = 0x128  # minimalny/bazowy rozmiar (format 'A', 296 bajtow)
MAGIC = 0x47375330   # "G7S0" little-endian

# Klucz deszyfrujacy - pierwsze 32 bajty stalej frazy.
_KEY = b"Simulator Interface Packet GT7 ver 0.0"[:32]
_IV_XOR = 0xDEADBEAF  # stala formatu 'A' (zachowana dla zgodnosci/encodera)
_IV_OFFSET = 0x40

# Specyfikacja trzech formatow telemetrii.
#   heartbeat - bajt wysylany na port 33739, by zamowic dany format
#   size      - oczekiwana dlugosc pakietu w bajtach
#   iv_xor    - stala XOR-owana z IV (rozna per format!)
FORMATS: dict[str, dict] = {
    "A": {"heartbeat": b"A", "size": 0x128, "iv_xor": 0xDEADBEAF},
    "B": {"heartbeat": b"B", "size": 0x13C, "iv_xor": 0xDEADBEEF},
    "~": {"heartbeat": b"~", "size": 0x158, "iv_xor": 0x55FABB4F},
}


def decrypt_packet(data: bytes, packet_format: str = "A") -> bytes | None:
    """Deszyfruje surowy pakiet UDP. Zwraca odszyfrowane bajty lub None.

    None oznacza, ze pakiet jest za krotki albo nie jest poprawnym pakietem GT7
    (zly magic - np. uzyto stalej XOR niewlasciwej dla danego formatu).
    """
    spec = FORMATS.get(packet_format, FORMATS["A"])
    if len(data) < spec["size"]:
        return None

    iv1 = int.from_bytes(data[_IV_OFFSET:_IV_OFFSET + 4], byteorder="little")
    iv2 = iv1 ^ spec["iv_xor"]
    nonce = iv2.to_bytes(4, "little") + iv1.to_bytes(4, "little")  # 8 bajtow

    decrypted = Salsa20_xor(bytes(data), nonce, _KEY)
    if int.from_bytes(decrypted[0:4], "little") != MAGIC:
        return None
    return decrypted


def _f(buf: bytes, off: int) -> float:
    return struct.unpack_from("<f", buf, off)[0]


def _i32(buf: bytes, off: int) -> int:
    return struct.unpack_from("<i", buf, off)[0]


def _i16(buf: bytes, off: int) -> int:
    return struct.unpack_from("<h", buf, off)[0]


def _u8(buf: bytes, off: int) -> int:
    return struct.unpack_from("<B", buf, off)[0]


def parse_packet(decrypted: bytes, packet_format: str = "A") -> GT7Packet:
    """Parsuje odszyfrowane bajty do obiektu :class:`GT7Packet`.

    Pola bazowe (0x00..0x127) sa wspolne dla wszystkich formatow. Dla 'B'/'~'
    doczytujemy dodatkowy blok ruchu nadwozia, a dla '~' surowe pedaly i odzysk
    energii - jesli pakiet jest odpowiednio dlugi.
    """
    p = GT7Packet()

    p.position = (_f(decrypted, 0x04), _f(decrypted, 0x08), _f(decrypted, 0x0C))
    p.velocity = (_f(decrypted, 0x10), _f(decrypted, 0x14), _f(decrypted, 0x18))
    p.body_height = _f(decrypted, 0x38)
    p.rpm = _f(decrypted, 0x3C)

    p.current_fuel = _f(decrypted, 0x44)
    p.fuel_capacity = _f(decrypted, 0x48)
    p.speed_mps = _f(decrypted, 0x4C)
    p.boost = _f(decrypted, 0x50)

    p.oil_pressure = _f(decrypted, 0x54)
    p.water_temp = _f(decrypted, 0x58)
    p.oil_temp = _f(decrypted, 0x5C)
    p.tyre_temp = (
        _f(decrypted, 0x60),
        _f(decrypted, 0x64),
        _f(decrypted, 0x68),
        _f(decrypted, 0x6C),
    )

    p.packet_id = _i32(decrypted, 0x70)
    p.current_lap = _i16(decrypted, 0x74)
    p.total_laps = _i16(decrypted, 0x76)
    p.best_lap_ms = _i32(decrypted, 0x78)
    p.last_lap_ms = _i32(decrypted, 0x7C)
    p.time_of_day_ms = _i32(decrypted, 0x80)
    p.position_in_race = _i16(decrypted, 0x84)
    p.total_cars = _i16(decrypted, 0x86)
    p.rpm_alert_min = _i16(decrypted, 0x88)
    p.rpm_alert_max = _i16(decrypted, 0x8A)
    p.calc_max_speed = _i16(decrypted, 0x8C)

    flags = _i16(decrypted, 0x8E)
    p.on_track = bool(flags & 0x0001)
    p.paused = bool(flags & 0x0002)
    p.loading = bool(flags & 0x0004)
    p.in_gear = bool(flags & 0x0008)
    p.has_turbo = bool(flags & 0x0010)
    p.rev_limiter = bool(flags & 0x0020)
    p.handbrake = bool(flags & 0x0040)
    p.lights = bool(flags & 0x0080)
    p.high_beam = bool(flags & 0x0100)
    p.low_beam = bool(flags & 0x0200)
    p.asm_active = bool(flags & 0x0400)
    p.tcs_active = bool(flags & 0x0800)

    gear_byte = _u8(decrypted, 0x90)
    p.gear = gear_byte & 0x0F
    p.suggested_gear = (gear_byte >> 4) & 0x0F
    p.throttle = _u8(decrypted, 0x91)
    p.brake = _u8(decrypted, 0x92)

    p.wheel_speed = (
        _f(decrypted, 0xA4),
        _f(decrypted, 0xA8),
        _f(decrypted, 0xAC),
        _f(decrypted, 0xB0),
    )
    p.tyre_radius = (
        _f(decrypted, 0xB4),
        _f(decrypted, 0xB8),
        _f(decrypted, 0xBC),
        _f(decrypted, 0xC0),
    )
    p.suspension = (
        _f(decrypted, 0xC4),
        _f(decrypted, 0xC8),
        _f(decrypted, 0xCC),
        _f(decrypted, 0xD0),
    )

    p.clutch = _f(decrypted, 0xF4)
    p.clutch_engaged = _f(decrypted, 0xF8)
    p.rpm_after_clutch = _f(decrypted, 0xFC)
    p.car_code = _i32(decrypted, 0x124)

    # --- Dodatkowy blok ruchu nadwozia (formaty 'B' i '~') ---
    if packet_format in ("B", "~") and len(decrypted) >= 0x13C:
        p.wheel_rotation_rad = _f(decrypted, 0x128)
        p.force_feedback = _f(decrypted, 0x12C)
        p.sway = _f(decrypted, 0x130)
        p.heave = _f(decrypted, 0x134)
        p.surge = _f(decrypted, 0x138)

    # --- Surowe pedaly i odzysk energii (tylko format '~') ---
    if packet_format == "~" and len(decrypted) >= 0x158:
        p.throttle_raw = _u8(decrypted, 0x13C)
        p.brake_raw = _u8(decrypted, 0x13D)
        p.energy_recovery = _f(decrypted, 0x150)

    return p

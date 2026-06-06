"""Budowanie i szyfrowanie syntetycznych pakietow GT7.

Sluzy WYLACZNIE do testow i symulatora telemetrii (odtwarza to, co robi gra,
zeby dekoder mial co parsowac bez prawdziwej konsoli). Nie jest uzywane na
produkcyjnej sciezce odbioru.
"""

from __future__ import annotations

import struct

from salsa20 import Salsa20_xor

from .decoder import _IV_OFFSET, _KEY, FORMATS, MAGIC


def encrypt_packet(plaintext: bytes, iv: int, packet_format: str = "A") -> bytes:
    """Szyfruje pakiet tak, by dekoder go odczytal.

    Gra umieszcza IV (jawnie) w bajtach 0x40..0x43 ZASZYFROWANEGO pakietu;
    odbiorca czyta stamtad IV przed deszyfracja. Odtwarzamy to zachowanie:
    szyfrujemy caly bufor, a nastepnie nadpisujemy slot IV jawna wartoscia.
    Stala XOR i oczekiwany rozmiar zaleza od formatu (A/B/~).
    """
    spec = FORMATS.get(packet_format, FORMATS["A"])
    if len(plaintext) != spec["size"]:
        raise ValueError(
            f"plaintext formatu '{packet_format}' musi miec {spec['size']} bajtow, "
            f"ma {len(plaintext)}"
        )
    iv1 = iv & 0xFFFFFFFF
    iv2 = iv1 ^ spec["iv_xor"]
    nonce = iv2.to_bytes(4, "little") + iv1.to_bytes(4, "little")
    cipher = bytearray(Salsa20_xor(bytes(plaintext), nonce, _KEY))
    cipher[_IV_OFFSET:_IV_OFFSET + 4] = iv1.to_bytes(4, "little")
    return bytes(cipher)


def build_packet(
    *,
    packet_id: int = 0,
    current_fuel: float = 100.0,
    fuel_capacity: float = 100.0,
    speed_mps: float = 0.0,
    rpm: float = 0.0,
    boost: float = 1.0,
    water_temp: float = 90.0,
    oil_temp: float = 100.0,
    tyre_temp: tuple[float, float, float, float] = (80.0, 80.0, 80.0, 80.0),
    current_lap: int = 0,
    total_laps: int = 0,
    best_lap_ms: int = -1,
    last_lap_ms: int = -1,
    position_in_race: int = 0,
    total_cars: int = 0,
    gear: int = 0,
    suggested_gear: int = 0,
    throttle: int = 0,
    brake: int = 0,
    car_code: int = 100,
    on_track: bool = True,
    paused: bool = False,
    loading: bool = False,
    packet_format: str = "A",
    wheel_rotation_rad: float = 0.0,
    force_feedback: float = 0.0,
    sway: float = 0.0,
    heave: float = 0.0,
    surge: float = 0.0,
    throttle_raw: int = 0,
    brake_raw: int = 0,
    energy_recovery: float = 0.0,
) -> bytes:
    """Buduje JAWNY (nieszyfrowany) pakiet o rozmiarze zaleznym od formatu."""
    size = FORMATS.get(packet_format, FORMATS["A"])["size"]
    buf = bytearray(size)
    struct.pack_into("<i", buf, 0x00, MAGIC)
    struct.pack_into("<f", buf, 0x38, 0.0)          # body height
    struct.pack_into("<f", buf, 0x3C, float(rpm))
    struct.pack_into("<f", buf, 0x44, float(current_fuel))
    struct.pack_into("<f", buf, 0x48, float(fuel_capacity))
    struct.pack_into("<f", buf, 0x4C, float(speed_mps))
    struct.pack_into("<f", buf, 0x50, float(boost))
    struct.pack_into("<f", buf, 0x58, float(water_temp))
    struct.pack_into("<f", buf, 0x5C, float(oil_temp))
    for i, t in enumerate(tyre_temp):
        struct.pack_into("<f", buf, 0x60 + i * 4, float(t))

    struct.pack_into("<i", buf, 0x70, int(packet_id))
    struct.pack_into("<h", buf, 0x74, int(current_lap))
    struct.pack_into("<h", buf, 0x76, int(total_laps))
    struct.pack_into("<i", buf, 0x78, int(best_lap_ms))
    struct.pack_into("<i", buf, 0x7C, int(last_lap_ms))
    struct.pack_into("<h", buf, 0x84, int(position_in_race))
    struct.pack_into("<h", buf, 0x86, int(total_cars))

    flags = 0
    if on_track:
        flags |= 0x0001
    if paused:
        flags |= 0x0002
    if loading:
        flags |= 0x0004
    struct.pack_into("<h", buf, 0x8E, flags)

    gear_byte = (int(gear) & 0x0F) | ((int(suggested_gear) & 0x0F) << 4)
    struct.pack_into("<B", buf, 0x90, gear_byte)
    struct.pack_into("<B", buf, 0x91, int(throttle) & 0xFF)
    struct.pack_into("<B", buf, 0x92, int(brake) & 0xFF)

    struct.pack_into("<i", buf, 0x124, int(car_code))

    # Dodatkowy blok ruchu nadwozia (formaty 'B' i '~').
    if packet_format in ("B", "~"):
        struct.pack_into("<f", buf, 0x128, float(wheel_rotation_rad))
        struct.pack_into("<f", buf, 0x12C, float(force_feedback))
        struct.pack_into("<f", buf, 0x130, float(sway))
        struct.pack_into("<f", buf, 0x134, float(heave))
        struct.pack_into("<f", buf, 0x138, float(surge))
    # Surowe pedaly i odzysk energii (tylko '~').
    if packet_format == "~":
        struct.pack_into("<B", buf, 0x13C, int(throttle_raw) & 0xFF)
        struct.pack_into("<B", buf, 0x13D, int(brake_raw) & 0xFF)
        struct.pack_into("<f", buf, 0x150, float(energy_recovery))

    return bytes(buf)

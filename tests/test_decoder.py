#!/usr/bin/env python3
"""Testy weryfikacyjne: round-trip dekodera, formatowanie i logika paliwowa.

Uruchom:  python tests/test_decoder.py   (lub: python -m pytest tests/)
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from gt7_engineer.config import EngineerConfig
from gt7_engineer.engineer import RaceEngineer
from gt7_engineer.engineer import messages_pl as M
from gt7_engineer.speech import Priority
from gt7_engineer.telemetry import decrypt_packet, parse_packet
from gt7_engineer.telemetry.encoder import build_packet, encrypt_packet


def test_decode_roundtrip():
    """Pakiet zbudowany -> zaszyfrowany -> odszyfrowany -> sparsowany == oryginal."""
    plaintext = build_packet(
        packet_id=42,
        current_fuel=37.5,
        fuel_capacity=60.0,
        speed_mps=55.0,            # 198 km/h
        rpm=7200.0,
        current_lap=3,
        total_laps=10,
        best_lap_ms=91234,
        last_lap_ms=92567,
        position_in_race=2,
        total_cars=12,
        gear=5,
        suggested_gear=4,
        throttle=200,
        brake=10,
        tyre_temp=(81.0, 82.0, 95.0, 96.0),
        car_code=2024,
        on_track=True,
    )
    encrypted = encrypt_packet(plaintext, iv=42)

    decrypted = decrypt_packet(encrypted)
    assert decrypted is not None, "deszyfrowanie nie powinno zwrocic None (zly magic?)"

    p = parse_packet(decrypted)
    assert p.packet_id == 42
    assert abs(p.current_fuel - 37.5) < 1e-3
    assert abs(p.fuel_capacity - 60.0) < 1e-3
    assert abs(p.speed_mps - 55.0) < 1e-3
    assert abs(p.speed_kph - 198.0) < 1e-2
    assert abs(p.rpm - 7200.0) < 1e-1
    assert p.current_lap == 3
    assert p.total_laps == 10
    assert p.best_lap_ms == 91234
    assert p.last_lap_ms == 92567
    assert p.position_in_race == 2
    assert p.total_cars == 12
    assert p.gear == 5
    assert p.suggested_gear == 4
    assert p.throttle == 200
    assert p.brake == 10
    assert p.car_code == 2024
    assert p.on_track is True
    assert abs(p.tyre_temp[3] - 96.0) < 1e-3
    print("OK: decode round-trip")


def test_bad_packet_rejected():
    """Losowe bajty nie powinny przejsc walidacji magic."""
    assert decrypt_packet(b"\x00" * 296) is None
    assert decrypt_packet(b"too short") is None
    print("OK: bledne pakiety odrzucone")


def test_format_b_and_tilde_roundtrip():
    """Formaty 'B' i '~': dodatkowe pola przechodza round-trip; zla stala XOR = None."""
    for fmt, size in (("B", 0x13C), ("~", 0x158)):
        plaintext = build_packet(
            packet_format=fmt,
            packet_id=7,
            current_fuel=20.0,
            fuel_capacity=60.0,
            speed_mps=50.0,
            rpm=6000.0,
            current_lap=2,
            total_laps=5,
            on_track=True,
            wheel_rotation_rad=0.25,
            force_feedback=-0.5,
            sway=1.5,
            heave=-0.5,
            surge=2.0,
            throttle_raw=240,
            brake_raw=15,
            energy_recovery=3.3,
        )
        assert len(plaintext) == size, f"{fmt}: zly rozmiar bufora {len(plaintext)}"
        enc = encrypt_packet(plaintext, iv=7, packet_format=fmt)

        dec = decrypt_packet(enc, fmt)
        assert dec is not None, f"{fmt}: deszyfrowanie zwrocilo None"
        p = parse_packet(dec, fmt)

        # Pola bazowe nadal poprawne.
        assert p.packet_id == 7
        assert abs(p.current_fuel - 20.0) < 1e-3
        # Wspolny blok ruchu nadwozia.
        assert abs(p.wheel_rotation_rad - 0.25) < 1e-3, fmt
        assert abs(p.sway - 1.5) < 1e-3, fmt
        assert abs(p.surge - 2.0) < 1e-3, fmt
        if fmt == "~":
            assert p.throttle_raw == 240
            assert p.brake_raw == 15
            assert abs(p.energy_recovery - 3.3) < 1e-3
        else:  # format 'B' nie ma surowych pedalow
            assert p.throttle_raw == 0 and p.brake_raw == 0

        # Uzycie stalej XOR formatu 'A' na pakiecie 'B'/'~' => zly magic => None.
        assert decrypt_packet(enc, "A") is None, f"{fmt}: zla stala XOR powinna dac None"
    print("OK: round-trip formatow B i ~ (oraz odrzucenie zlej stalej XOR)")


def test_message_helpers():
    assert M.plural_pl(1, "a", "b", "c") == "a"
    assert M.plural_pl(3, "a", "b", "c") == "b"
    assert M.plural_pl(5, "a", "b", "c") == "c"
    assert M.plural_pl(12, "a", "b", "c") == "c"   # 12 -> many, nie few
    assert M.laps_word(1) == "okrazenie"
    assert M.laps_word(3) == "okrazenia"
    assert M.laps_word(7) == "okrazen"
    assert M.number_pl(3.0) == "3"
    assert M.number_pl(2.5) == "2 przecinek 5"
    spoken = M.format_laptime_spoken(92567)   # 1:32.567
    assert spoken.startswith("1 minuta 32"), spoken
    print(f"OK: helpery komunikatow (przyklad czasu: '{spoken}')")


def _feed(eng: RaceEngineer, **kw):
    plaintext = build_packet(**kw)
    enc = encrypt_packet(plaintext, iv=kw.get("packet_id", 0))
    p = parse_packet(decrypt_packet(enc))
    return eng.update(p)


def test_fuel_escalation():
    """Malejace paliwo -> ostrzezenie HIGH, a potem alarm CRITICAL."""
    # Sztuczny zegar: kazde okrazenie to +30 s, by anti-spam nie scinal komunikatow.
    fake_time = {"t": 0.0}
    eng = RaceEngineer(EngineerConfig(), clock=lambda: fake_time["t"])
    priorities: list[Priority] = []
    texts: list[str] = []

    laps_fuel = [(1, 60.0), (2, 49.0), (3, 38.0), (4, 27.0), (5, 16.0), (6, 5.0)]
    for i, (lap, fuel) in enumerate(laps_fuel):
        fake_time["t"] = i * 30.0
        anns = _feed(
            eng,
            packet_id=i,
            current_lap=lap,
            total_laps=10,
            current_fuel=fuel,
            fuel_capacity=60.0,
            best_lap_ms=90000,
            last_lap_ms=91000,
            position_in_race=3,
            total_cars=8,
            on_track=True,
        )
        for a in anns:
            priorities.append(a.priority)
            texts.append(a.text)

    assert Priority.HIGH in priorities, f"brak ostrzezenia HIGH; teksty: {texts}"
    assert Priority.CRITICAL in priorities, f"brak alarmu CRITICAL; teksty: {texts}"
    assert any("paliw" in t.lower() for t in texts)
    print("OK: eskalacja paliwa (HIGH + CRITICAL)")


def test_tyre_warning_throttled():
    """Goraca opona w kazdym pakiecie -> komunikat tylko raz na min_gap."""
    fake_time = {"t": 0.0}
    eng = RaceEngineer(EngineerConfig(), clock=lambda: fake_time["t"])
    # Najpierw polaczenie (pierwszy pakiet na torze).
    _feed(eng, packet_id=0, current_lap=1, on_track=True,
          tyre_temp=(80.0, 80.0, 80.0, 80.0))
    count = 0
    for i in range(1, 40):
        fake_time["t"] = i * 0.1   # 0.1 s miedzy pakietami (~4 s lacznie)
        anns = _feed(eng, packet_id=i, current_lap=1, on_track=True,
                     tyre_temp=(80.0, 80.0, 80.0, 120.0))
        count += sum(1 for a in anns if a.key == "tyre_hot")
    assert count == 1, f"oczekiwano 1 komunikatu o oponie w ~4 s, bylo {count}"
    print("OK: throttling komunikatu o oponie")


def test_english_messages():
    """Pakiet EN: formatowanie liczb/czasu i tresc komunikatow po angielsku."""
    from gt7_engineer.engineer.messages import load

    m = load("en")
    assert m.lang == "en"
    assert m.number(3.0) == "3"
    assert m.number(2.5) == "2 point 5"
    assert m.laptime(92567).startswith("1 minute 32"), m.laptime(92567)
    assert m.corners[0] == "front left"
    assert "fuel" in m.fuel_warning(2.0).lower()
    # Domyslny jezyk to polski, nieznany kod -> tez polski.
    assert load("pl").lang == "pl"
    assert load("xx").lang == "pl"
    print("OK: komunikaty angielskie i wybor jezyka")


def test_engineer_language_wiring():
    """RaceEngineer(language=...) dobiera wlasciwy zestaw komunikatow."""
    assert RaceEngineer(EngineerConfig(), language="en").M.lang == "en"
    assert RaceEngineer(EngineerConfig(), language="pl").M.lang == "pl"
    print("OK: wpiecie jezyka do inzyniera")


def test_fuel_strategy_enough():
    """Niskie zuzycie + krotki wyscig -> komunikat, ze paliwa starczy do mety."""
    fake = {"t": 0.0}
    eng = RaceEngineer(EngineerConfig(), clock=lambda: fake["t"])
    texts: list[str] = []
    laps_fuel = [(1, 60.0), (2, 58.0), (3, 56.0), (4, 54.0)]
    for i, (lap, fuel) in enumerate(laps_fuel):
        fake["t"] = i * 70.0  # duzy odstep, by anti-spam nie scinal
        anns = _feed(
            eng, packet_id=i, current_lap=lap, total_laps=5,
            current_fuel=fuel, fuel_capacity=60.0,
            best_lap_ms=90000, last_lap_ms=91000,
            position_in_race=3, total_cars=8, on_track=True,
        )
        texts += [a.text for a in anns]
    assert any("mety" in t.lower() for t in texts), f"brak 'do mety'; teksty: {texts}"
    print("OK: strategia paliwa - starczy do mety")


def test_fuel_strategy_save_to_finish():
    """Wysokie zuzycie -> komunikat o oszczedzaniu/dotankowaniu do mety."""
    fake = {"t": 0.0}
    eng = RaceEngineer(EngineerConfig(), clock=lambda: fake["t"])
    texts: list[str] = []
    # ~12/okr, 20 okrazen, zbiornik 60 -> na pewno nie starczy.
    laps_fuel = [(1, 60.0), (2, 48.0), (3, 36.0)]
    for i, (lap, fuel) in enumerate(laps_fuel):
        fake["t"] = i * 70.0
        anns = _feed(
            eng, packet_id=i, current_lap=lap, total_laps=20,
            current_fuel=fuel, fuel_capacity=60.0,
            best_lap_ms=90000, last_lap_ms=91000,
            position_in_race=3, total_cars=8, on_track=True,
        )
        texts += [a.text for a in anns]
    assert any(("oszczed" in t.lower() or "dotankuj" in t.lower()
                or "starczy" in t.lower() or "zabraknie" in t.lower())
               for t in texts), f"brak strategii niedoboru; teksty: {texts}"
    print("OK: strategia paliwa - oszczedzanie do mety")


def test_tyre_sections_learned():
    """Po dwoch okrazeniach z gorqca RR w srodku okrazenia -> sekcja z RR."""
    fake = {"t": 0.0}
    eng = RaceEngineer(EngineerConfig(), clock=lambda: fake["t"])
    # Polaczenie (lap 1).
    _feed(eng, packet_id=0, current_lap=1, on_track=True, speed_mps=50.0,
          tyre_temp=(80.0, 80.0, 80.0, 80.0))
    # Lap 1: jazda - tylko pomiar dystansu (binning rusza od lap 2).
    for i in range(1, 21):
        fake["t"] = float(i)
        _feed(eng, packet_id=i, current_lap=1, total_laps=5, on_track=True,
              speed_mps=50.0, tyre_temp=(80.0, 80.0, 80.0, 80.0))
    # Wjazd na lap 2 -> ustala dlugosc okrazenia.
    fake["t"] = 21.0
    _feed(eng, packet_id=21, current_lap=2, total_laps=5, on_track=True,
          speed_mps=50.0, tyre_temp=(80.0, 80.0, 80.0, 80.0))
    # Lap 2: RR przegrzana w srodkowej czesci okrazenia.
    for i in range(22, 42):
        fake["t"] = float(i)
        prog = i - 22
        rr = 130.0 if 9 <= prog <= 11 else 80.0
        _feed(eng, packet_id=i, current_lap=2, total_laps=5, on_track=True,
              speed_mps=50.0, tyre_temp=(80.0, 80.0, 80.0, rr))
    # Wjazd na lap 3 -> scala dane sekcji z lap 2.
    fake["t"] = 42.0
    _feed(eng, packet_id=42, current_lap=3, total_laps=5, on_track=True,
          speed_mps=50.0, tyre_temp=(80.0, 80.0, 80.0, 80.0))

    res = eng.tyres.hottest_section()
    assert res is not None, "brak nauczonej sekcji"
    section, tyre_idx, temp = res
    assert tyre_idx == 3, f"oczekiwano RR(3), bylo {tyre_idx}"
    assert temp >= 120.0, f"za niska temp sekcji: {temp}"
    assert 1 <= section <= eng.tyres.n
    print(f"OK: nauka sekcji opon (sekcja {section}/{eng.tyres.n}, RR, {temp:.0f}C)")


def run_all():
    tests = [
        test_decode_roundtrip,
        test_bad_packet_rejected,
        test_format_b_and_tilde_roundtrip,
        test_message_helpers,
        test_english_messages,
        test_engineer_language_wiring,
        test_fuel_escalation,
        test_fuel_strategy_enough,
        test_fuel_strategy_save_to_finish,
        test_tyre_warning_throttled,
        test_tyre_sections_learned,
    ]
    failed = 0
    for t in tests:
        try:
            t()
        except AssertionError as e:
            failed += 1
            print(f"FAIL: {t.__name__}: {e}")
        except Exception as e:  # noqa: BLE001
            failed += 1
            print(f"ERROR: {t.__name__}: {type(e).__name__}: {e}")
    print("-" * 50)
    if failed:
        print(f"{failed} test(ow) nie przeszlo.")
        return 1
    print("Wszystkie testy przeszly.")
    return 0


if __name__ == "__main__":
    sys.exit(run_all())

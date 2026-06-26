"""Testy logiki paliwa: limit komunikatow, filtry zbednych, srednia po pit stopie."""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from gt7_engineer.config import EngineerConfig
from gt7_engineer.engineer import RaceEngineer
from gt7_engineer.telemetry import GT7Packet

FUEL_KEYS = {"fuel", "fuel_finish", "fuel_runs_out", "fuel_refuel"}


class Clock:
    def __init__(self) -> None:
        self.t = 0.0

    def __call__(self) -> float:
        return self.t

    def tick(self, dt: float = 1.0) -> None:
        self.t += dt


def pkt(lap, fuel, *, total_laps=20, cap=60.0, speed_kph=150.0, last_ms=95000,
        on_track=True, car=42):
    return GT7Packet(
        current_lap=lap, total_laps=total_laps, on_track=on_track,
        current_fuel=fuel, fuel_capacity=cap, speed_mps=speed_kph / 3.6,
        position=(0.0, 0.0, 0.0), throttle=200, brake=0,
        last_lap_ms=last_ms, best_lap_ms=91000, car_code=car,
        position_in_race=0, total_cars=0,
    )


def _cfg(**kw):
    base = dict(
        announce_lap_times=False, announce_position_changes=False,
        announce_best_lap=False, announce_corner_tyres=False,
        announce_delta=False, announce_ref_sectors=False,
        min_laps_for_fuel_calc=1, fuel_avg_window=3,
    )
    base.update(kw)
    return EngineerConfig(**base)


def _drive_race(eng, clk, fuels_at_line, *, total_laps=20, per_lap_msgs=None,
                refill_during_lap=None):
    """Symuluje wyscig: fuels_at_line[i] = paliwo przy przecieciu linii na okr. i+2.

    refill_during_lap: (numer_okrazenia, paliwo_po_tankowaniu) - dotankowanie
    w srodku tego okrazenia (predkosc ~0, skok paliwa w gore).
    Zwraca liste komunikatow paliwowych per okrazenie (gdy per_lap_msgs=list).
    """
    # Pierwszy pakiet: polaczenie (okrazenie 1).
    f = fuels_at_line[0] + 2.0
    eng.update(pkt(1, f, total_laps=total_laps))
    clk.tick(5)
    lap = 1
    for i, fuel_line in enumerate(fuels_at_line):
        target_lap = i + 2
        # Srodek okrazenia: pare ramek, paliwo opada liniowo.
        for k in range(3):
            mid = f - (f - fuel_line) * (k + 1) / 4.0
            eng.update(pkt(lap, mid, total_laps=total_laps))
            clk.tick(20)
        if refill_during_lap and refill_during_lap[0] == lap:
            # Pit stop: paliwo skacze w gore przy ~zerowej predkosci.
            f = refill_during_lap[1]
            eng.update(pkt(lap, f, total_laps=total_laps, speed_kph=0.0))
            clk.tick(20)
            # Dojazd do linii po tankowaniu (zuzycie czesci okrazenia).
            fuel_line = f - 1.0
        # Przeciecie linii.
        anns = eng.update(pkt(target_lap, fuel_line, total_laps=total_laps))
        if per_lap_msgs is not None:
            per_lap_msgs.append([a for a in anns if a.key in FUEL_KEYS])
        clk.tick(30)
        lap = target_lap
        f = fuel_line
    return eng


def test_max_one_fuel_message_per_lap():
    """Scenariusz deficytu (stara wersja dawala 2-3 komunikaty na okrazenie)."""
    clk = Clock()
    eng = RaceEngineer(_cfg(), clock=clk)
    per_lap: list = []
    # 20 paliwa, 2/okr., 20 okrazen -> brakuje duzo -> duzo kandydatow.
    fuels = [20.0 - 2.0 * i for i in range(1, 9)]
    _drive_race(eng, clk, fuels, total_laps=20, per_lap_msgs=per_lap)
    for i, msgs in enumerate(per_lap):
        assert len(msgs) <= 1, f"okr. {i + 2}: {len(msgs)} komunikatow paliwa: " \
                               f"{[m.key for m in msgs]}"
    # W deficycie cos jednak mowi (nie wyciszylismy wszystkiego).
    assert any(msgs for msgs in per_lap), "zadnego komunikatu paliwowego w deficycie"


def test_priority_critical_wins():
    """Przy bardzo malo paliwa jedyny komunikat to krytyczny (nie strategia)."""
    clk = Clock()
    eng = RaceEngineer(_cfg(fuel_critical_laps=1.5), clock=clk)
    per_lap: list = []
    fuels = [10.0 - 2.0 * i for i in range(1, 5)]  # konczy na 2.0 (1 okr. zapasu)
    _drive_race(eng, clk, fuels, total_laps=20, per_lap_msgs=per_lap)
    last = per_lap[-1]
    assert len(last) == 1 and last[0].key == "fuel", f"oczekiwano krytycznego: {last}"
    from gt7_engineer.speech import Priority
    assert last[0].priority == Priority.CRITICAL


def test_runs_out_suppressed_when_beyond_race():
    """Deficyt tylko przez margines: 'starczy do okr. X' z X >= mety - cisza."""
    clk = Clock()
    # Margines 0.5 okr.; paliwo wystarcza na pelny dystans, ale nie na margines.
    eng = RaceEngineer(_cfg(fuel_target_margin_laps=0.5,
                            fuel_max_messages_per_lap=3), clock=clk)
    keys: list = []
    per_lap: list = []
    fuels = [30.5 - 2.0 * i for i in range(1, 9)]
    _drive_race(eng, clk, fuels, total_laps=15, per_lap_msgs=per_lap)
    for msgs in per_lap:
        keys.extend(m.key for m in msgs)
    assert "fuel_runs_out" not in keys, f"runs_out mimo paliwa do mety: {keys}"


def test_ok_to_finish_silent_by_default_configurable():
    """Gdy paliwa starcza: domyslnie cisza; po wlaczeniu opcji - potwierdzenie."""
    for enabled in (False, True):
        clk = Clock()
        eng = RaceEngineer(_cfg(announce_fuel_ok_to_finish=enabled), clock=clk)
        per_lap: list = []
        # 55 paliwa, 1/okr., 10 okrazen -> ogromny zapas.
        fuels = [55.0 - 1.0 * i for i in range(1, 8)]
        _drive_race(eng, clk, fuels, total_laps=10, per_lap_msgs=per_lap)
        finish_keys = [m.key for msgs in per_lap for m in msgs if m.key == "fuel_finish"]
        if enabled:
            assert finish_keys, "wlaczone potwierdzenie, a nic nie powiedzial"
        else:
            assert not finish_keys, f"domyslnie mialo byc cicho: {finish_keys}"


def test_pit_refill_does_not_skew_average():
    """Okrazenie z tankowaniem NIE wnosi probki zuzycia (srednia bez zmian)."""
    clk = Clock()
    eng = RaceEngineer(_cfg(), clock=clk)
    # Okr. 2-5: zuzycie 2.0/okr. (probka z okr. 1 pomijana - wjazd w srodku kolka).
    fuels = [50.0 - 2.0 * i for i in range(1, 5)]
    _drive_race(eng, clk, fuels, total_laps=20)
    hist_before = list(eng.state.fuel_per_lap_history)
    avg_before = eng.state.avg_fuel_per_lap
    assert all(abs(v - 2.0) < 1e-6 for v in hist_before), hist_before
    assert abs(avg_before - 2.0) < 1e-6

    # Okrazenie 5 z tankowaniem w srodku (42 -> 60), do linii spala 1.0.
    eng.pop_fuel_debug()
    _ = _drive_race  # czytelnosc
    f = fuels[-1]
    for k in range(2):
        eng.update(pkt(5, f - 0.3 * (k + 1), total_laps=20))
        clk.tick(20)
    eng.update(pkt(5, 60.0, total_laps=20, speed_kph=0.0))  # tankowanie
    clk.tick(20)
    eng.update(pkt(6, 59.0, total_laps=20))                  # linia po picie
    clk.tick(30)

    hist_after = list(eng.state.fuel_per_lap_history)
    assert hist_after == hist_before, \
        f"probka z okrazenia z pitem zaburzyla historie: {hist_before} -> {hist_after}"
    assert abs(eng.state.avg_fuel_per_lap - 2.0) < 1e-6
    debug = "\n".join(eng.pop_fuel_debug())
    assert "Tankowanie wykryte" in debug
    assert "POMINIETA" in debug

    # Nastepne pelne okrazenie znow liczy sie normalnie.
    for k in range(2):
        eng.update(pkt(6, 59.0 - 0.5 * (k + 1), total_laps=20))
        clk.tick(20)
    eng.update(pkt(7, 57.0, total_laps=20))
    assert abs(list(eng.state.fuel_per_lap_history)[-1] - 2.0) < 1e-6


def test_fuel_debug_lines_only_in_log():
    """pop_fuel_debug zwraca linie i czysci bufor; linie maja prefiks [PALIWO]."""
    clk = Clock()
    eng = RaceEngineer(_cfg(), clock=clk)
    fuels = [50.0 - 2.0 * i for i in range(1, 4)]
    _drive_race(eng, clk, fuels, total_laps=20)
    lines = eng.pop_fuel_debug()
    assert lines and all(ln.startswith("[PALIWO]") for ln in lines)
    assert eng.pop_fuel_debug() == []  # bufor wyczyszczony


def test_fuel_zero_limit_silences_everything():
    clk = Clock()
    eng = RaceEngineer(_cfg(fuel_max_messages_per_lap=0), clock=clk)
    per_lap: list = []
    fuels = [20.0 - 2.0 * i for i in range(1, 9)]
    _drive_race(eng, clk, fuels, total_laps=20, per_lap_msgs=per_lap)
    assert all(not msgs for msgs in per_lap), "limit 0 mial wyciszyc paliwo"


if __name__ == "__main__":
    failed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            try:
                fn()
                print(f"PASS {name}")
            except Exception as e:  # noqa: BLE001
                failed += 1
                print(f"FAIL {name}: {type(e).__name__}: {e}")
    sys.exit(1 if failed else 0)

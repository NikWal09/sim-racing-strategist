"""Testy okrazenia referencyjnego, bazy nazw aut i raportu opon."""

from __future__ import annotations

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from gt7_engineer.data import car_name
from gt7_engineer.engineer.recorder import CHANNELS
from gt7_engineer.engineer.reference import ReferenceDelta


R = 200.0                       # promien petli testowej [m]
CIRC = 2 * math.pi * R          # obwod ~1257 m
REF_SPEED = 50.0                # predkosc referencji [m/s]


def _circle_pos(dist: float) -> tuple[float, float, float]:
    a = 2 * math.pi * (dist / CIRC)
    return (R * math.cos(a), 0.0, R * math.sin(a))


def _make_ref_file(tmp_path, speed=REF_SPEED, step_m=2.0):
    """Nagranie okrazenia po okregu ze stala predkoscia, w formacie recordera."""
    samples = []
    d = 0.0
    while d < CIRC:
        x, y, z = _circle_pos(d)
        t = d / speed
        # Wiersz zgodny z CHANNELS (gaz/hamulec/kierownica/bieg/rpm/opony - atrapy).
        samples.append([round(t, 3), x, y, z, speed * 3.6, 1.0, 0.0, 0.1, 4, 9000,
                        80.0, 82.0, 78.0, 79.0])
        d += step_m
    lap_ms = int(CIRC / speed * 1000)
    data = {
        "session_id": "test", "car_code": 3334, "car_name": "Audi R18 '16",
        "lap_number": 2, "lap_ms": lap_ms, "lap_time": "x",
        "recorded_at": "2026-06-11T10:00:00", "track_key": "L1250-W400-H400",
        "fingerprint": {"length_m": CIRC, "width_m": 2 * R, "height_m": 2 * R},
        "sample_hz": 25.0, "channels": list(CHANNELS), "samples": samples,
    }
    path = str(tmp_path / "ref.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f)
    return path, lap_ms


def _drive(rd: ReferenceDelta, speed: float, dt: float = 0.05):
    """Przejazd pelnego okrazenia ze stala predkoscia; zwraca liste wynikow sektorow."""
    now = 100.0
    rd.start_lap(now, speed_mps=speed, lap_no=2)
    sectors = []
    d = 0.0
    while d < CIRC:
        now += dt
        d += speed * dt
        rd.update(_circle_pos(min(d, CIRC - 0.01)), speed, now, lap_no=2)
        r = rd.pop_sector_result()
        if r:
            sectors.append(r)
    rd.on_lap_complete(int(CIRC / speed * 1000), now, speed, 3)
    r = rd.pop_sector_result()
    if r:
        sectors.append(r)
    return sectors, rd


def test_load_and_resample(tmp_path):
    path, lap_ms = _make_ref_file(tmp_path)
    rd = ReferenceDelta(sectors=3)
    info = rd.load(path)
    assert rd.loaded
    assert info.car_name == "Audi R18 '16"
    assert rd.ref_ms == lap_ms
    # Przepróbkowanie: kolejne probki >= 5 m od siebie.
    for a, b in zip(rd.ref, rd.ref[1:]):
        assert math.dist(a[:3], b[:3]) >= ReferenceDelta.RESAMPLE_M - 1e-6
    # Granice sektorow: 2 dla 3 sektorow, rosnace.
    assert len(rd._sector_bounds) == 2
    assert rd._sector_bounds[0] < rd._sector_bounds[1]


def test_same_pace_delta_near_zero(tmp_path):
    path, _ = _make_ref_file(tmp_path)
    rd = ReferenceDelta(sectors=3)
    rd.load(path)
    _sectors, rd = _drive(rd, REF_SPEED)
    d = rd.current_delta()
    assert d is not None and abs(d) < 0.3, f"delta {d}"


def test_slower_pace_positive_delta_and_sectors(tmp_path):
    path, _ = _make_ref_file(tmp_path)
    rd = ReferenceDelta(sectors=3)
    rd.load(path)
    slow = 45.0  # ~2.8 s wolniej na okrazeniu
    sectors, rd = _drive(rd, slow)
    expected_total = CIRC / slow - CIRC / REF_SPEED
    d = rd.current_delta()
    # current_delta po on_lap_complete dotyczy starego kolka - bierzemy sektory.
    assert len(sectors) == 3, f"sektory: {sectors}"
    total = sum(diff for _no, diff in sectors)
    assert abs(total - expected_total) < 0.6, f"suma sektorow {total} vs {expected_total}"
    for no, diff in sectors:
        assert diff > 0.3, f"sektor {no}: {diff}"


def test_reference_survives_reset_cleared_by_clear(tmp_path):
    path, _ = _make_ref_file(tmp_path)
    rd = ReferenceDelta()
    rd.load(path)
    rd.reset()  # zmiana auta itd.
    assert rd.loaded and rd.ref is not None
    rd.clear()
    assert not rd.loaded and rd.ref is None


def test_load_rejects_bad_file(tmp_path):
    bad = str(tmp_path / "bad.json")
    with open(bad, "w", encoding="utf-8") as f:
        json.dump({"channels": ["t", "x"], "samples": [[0, 1]], "lap_ms": 0}, f)
    rd = ReferenceDelta()
    try:
        rd.load(bad)
        raise AssertionError("powinien byc ValueError")
    except ValueError:
        pass


def test_car_name_lookup():
    assert car_name(3334) == "Audi R18 '16"
    assert car_name(None) == "Nieznane auto"
    assert car_name(999999) == "Auto 999999"


def test_recorder_channels_include_tyres():
    for c in ("tyre_fl", "tyre_fr", "tyre_rl", "tyre_rr"):
        assert c in CHANNELS
    # Pozycje x/z bez zmian (zgodnosc ze starszymi testami fingerprintu).
    assert CHANNELS.index("x") == 1 and CHANNELS.index("z") == 3


def test_tyre_report_builds_html(tmp_path):
    path, _ = _make_ref_file(tmp_path)
    from tools.tyre_report import analyze_lap, build_report_html
    lap = json.load(open(path, encoding="utf-8"))
    lap["_file"] = "ref.json"
    an = analyze_lap(lap)
    assert an is not None
    assert an["max"][1] == 82.0  # FR ma najwyzsza temperature w atrapach
    html = build_report_html([lap])
    assert html.startswith("<!DOCTYPE html>")
    assert "Raport temperatur opon" in html
    assert "Audi R18" in html


def test_tyre_report_skips_old_recordings(tmp_path):
    from tools.tyre_report import build_report_html
    old = {
        "channels": ["t", "x", "y", "z", "speed_kph", "throttle", "brake",
                     "steering", "gear", "rpm"],
        "samples": [[0, 0, 0, 0, 100, 1, 0, 0, 4, 9000]],
        "track_key": "L100-W0-H0", "lap_number": 1, "lap_time": "x",
    }
    html = build_report_html([old])
    assert "Pomini" in html  # adnotacja o pominietych nagraniach


if __name__ == "__main__":
    import inspect
    failed = 0
    tests = [(n, f) for n, f in sorted(globals().items()) if n.startswith("test_")]
    import tempfile
    from pathlib import Path
    for name, fn in tests:
        try:
            kwargs = {}
            if "tmp_path" in inspect.signature(fn).parameters:
                kwargs["tmp_path"] = Path(tempfile.mkdtemp())
            fn(**kwargs)
            print(f"PASS {name}")
        except Exception as e:  # noqa: BLE001
            failed += 1
            print(f"FAIL {name}: {type(e).__name__}: {e}")
    sys.exit(1 if failed else 0)

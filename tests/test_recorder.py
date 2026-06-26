"""Testy nagrywania telemetrii: segmentacja okrazen, fingerprint, zapis i viewer."""

from __future__ import annotations

import glob
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from gt7_engineer.config import RecordingConfig
from gt7_engineer.engineer.recorder import TelemetryRecorder
from gt7_engineer.telemetry import GT7Packet


class Clock:
    """Sterowalny zegar - rosnie tylko gdy wywolamy tick()."""

    def __init__(self) -> None:
        self.t = 0.0

    def __call__(self) -> float:
        return self.t

    def tick(self, dt: float = 0.06) -> None:
        self.t += dt


def pkt(lap, x, z, *, on_track=True, fuel=50.0, cap=60.0, speed_kph=120.0,
        throttle=255, brake=0, steer=0.1, gear=4, rpm=9000.0, last_lap_ms=-1, car=42):
    return GT7Packet(
        current_lap=lap, position=(x, 0.0, z), on_track=on_track,
        current_fuel=fuel, fuel_capacity=cap, speed_mps=speed_kph / 3.6,
        throttle=throttle, brake=brake, wheel_rotation_rad=steer,
        gear=gear, rpm=rpm, last_lap_ms=last_lap_ms, car_code=car,
    )


def _loop_points(n=40, r=200.0):
    """Punkty na okregu (zamknieta petla = realistyczny ksztalt toru)."""
    return [(r * math.cos(2 * math.pi * i / n), r * math.sin(2 * math.pi * i / n))
            for i in range(n)]


def _make_recorder(tmp_path):
    cfg = RecordingConfig(enabled=True, output_dir=str(tmp_path / "rec"),
                          sample_hz=20.0, min_lap_seconds=10.0)
    return TelemetryRecorder(cfg, clock=Clock())


def _drive_lap(rec, clk, lap_no, pts, last_lap_ms=-1):
    """Przejazd jednego okrazenia: po jednej ramce na punkt petli."""
    saved = None
    for (x, z) in pts:
        s = rec.update(pkt(lap_no, x, z, last_lap_ms=last_lap_ms))
        if s:
            saved = s
        clk.tick()
    return saved


def test_outlap_not_saved_then_timed_lap_saved(tmp_path):
    rec = _make_recorder(tmp_path)
    clk = rec._clock
    pts = _loop_points()

    # Out-lap (lap 0) - dolaczamy w srodku, brak czasu.
    _drive_lap(rec, clk, 0, pts, last_lap_ms=-1)
    # Przeciecie linii: 0 -> 1 (out-lap zamkniety, NIE zapisany).
    s1 = rec.update(pkt(1, pts[0][0], pts[0][1], last_lap_ms=-1)); clk.tick()
    assert s1 is None

    # Okrazenie 1 (juz pelne, liczone od linii).
    _drive_lap(rec, clk, 1, pts, last_lap_ms=-1)
    # Przeciecie 1 -> 2 z czasem 95.000 -> zapis okrazenia 1.
    saved = rec.update(pkt(2, pts[0][0], pts[0][1], last_lap_ms=95000)); clk.tick()
    assert saved is not None
    assert os.path.exists(saved)

    data = json.loads(open(saved, encoding="utf-8").read())
    assert data["lap_ms"] == 95000
    assert data["lap_number"] == 1
    assert data["car_code"] == 42
    assert len(data["samples"]) >= 2
    assert data["channels"][0] == "t"
    assert "track_key" in data and data["track_key"].startswith("L")


def test_fingerprint_and_track_key(tmp_path):
    """Fingerprint jest deterministyczny i rozroznia tory roznej wielkosci."""
    fp1 = TelemetryRecorder._fingerprint([[0, x, 0, z, 100, 1, 0, 0, 4, 9000]
                                          for (x, z) in _loop_points()])
    fp2 = TelemetryRecorder._fingerprint([[0, x, 0, z, 100, 1, 0, 0, 4, 9000]
                                          for (x, z) in _loop_points()])
    # Te same probki -> identyczny fingerprint i klucz (determinizm).
    assert fp1 == fp2
    assert TelemetryRecorder._track_key(fp1) == TelemetryRecorder._track_key(fp2)
    # Wyraznie wiekszy tor -> inny klucz (rozroznialnosc).
    fpBig = TelemetryRecorder._fingerprint([[0, x, 0, z, 100, 1, 0, 0, 4, 9000]
                                            for (x, z) in _loop_points(r=600.0)])
    assert TelemetryRecorder._track_key(fpBig) != TelemetryRecorder._track_key(fp1)
    assert fpBig["length_m"] > fp1["length_m"]


def test_pit_return_invalidates_lap(tmp_path):
    """Powrot do boksu (skok paliwa przy ~0 km/h) uniewaznia biezace okrazenie."""
    rec = _make_recorder(tmp_path)
    clk = rec._clock
    pts = _loop_points()

    _drive_lap(rec, clk, 0, pts, last_lap_ms=-1)
    rec.update(pkt(1, pts[0][0], pts[0][1], last_lap_ms=-1)); clk.tick()
    # W trakcie okrazenia 1 wracamy do boksu: paliwo skacze w gore, predkosc ~0.
    for (x, z) in pts[:10]:
        rec.update(pkt(1, x, z, last_lap_ms=-1)); clk.tick()
    rec.update(pkt(1, pts[10][0], pts[10][1], fuel=60.0, speed_kph=0.0, last_lap_ms=-1)); clk.tick()
    for (x, z) in pts[11:]:
        rec.update(pkt(1, x, z, fuel=60.0, last_lap_ms=-1)); clk.tick()
    # Przeciecie 1 -> 2: bufor byl uniewazniony, wiec NIE zapisujemy.
    saved = rec.update(pkt(2, pts[0][0], pts[0][1], last_lap_ms=95000)); clk.tick()
    assert saved is None


def test_too_short_lap_rejected(tmp_path):
    rec = _make_recorder(tmp_path)
    clk = rec._clock
    pts = _loop_points()
    _drive_lap(rec, clk, 0, pts)
    rec.update(pkt(1, pts[0][0], pts[0][1])); clk.tick()
    _drive_lap(rec, clk, 1, pts)
    # Czas 5 s < min_lap_seconds (10 s) -> odrzucone.
    saved = rec.update(pkt(2, pts[0][0], pts[0][1], last_lap_ms=5000)); clk.tick()
    assert saved is None


def test_disabled_recorder_does_nothing(tmp_path):
    cfg = RecordingConfig(enabled=False, output_dir=str(tmp_path / "rec"))
    rec = TelemetryRecorder(cfg, clock=Clock())
    assert rec.update(pkt(1, 0, 0, last_lap_ms=95000)) is None
    assert not os.path.isdir(str(tmp_path / "rec"))


def test_viewer_builds_html(tmp_path):
    # Najpierw nagraj jedno okrazenie.
    rec = _make_recorder(tmp_path)
    clk = rec._clock
    pts = _loop_points()
    _drive_lap(rec, clk, 0, pts)
    rec.update(pkt(1, pts[0][0], pts[0][1])); clk.tick()
    _drive_lap(rec, clk, 1, pts)
    saved = rec.update(pkt(2, pts[0][0], pts[0][1], last_lap_ms=95000)); clk.tick()
    assert saved is not None

    from tools.telemetry_viewer import load_laps, build_html
    laps = load_laps(str(tmp_path / "rec"))
    assert len(laps) == 1
    html = build_html(laps)
    assert html.startswith("<!DOCTYPE html>")
    assert "/*__DATA__*/" not in html        # placeholder podmieniony
    assert "const LAPS =" in html
    assert laps[0]["track_key"] in html

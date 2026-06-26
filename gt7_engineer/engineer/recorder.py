"""Nagrywanie telemetrii per-okrazenie (w stylu Garage 61).

Recorder konsumuje strumien pakietow GT7 i buforuje probki biezacego okrazenia
(czas, pozycja x,y,z, predkosc, gaz, hamulec, kat kierownicy, bieg, rpm). Po
przecieciu linii start/meta zapisuje zakonczone, poprawne okrazenie do osobnego
pliku JSON. Kazdemu okrazeniu liczymy "odcisk toru" (fingerprint): dlugosc sladu
i wymiary obrysu w plaszczyznie x-z. Z fingerprintu robimy track_key, ktory
pozwala automatycznie grupowac okrazenia z tego samego toru (do porownan).

Segmentacja okrazen dziala tak samo jak w analyzer.py: liczymy na inkrementach
pola current_lap, a powrot do boksu / cofniecie licznika / zmiana auta uniewaznia
biezacy bufor (oznaczamy go jako "niepelny", wiec nie zapiszemy out-lapu ani
smieci po resecie w boksie).
"""

from __future__ import annotations

import json
import math
import os
import time
from dataclasses import dataclass, field

from ..config import RecordingConfig
from ..data import car_name
from ..telemetry import GT7Packet

# Kanaly zapisywane dla kazdej probki (kolejnosc = kolejnosc w wierszu "samples").
# Temperatury opon (FL, FR, RL, RR) dodano na KONCU listy - starsze nagrania ich
# nie maja, dlatego odbiorcy (viewer, raport opon) musza szukac kanalu po nazwie.
CHANNELS = ["t", "x", "y", "z", "speed_kph", "throttle", "brake", "steering", "gear", "rpm",
            "tyre_fl", "tyre_fr", "tyre_rl", "tyre_rr", "fuel_pct"]


@dataclass
class _LapBuffer:
    """Bufor probek biezacego okrazenia."""

    start_t: float = 0.0
    clean: bool = False          # czy okrazenie zaczelo sie dokladnie na linii start/meta
    samples: list[list[float]] = field(default_factory=list)
    last_sample_t: float = -1e9  # czas ostatniej zapisanej probki (do throttlingu Hz)


class TelemetryRecorder:
    """Wejscie: pakiet -> (czasem) zapisany plik okrazenia.

    Wywoluj `update(packet)` w kazdej iteracji petli odbioru. Metoda zwraca
    sciezke zapisanego pliku, gdy wlasnie zamknieto poprawne okrazenie, albo
    None w pozostalych przypadkach.
    """

    # Powrot do boksu przez menu pauzy: paliwo skacze w gore przy niemal zerowej
    # predkosci (jak w analyzer.py). To pewny sygnal, by uniewaznic biezacy bufor.
    FUEL_REFILL_EPS = 0.05
    PIT_RETURN_MAX_KPH = 5.0

    def __init__(self, cfg: RecordingConfig, clock=time.monotonic, base_dir: str = ".") -> None:
        self.cfg = cfg
        self._clock = clock
        # Katalog wyjsciowy liczymy wzgledem podanego base_dir (folder projektu).
        self.out_dir = cfg.output_dir if os.path.isabs(cfg.output_dir) \
            else os.path.join(base_dir, cfg.output_dir)
        self._min_dt = 1.0 / cfg.sample_hz if cfg.sample_hz > 0 else 0.0

        self._buf = _LapBuffer()
        self._cur_lap: int | None = None
        self._car_code: int | None = None
        self._last_fuel: float | None = None
        # Identyfikator sesji - wspolny dla okrazen z jednego "wjazdu na tor".
        self._session_id = time.strftime("%Y%m%d_%H%M%S")

    # --- API ---

    def update(self, p: GT7Packet) -> str | None:
        if not self.cfg.enabled:
            return None
        if p.paused or p.loading:
            return None

        # Pauza/menu/powrot do garazu - biezace okrazenie przestaje byc pelne.
        if not p.on_track:
            self._invalidate("menu")
            return None

        # Zmiana auta = nowa sesja, czysty start.
        if self._car_code is None:
            self._car_code = p.car_code
        elif p.car_code != self._car_code:
            self._car_code = p.car_code
            self._session_id = time.strftime("%Y%m%d_%H%M%S")
            self._cur_lap = None
            self._invalidate("car_change")
            self._last_fuel = None

        now = self._clock()

        # Powrot do boksu (dotankowanie przy ~zerowej predkosci) - uniewaznij bufor.
        if (self._last_fuel is not None and p.fuel_capacity > 0
                and p.current_fuel > self._last_fuel + self.FUEL_REFILL_EPS
                and p.speed_kph <= self.PIT_RETURN_MAX_KPH):
            self._invalidate("pit")
        self._last_fuel = p.current_fuel

        saved: str | None = None

        # Segmentacja okrazen na podstawie current_lap.
        if self._cur_lap is None:
            # Pierwszy pakiet w sesji - dolaczamy w srodku okrazenia (niepelne).
            self._cur_lap = p.current_lap
            self._start_buffer(now, clean=False)
        elif p.current_lap < self._cur_lap:
            # Licznik cofnal sie (reset w boksie) - zacznij od nowa, niepelne.
            self._cur_lap = p.current_lap
            self._start_buffer(now, clean=False)
        elif p.current_lap > self._cur_lap:
            # Przeciecie linii start/meta - zamknij poprzednie okrazenie.
            completed = self._buf
            prev_lap_no = self._cur_lap
            self._cur_lap = p.current_lap
            if self._is_saveable(completed, p.last_lap_ms):
                saved = self._save_lap(completed, p.last_lap_ms, prev_lap_no)
            # Nowe okrazenie zaczyna sie dokladnie na linii -> pelne.
            self._start_buffer(now, clean=True)

        self._sample(p, now)
        return saved

    # --- Wewnetrzne ---

    def _start_buffer(self, now: float, clean: bool) -> None:
        self._buf = _LapBuffer(start_t=now, clean=clean)

    def _invalidate(self, reason: str) -> None:
        """Oznacz biezacy bufor jako niepelny i wyczysc probki."""
        self._buf = _LapBuffer(start_t=self._clock(), clean=False)

    def _sample(self, p: GT7Packet, now: float) -> None:
        if self._min_dt > 0 and (now - self._buf.last_sample_t) < self._min_dt:
            return
        self._buf.last_sample_t = now
        x, y, z = p.position
        self._buf.samples.append([
            round(now - self._buf.start_t, 3),
            round(x, 3), round(y, 3), round(z, 3),
            round(p.speed_kph, 2),
            round(p.throttle / 255.0, 4),
            round(p.brake / 255.0, 4),
            round(p.wheel_rotation_rad, 4),
            int(p.gear),
            round(p.rpm, 1),
            round(p.tyre_temp[0], 1),
            round(p.tyre_temp[1], 1),
            round(p.tyre_temp[2], 1),
            round(p.tyre_temp[3], 1),
            round(p.fuel_pct, 2),
        ])

    def _is_saveable(self, buf: _LapBuffer, last_lap_ms: int) -> bool:
        if not buf.clean:
            return False
        if last_lap_ms is None or last_lap_ms <= 0:
            return False  # brak zmierzonego czasu (np. out-lap)
        if len(buf.samples) < 2:
            return False
        if last_lap_ms < self.cfg.min_lap_seconds * 1000:
            return False
        return True

    @staticmethod
    def _fingerprint(samples: list[list[float]]) -> dict:
        """Odcisk toru z sladu: dlugosc oraz wymiary obrysu w plaszczyznie x-z."""
        xi, zi = CHANNELS.index("x"), CHANNELS.index("z")
        xs = [s[xi] for s in samples]
        zs = [s[zi] for s in samples]
        length = 0.0
        for i in range(1, len(samples)):
            dx = samples[i][xi] - samples[i - 1][xi]
            dz = samples[i][zi] - samples[i - 1][zi]
            length += math.hypot(dx, dz)
        width = max(xs) - min(xs)
        height = max(zs) - min(zs)
        return {
            "length_m": round(length, 1),
            "width_m": round(width, 1),
            "height_m": round(height, 1),
        }

    @staticmethod
    def _track_key(fp: dict) -> str:
        """Klucz toru z fingerprintu (kwantyzacja -> okrazenia z 1 toru sa rowne).

        Dlugosc do 50 m, obrys do 20 m. Dwa okrazenia z tego samego toru maja
        praktycznie identyczna dlugosc i obrys, wiec wpadaja do tej samej grupy.
        """
        ln = round(fp["length_m"] / 50.0) * 50
        w = round(fp["width_m"] / 20.0) * 20
        h = round(fp["height_m"] / 20.0) * 20
        return f"L{ln}-W{w}-H{h}"

    def _save_lap(self, buf: _LapBuffer, last_lap_ms: int, lap_no: int) -> str | None:
        fp = self._fingerprint(buf.samples)
        track_key = self._track_key(fp)
        data = {
            "session_id": self._session_id,
            "car_code": self._car_code,
            "car_name": car_name(self._car_code),
            "lap_number": lap_no,
            "lap_ms": int(last_lap_ms),
            "lap_time": GT7Packet.format_laptime(int(last_lap_ms)),
            "recorded_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "track_key": track_key,
            "fingerprint": fp,
            "sample_hz": self.cfg.sample_hz,
            "channels": CHANNELS,
            "samples": buf.samples,
        }
        try:
            os.makedirs(self.out_dir, exist_ok=True)
            fname = f"{self._session_id}_{track_key}_lap{lap_no:03d}_{int(last_lap_ms)}ms.json"
            path = os.path.join(self.out_dir, fname)
            with open(path, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
            return path
        except OSError:
            # Blad zapisu nie moze wywrocic petli telemetrii - po cichu pomijamy.
            return None

"""Okrążenie referencyjne — delta na żywo do NAGRANEGO okrążenia (z pliku).

Użytkownik wybiera w GUI dowolne nagrane okrążenie (także z INNEGO auta — np.
porównanie dwóch pojazdów na tym samym torze). Ślad referencji wczytujemy z
pliku JSON recordera i liczymy do niego deltę dokładnie tą samą metodą
pozycyjną co `DeltaTracker` (najbliższy punkt śladu + rzut na odcinek).

Dodatkowo ślad referencji dzielimy na sektory (domyślnie 3, równe czasowo).
Przy przekroczeniu granicy sektora znamy zmianę delty w tym sektorze, więc
inżynier może powiedzieć "tracisz pół sekundy w sektorze 2".
"""

from __future__ import annotations

import json
import math
import os
from dataclasses import dataclass

from .delta import DeltaTracker, Sample


@dataclass
class ReferenceInfo:
    """Metadane wczytanej referencji (do GUI i komunikatów)."""

    path: str
    car_code: int | None
    car_name: str
    lap_time: str
    lap_ms: int
    track_key: str


class ReferenceDelta(DeltaTracker):
    """DeltaTracker ze STAŁĄ referencją z pliku nagrania + sektory.

    Różnice względem klasy bazowej:
      * referencja nigdy nie jest nadpisywana najszybszym kółkiem sesji,
      * po przekroczeniu granicy sektora wystawia wynik sektora
        (pop_sector_result), liczony jako zmiana delty od początku sektora.
    """

    # Minimalny odstęp między próbkami śladu po przepróbkowaniu [m] — taki sam
    # jak SAMPLE_EVERY_M w DeltaTracker, by okno wyszukiwania działało tak samo.
    RESAMPLE_M = DeltaTracker.SAMPLE_EVERY_M

    def __init__(self, min_delta_s: float = 0.15, sectors: int = 3) -> None:
        self.sectors = max(1, int(sectors))
        self.info: ReferenceInfo | None = None
        self._sector_bounds: list[int] = []   # indeksy próbek granic sektorów
        super().__init__(min_delta_s)

    def reset(self) -> None:
        # reset() klasy bazowej kasuje ref - u nas referencja pochodzi z PLIKU
        # i ma przetrwać resety (zmiana auta itd.). Usuwa ją tylko clear().
        keep_ref = getattr(self, "ref", None)
        keep_ms = getattr(self, "ref_ms", None)
        super().reset()
        self.ref = keep_ref
        self.ref_ms = keep_ms
        # Stan sektorów biezacego okrazenia.
        self._sector = 0                       # ile granic juz przekroczono
        self._sector_start_delta: float | None = None
        self._pending_sector: tuple[int, float] | None = None

    # --- Wczytywanie referencji ---

    def load(self, path: str) -> ReferenceInfo:
        """Wczytuje plik nagrania recordera i ustawia go jako referencję.

        Rzuca ValueError, gdy plik nie jest poprawnym nagraniem okrążenia.
        """
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        channels = data.get("channels") or []
        samples = data.get("samples") or []
        lap_ms = int(data.get("lap_ms") or 0)
        try:
            it = channels.index("t")
            ix = channels.index("x")
            iy = channels.index("y")
            iz = channels.index("z")
        except ValueError as e:
            raise ValueError(f"Nagranie bez kanałów pozycji: {e}") from e
        if len(samples) < 2 or lap_ms <= 0:
            raise ValueError("Nagranie nie zawiera pełnego okrążenia z czasem.")

        ref = self._resample([(s[ix], s[iy], s[iz], s[it]) for s in samples])
        if len(ref) < 2:
            raise ValueError("Za mało próbek po przepróbkowaniu śladu.")

        self.reset()
        self.ref = ref
        self.ref_ms = lap_ms
        self._sector_bounds = self._make_sector_bounds(ref)
        self.info = ReferenceInfo(
            path=path,
            car_code=data.get("car_code"),
            car_name=data.get("car_name") or f"Auto {data.get('car_code')}",
            lap_time=data.get("lap_time") or "?",
            lap_ms=lap_ms,
            track_key=data.get("track_key") or "?",
        )
        return self.info

    @classmethod
    def _resample(cls, pts: list[Sample]) -> list[Sample]:
        """Przerzedza ślad tak, by kolejne próbki dzieliło >= RESAMPLE_M metrów.

        Recorder próbkuje czasem (20 Hz), więc przy małej prędkości próbki są
        gęste — okno wyszukiwania DeltaTrackera zakłada odstęp ~5 m.
        """
        out: list[Sample] = [pts[0]]
        for p in pts[1:]:
            last = out[-1]
            d = math.dist((p[0], p[1], p[2]), (last[0], last[1], last[2]))
            if d >= cls.RESAMPLE_M:
                out.append(p)
        return out

    def _make_sector_bounds(self, ref: list[Sample]) -> list[int]:
        """Indeksy próbek kończących sektory 1..N-1 (równe czasowo)."""
        total_t = ref[-1][3]
        bounds: list[int] = []
        k = 1
        for i, s in enumerate(ref):
            if k >= self.sectors:
                break
            if s[3] >= total_t * k / self.sectors:
                bounds.append(i)
                k += 1
        return bounds

    @property
    def loaded(self) -> bool:
        return self.ref is not None and self.info is not None

    def clear(self) -> None:
        """Usuwa referencję (delta przestaje być liczona)."""
        self.info = None
        self._sector_bounds = []
        self.ref = None
        self.ref_ms = None
        self.reset()

    # --- Nadpisania DeltaTrackera ---

    def on_lap_complete(self, last_lap_ms: int, now: float,
                        speed_mps: float = 0.0, lap_no: int = 0) -> None:
        """Linia start/meta: NIE nadpisujemy referencji, tylko zaczynamy kółko.

        Ostatni sektor kończy się na linii mety, więc jego wynik wystawiamy tu
        (start_lap czyści stan, dlatego liczymy przed i podstawiamy po nim).
        """
        pending: tuple[int, float] | None = None
        if (self._sector_bounds and self._sector >= len(self._sector_bounds)
                and self._cur_delta is not None
                and self._sector_start_delta is not None):
            pending = (self.sectors, self._cur_delta - self._sector_start_delta)
        self.start_lap(now, speed_mps, lap_no)
        if pending is not None:
            self._pending_sector = pending

    def start_lap(self, now: float, speed_mps: float = 0.0, lap_no: int = 0) -> None:
        super().start_lap(now, speed_mps, lap_no)
        self._sector = 0
        self._sector_start_delta = None
        self._pending_sector = None

    def update(self, pos, speed_mps: float, now: float, lap_no: int = 0) -> None:
        super().update(pos, speed_mps, now, lap_no)
        self._check_sector()

    # --- Sektory ---

    def _check_sector(self) -> None:
        """Po przekroczeniu granicy sektora wylicza zmianę delty w sektorze."""
        if not self._sector_bounds:
            return
        d = self._cur_delta
        if d is not None and self._sector_start_delta is None:
            # Pierwszy pomiar na tym okrazeniu - punkt odniesienia sektora.
            self._sector_start_delta = d
        if self._sector >= len(self._sector_bounds):
            return
        if self._ref_idx >= self._sector_bounds[self._sector]:
            sector_no = self._sector + 1
            self._sector += 1
            if d is not None and self._sector_start_delta is not None:
                self._pending_sector = (sector_no, d - self._sector_start_delta)
            self._sector_start_delta = d

    def pop_sector_result(self) -> tuple[int, float] | None:
        """(numer_sektora 1.., zmiana_delty[s]) ostatnio zamkniętego sektora.

        Dodatnia zmiana = strata do referencji w tym sektorze. None, gdy od
        ostatniego odczytu nie zamknięto sektora.
        """
        r = self._pending_sector
        self._pending_sector = None
        return r


def list_reference_candidates(recordings_dir: str) -> list[str]:
    """Ścieżki plików nagrań możliwych do użycia jako referencja."""
    if not os.path.isdir(recordings_dir):
        return []
    out = []
    for name in sorted(os.listdir(recordings_dir)):
        if name.endswith(".json") and not name.startswith("_"):
            out.append(os.path.join(recordings_dir, name))
    return out

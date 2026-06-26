"""Dane statyczne: baza aut GT7 (kod -> nazwa).

Plik gt7_cars.csv (kolumny: code,name) pochodzi z bazy ddm999/gt7info
(ID auta z telemetrii + nazwa producenta i modelu). Wczytujemy go leniwie
i raz - kolejne wywolania korzystaja z cache w pamieci.
"""

from __future__ import annotations

import csv
import os

_CARS_CSV = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gt7_cars.csv")
_cache: dict[int, str] | None = None


def _load() -> dict[int, str]:
    global _cache
    if _cache is None:
        cars: dict[int, str] = {}
        try:
            with open(_CARS_CSV, "r", encoding="utf-8") as f:
                for row in csv.DictReader(f):
                    try:
                        cars[int(row["code"])] = row["name"].strip()
                    except (KeyError, ValueError):
                        continue
        except OSError:
            pass  # brak pliku = puste mapowanie (car_name zwroci fallback)
        _cache = cars
    return _cache


def car_name(code: int | None) -> str:
    """Nazwa auta dla kodu z telemetrii GT7. Fallback: 'Auto <kod>'."""
    if code is None:
        return "Nieznane auto"
    return _load().get(int(code), f"Auto {code}")

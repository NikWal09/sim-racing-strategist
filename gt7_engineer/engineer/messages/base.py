"""Wspolny interfejs komunikatow inzyniera dla wielu jezykow.

Kazdy jezyk (pl, en, ...) dziedziczy po `Messages` i implementuje metody zwracajace
gotowy do wypowiedzenia tekst. Wiele metod losuje jeden z kilku wariantow, zeby
inzynier brzmial mniej robotycznie. Formatowanie liczb/czasu jest jezykowo zalezne,
wiec realizuja je metody pomocnicze nadpisywane w podklasach.
"""

from __future__ import annotations

import random


class Messages:
    """Bazowy zestaw komunikatow. Podklasy nadpisuja wszystkie metody."""

    lang: str = "xx"
    # Nazwy naroznikow opon w kolejnosci telemetrii: FL, FR, RL, RR.
    corners: tuple[str, str, str, str] = ("FL", "FR", "RL", "RR")

    @staticmethod
    def _pick(*variants: str) -> str:
        """Losuje jeden z wariantow sformulowania."""
        return random.choice(variants)

    # --- Pomocnicze formatowanie (jezykowo zalezne) ---
    def number(self, value: float) -> str:  # pragma: no cover - abstrakcja
        raise NotImplementedError

    def laptime(self, ms: int) -> str:  # pragma: no cover - abstrakcja
        raise NotImplementedError

    # --- Komunikaty ---
    def radio_check(self) -> str:  # pragma: no cover
        raise NotImplementedError

    def connected(self) -> str:  # pragma: no cover
        raise NotImplementedError

    def lap_time(self, last_ms: int) -> str:  # pragma: no cover
        raise NotImplementedError

    def best_lap(self, best_ms: int) -> str:  # pragma: no cover
        raise NotImplementedError

    def fuel_laps_left(self, laps: float) -> str:  # pragma: no cover
        raise NotImplementedError

    def fuel_warning(self, laps: float) -> str:  # pragma: no cover
        raise NotImplementedError

    def fuel_critical(self, laps: float) -> str:  # pragma: no cover
        raise NotImplementedError

    def fuel_short_to_finish(self, short_laps: float) -> str:  # pragma: no cover
        raise NotImplementedError

    def fuel_ok_to_finish(self, margin_laps: float) -> str:  # pragma: no cover
        raise NotImplementedError

    def fuel_runs_out(self, lap: int) -> str:  # pragma: no cover
        raise NotImplementedError

    def fuel_save_per_lap(self, amount: float) -> str:  # pragma: no cover
        raise NotImplementedError

    def fuel_refuel_pct(self, pct: float) -> str:  # pragma: no cover
        raise NotImplementedError

    def gained_position(self, pos: int) -> str:  # pragma: no cover
        raise NotImplementedError

    def lost_position(self, pos: int) -> str:  # pragma: no cover
        raise NotImplementedError

    def last_lap(self) -> str:  # pragma: no cover
        raise NotImplementedError

    def delta_ahead(self, seconds: float) -> str:  # pragma: no cover
        raise NotImplementedError

    def delta_behind(self, seconds: float) -> str:  # pragma: no cover
        raise NotImplementedError

    def ref_sector_loss(self, sector: int, seconds: float) -> str:  # pragma: no cover
        """Strata czasu do okrazenia referencyjnego w danym sektorze."""
        raise NotImplementedError

    def ref_sector_gain(self, sector: int, seconds: float) -> str:  # pragma: no cover
        """Zysk do okrazenia referencyjnego w danym sektorze."""
        raise NotImplementedError

    def tyre_hot(self, corner: str, temp: float) -> str:  # pragma: no cover
        raise NotImplementedError

    def tyre_section_hot(self, section: int, total: int, corner: str, temp: float) -> str:  # pragma: no cover
        raise NotImplementedError

    def tyre_corner_hot(self, corner_no: int, tyre: str, temp: float) -> str:  # pragma: no cover
        """Feedback na biezaco: na ktorym zakrecie przegrzala sie ktora opona."""
        raise NotImplementedError

    def tyre_corner_worst(self, corner_no: int, tyre: str, temp: float) -> str:  # pragma: no cover
        """Analiza: zakret, na ktorym opony grzeja sie najmocniej w sesji."""
        raise NotImplementedError

    def finished(self, pos: int, total: int) -> str:  # pragma: no cover
        raise NotImplementedError

    def position(self, pos: int, total: int) -> str:  # pragma: no cover
        raise NotImplementedError

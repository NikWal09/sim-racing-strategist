"""Race engineer - przeksztalca strumien pakietow w komunikaty dla kierowcy."""

from __future__ import annotations

import time
from dataclasses import dataclass

from ..config import EngineerConfig
from ..speech import Priority
from ..telemetry import GT7Packet
from .delta import DeltaTracker
from .messages import Messages
from .messages import load as load_messages
from .state import SessionState
from .tyres import TyreSectionTracker


@dataclass
class Announcement:
    """Pojedynczy komunikat do wypowiedzenia."""

    text: str
    priority: Priority = Priority.NORMAL
    key: str | None = None          # etykieta do anti-spamu
    min_gap: float | None = None    # opcjonalny wlasny odstep [s]


class RaceEngineer:
    """Wejscie: pakiet -> lista komunikatow; stan trzyma SessionState."""

    # Domyslny odstep [s] dla komunikatow z kluczem, ktore nie podaly wlasnego.
    DEFAULT_MIN_GAP = 2.0

    def __init__(
        self,
        cfg: EngineerConfig,
        clock=time.monotonic,
        language: str = "pl",
        messages: Messages | None = None,
    ) -> None:
        self.cfg = cfg
        self.state = SessionState()
        self.M: Messages = messages or load_messages(language)
        self.tyres = TyreSectionTracker(cfg.tyre_sections)
        self.delta = DeltaTracker(cfg.delta_min_seconds)
        self._laps_since_fuel_report = 0
        self._last_emit: dict[str, float] = {}
        self._clock = clock  # wstrzykiwalny zegar (ulatwia testy)

    def _throttle(self, anns: list[Announcement]) -> list[Announcement]:
        """Odsiewa duplikaty tego samego 'key' czesciej niz co min_gap sekund.

        Anti-spam zyje w jednym miejscu, wiec glos i log konsoli (oraz tryb
        --no-speech) sa spojne i wolne od powtorzen.
        """
        now = self._clock()
        kept: list[Announcement] = []
        for a in anns:
            if a.key is None:
                kept.append(a)
                continue
            gap = self.DEFAULT_MIN_GAP if a.min_gap is None else a.min_gap
            if now - self._last_emit.get(a.key, float("-inf")) >= gap:
                self._last_emit[a.key] = now
                kept.append(a)
        return kept

    def update(self, p: GT7Packet) -> list[Announcement]:
        return self._throttle(self._update(p))

    def _update(self, p: GT7Packet) -> list[Announcement]:
        out: list[Announcement] = []

        if p.paused or p.loading:
            return out

        # Nowa sesja / zmiana auta -> reset.
        if self.state.car_code is None:
            self.state.car_code = p.car_code
        elif p.car_code != self.state.car_code:
            self.state.car_code = p.car_code
            self.state.reset()
            self.tyres.reset()
            self.delta.reset()
            self.state.connected = False

        if not p.on_track:
            # Powrot do menu - przy kolejnym wejsciu na tor przywitamy ponownie.
            self.state.connected = False
            return out

        # Pierwsze polaczenie na torze.
        if not self.state.connected:
            self.state.connected = True
            self.state.current_lap = p.current_lap
            self.state.last_position = p.position_in_race
            self.state.best_lap_ms = p.best_lap_ms
            self.tyres.reset()
            self.delta.reset()
            self.delta.start_lap(self._clock())
            if p.fuel_capacity > 0:
                self.state.fuel_at_lap_start = p.current_fuel
            out.append(Announcement(self.M.connected(), Priority.NORMAL, key="connected", min_gap=10))
            return out

        # Sledzenie temperatury opon po sekcjach toru i delty (co pakiet).
        now = self._clock()
        self.tyres.update(p.speed_mps, p.tyre_temp, now)
        self.delta.update(p.speed_mps, now)

        out.extend(self._check_lap(p))
        out.extend(self._check_position(p))
        out.extend(self._check_tyres(p))
        out.extend(self._check_tyre_sections(p))
        out.extend(self._check_delta(p))
        return out

    # --- Okrazenia + paliwo ---

    def _check_lap(self, p: GT7Packet) -> list[Announcement]:
        out: list[Announcement] = []
        if p.current_lap <= self.state.current_lap:
            return out

        completed_a_timed_lap = self.state.current_lap >= 1
        self.state.current_lap = p.current_lap
        # Domknij sekcje opon i delte dla zakonczonego okrazenia.
        self.tyres.on_lap_complete()
        self.delta.on_lap_complete(p.last_lap_ms, self._clock())

        # Wejscie na ostatnie okrazenie wyscigu.
        if self.cfg.announce_lap_times and p.total_laps > 0 and p.current_lap == p.total_laps:
            out.append(Announcement(self.M.last_lap(), Priority.HIGH, key="last_lap", min_gap=30))

        if not completed_a_timed_lap:
            # Pierwsze przeciecie linii - zacznij liczyc paliwo od teraz.
            if p.fuel_capacity > 0:
                self.state.fuel_at_lap_start = p.current_fuel
            return out

        # --- Czas okrazenia / najlepszy ---
        improved_best = (
            p.best_lap_ms > 0
            and (self.state.best_lap_ms <= 0 or p.best_lap_ms < self.state.best_lap_ms)
        )
        if improved_best:
            self.state.best_lap_ms = p.best_lap_ms
            if self.cfg.announce_best_lap:
                out.append(Announcement(self.M.best_lap(p.best_lap_ms), Priority.HIGH, key="lap_time"))
            elif self.cfg.announce_lap_times and p.last_lap_ms > 0:
                out.append(Announcement(self.M.lap_time(p.last_lap_ms), Priority.NORMAL, key="lap_time"))
        elif self.cfg.announce_lap_times and p.last_lap_ms > 0:
            out.append(Announcement(self.M.lap_time(p.last_lap_ms), Priority.NORMAL, key="lap_time"))

        # --- Paliwo ---
        out.extend(self._check_fuel(p))
        return out

    def _check_fuel(self, p: GT7Packet) -> list[Announcement]:
        out: list[Announcement] = []
        if p.fuel_capacity <= 0:
            return out  # auto bez paliwa (np. niektore EV raportuja 0)

        # Zuzycie w minionym okrazeniu.
        if self.state.fuel_at_lap_start is not None:
            used = self.state.fuel_at_lap_start - p.current_fuel
            if used > 0:
                self.state.fuel_per_lap_history.append(used)
        self.state.fuel_at_lap_start = p.current_fuel

        avg = self.state.avg_fuel_per_lap
        laps_left = self.state.laps_remaining_on_fuel(p.current_fuel)
        if (avg is None or laps_left is None
                or self.state.current_lap < self.cfg.min_laps_for_fuel_calc + 1):
            return out

        self._laps_since_fuel_report += 1

        if laps_left <= self.cfg.fuel_critical_laps:
            out.append(Announcement(self.M.fuel_critical(laps_left), Priority.CRITICAL,
                                    key="fuel", min_gap=8))
        elif laps_left <= self.cfg.fuel_warning_laps:
            out.append(Announcement(self.M.fuel_warning(laps_left), Priority.HIGH,
                                    key="fuel", min_gap=15))
        elif laps_left <= self.cfg.pit_window_laps + self.cfg.fuel_warning_laps:
            if self._laps_since_fuel_report >= 2:
                self._laps_since_fuel_report = 0
                out.append(Announcement(self.M.fuel_laps_left(laps_left), Priority.LOW, key="fuel"))
        else:
            if self._laps_since_fuel_report >= 3:
                self._laps_since_fuel_report = 0
                out.append(Announcement(self.M.fuel_laps_left(laps_left), Priority.LOW, key="fuel"))

        # Strategia do mety - tylko wyscigi na okreslona liczbe okrazen.
        if self.cfg.announce_fuel_strategy and p.total_laps > 0:
            out.extend(self._fuel_strategy(p, avg, laps_left))
        return out

    def _fuel_strategy(self, p: GT7Packet, avg: float, laps_left: float) -> list[Announcement]:
        """Czy paliwa starczy do mety; jak nie - ile oszczedzac i ile dotankowac."""
        out: list[Announcement] = []
        race_laps_left = p.total_laps - p.current_lap + 1
        if race_laps_left <= 0 or avg <= 0:
            return out

        margin = self.cfg.fuel_target_margin_laps
        needed_with_margin = (race_laps_left + margin) * avg
        deficit = needed_with_margin - p.current_fuel

        if deficit > 0.01:
            # Brakuje paliwa. Ile mniej palic na okrazenie, by dociagnac bez zapasu.
            required_avg = p.current_fuel / race_laps_left
            save = avg - required_avg
            # Do ktorego okrazenia starczy obecnym tempem (ostatnie pelne kolko).
            last_full_lap = p.current_lap + int(laps_left) - 1
            if last_full_lap < p.current_lap:
                last_full_lap = p.current_lap
            refuel_pct = 100.0 * deficit / p.fuel_capacity if p.fuel_capacity > 0 else 0.0

            if save > 0.01:
                out.append(Announcement(self.M.fuel_save_per_lap(save), Priority.HIGH,
                                        key="fuel_finish", min_gap=20))
            out.append(Announcement(self.M.fuel_runs_out(last_full_lap), Priority.NORMAL,
                                    key="fuel_runs_out", min_gap=25))
            if refuel_pct > 1.0:
                out.append(Announcement(self.M.fuel_refuel_pct(refuel_pct), Priority.LOW,
                                        key="fuel_refuel", min_gap=40))
        else:
            # Starczy z zapasem - rzadkie, spokojne potwierdzenie.
            margin_laps = (p.current_fuel - race_laps_left * avg) / avg
            if margin_laps > 0:
                out.append(Announcement(self.M.fuel_ok_to_finish(margin_laps), Priority.LOW,
                                        key="fuel_finish", min_gap=60))
        return out

    # --- Pozycja ---

    def _check_position(self, p: GT7Packet) -> list[Announcement]:
        out: list[Announcement] = []
        if not self.cfg.announce_position_changes or p.total_cars <= 0:
            return out
        if p.position_in_race <= 0:
            return out
        prev = self.state.last_position
        if prev <= 0:
            self.state.last_position = p.position_in_race
            return out
        if p.position_in_race < prev:
            out.append(Announcement(self.M.gained_position(p.position_in_race), Priority.NORMAL,
                                    key="position", min_gap=3))
        elif p.position_in_race > prev:
            out.append(Announcement(self.M.lost_position(p.position_in_race), Priority.NORMAL,
                                    key="position", min_gap=3))
        self.state.last_position = p.position_in_race
        return out

    # --- Opony ---

    def _check_tyres(self, p: GT7Packet) -> list[Announcement]:
        out: list[Announcement] = []
        threshold = self.cfg.tyre_temp_warning
        hottest_idx = max(range(4), key=lambda i: p.tyre_temp[i])
        if p.tyre_temp[hottest_idx] >= threshold:
            out.append(Announcement(
                self.M.tyre_hot(self.M.corners[hottest_idx], p.tyre_temp[hottest_idx]),
                Priority.NORMAL, key="tyre_hot", min_gap=25,
            ))
        return out

    def _check_delta(self, p: GT7Packet) -> list[Announcement]:
        """Delta do najlepszego okrazenia - tylko na prostej, raz na prosta."""
        out: list[Announcement] = []
        if not self.cfg.announce_delta:
            return out
        now = self._clock()
        # wheel_rotation_rad jest niezerowy tylko w formatach 'B'/'~'; przy 'A'
        # bramka opiera sie na gazie i predkosci.
        self.delta.update_straight(p.throttle, p.wheel_rotation_rad, p.speed_kph, now)
        if not self.delta.can_announce_straight(now):
            return out
        d = self.delta.current_delta()
        if d is None or abs(d) < self.cfg.delta_min_seconds:
            return out
        self.delta.mark_announced()
        if d < 0:
            out.append(Announcement(self.M.delta_ahead(-d), Priority.LOW, key="delta", min_gap=4))
        else:
            out.append(Announcement(self.M.delta_behind(d), Priority.LOW, key="delta", min_gap=4))
        return out

    def _check_tyre_sections(self, p: GT7Packet) -> list[Announcement]:
        """Komunikat o sekcji toru, w ktorej opony grzeja sie najmocniej."""
        out: list[Announcement] = []
        if not self.cfg.announce_tyre_sections:
            return out
        res = self.tyres.hottest_section()
        if res is None:
            return out
        section, tyre_idx, temp = res
        if temp >= self.cfg.tyre_section_temp_warning:
            out.append(Announcement(
                self.M.tyre_section_hot(section, self.tyres.n, self.M.corners[tyre_idx], temp),
                Priority.LOW, key="tyre_section", min_gap=90,
            ))
        return out

"""Auto-wykrywanie zakretow toru i temperatury opon na kazdym z nich.

Zamiast dzielic okrazenie na sztywne sekcje, rozpoznajemy PRAWDZIWE zakrety:
auto skreca (duzy kat kierownicy albo szybka zmiana kierunku jazdy), zwykle z
hamowaniem przed. Kazdy zakret na okrazeniu dostaje kolejny numer (1, 2, 3...),
a dla kazdego zapamietujemy najwyzsza temperature opony i ktorej.

Dwa zrodla sygnalu "skrecam":
  * kat kierownicy (wheel_rotation_rad) - dostepny w formatach 'B'/'~',
  * predkosc katowa toru jazdy (yaw rate) liczona ze zmiany wektora predkosci -
    dziala w KAZDYM formacie, takze 'A' (gdzie kata kierownicy nie ma).

Dzieki temu po pierwszym pelnym okrazeniu wiadomo, na ktorym zakrecie opony
grzeja sie najmocniej, a na biezaco - czy na WLASNIE pokonanym zakrecie doszlo
do przegrzania (feedback "na poprzednim zakrecie przegrzales opone").

Dziala na dowolnym torze, bez map i nazw zakretow.
"""

from __future__ import annotations

import math

Vec3 = tuple[float, float, float]


class CornerTracker:
    """Wykrywa zakrety i buduje mape "zakret -> najgoretsza opona"."""

    # Progi wejscia/wyjscia z zakretu (histereza, by jeden zakret nie liczyl sie kilka razy).
    ENTER_STEER_RAD = 0.06     # kat kierownicy uznany za "skrecam" (format B/~)
    EXIT_STEER_RAD = 0.03      # ponizej tego - prostowanie
    ENTER_YAW_DPS = 14.0       # zmiana kierunku jazdy [stopnie/s] uznana za zakret
    EXIT_YAW_DPS = 7.0
    MIN_SPEED_MPS = 8.0        # ponizej tej predkosci nie ufamy yaw (manewry w boksie itp.)
    MIN_ENTER_S = 0.20         # tyle musi trwac skret, zanim uznamy zakret (anty-drgania)
    MIN_EXIT_S = 0.45          # tyle musi trwac prosta, zanim zamkniemy zakret
    MAX_DT_S = 0.5             # wieksza przerwa (pauza) -> zerujemy kierunek

    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        self._last_t: float | None = None
        self._heading: float | None = None
        self.in_corner = False
        self._enter_since: float | None = None
        self._exit_since: float | None = None
        self.cur_corner_idx = 0          # numer zakretu w biezacym okrazeniu (1..)
        self._cur_peak = 0.0
        self._cur_tyre = 0
        # Agregaty po numerach zakretow (wygladzone EMA przez okrazenia).
        self.corner_peak: list[float] = []
        self.corner_tyre: list[int] = []
        self.corner_count = 0            # ustabilizowana liczba zakretow na okrazeniu
        self.completed_laps = 0
        # Zakret wlasnie zamkniety - do feedbacku na biezaco (analyzer go odbiera).
        self._just_finished: tuple[int, int, float] | None = None

    # --- Pomiar ---

    def update(self, pos: Vec3, vel: Vec3, speed_mps: float,
               steer_rad: float, tyre_temp, now: float) -> None:
        """Wolane co pakiet: aktualizuje wykrywanie zakretu i szczyt temp opon."""
        # Predkosc katowa toru jazdy z poziomego wektora predkosci (x, z).
        yaw_dps = 0.0
        dt = None if self._last_t is None else now - self._last_t
        if dt is not None and (dt <= 0 or dt > self.MAX_DT_S):
            self._heading = None  # przerwa - nie licz skoku kierunku
            dt = None
        self._last_t = now

        if speed_mps >= self.MIN_SPEED_MPS and abs(vel[0]) + abs(vel[2]) > 1e-3:
            heading = math.atan2(vel[2], vel[0])
            if self._heading is not None and dt:
                d = heading - self._heading
                while d > math.pi:
                    d -= 2 * math.pi
                while d < -math.pi:
                    d += 2 * math.pi
                yaw_dps = abs(math.degrees(d) / dt)
            self._heading = heading

        steer = abs(steer_rad)
        # "Skrecam mocno" (wejscie) i "wciaz w zakrecie" (wyjscie) - z dwoch zrodel.
        turn_strong = (steer >= self.ENTER_STEER_RAD) or (yaw_dps >= self.ENTER_YAW_DPS)
        turn_weak = (steer >= self.EXIT_STEER_RAD) or (yaw_dps >= self.EXIT_YAW_DPS)

        if not self.in_corner:
            if turn_strong:
                if self._enter_since is None:
                    self._enter_since = now
                if now - self._enter_since >= self.MIN_ENTER_S:
                    self._begin_corner()
            else:
                self._enter_since = None
        else:
            self._accumulate(tyre_temp)
            if not turn_weak:
                if self._exit_since is None:
                    self._exit_since = now
                if now - self._exit_since >= self.MIN_EXIT_S:
                    self._end_corner()
            else:
                self._exit_since = None

    def _begin_corner(self) -> None:
        self.in_corner = True
        self._enter_since = None
        self._exit_since = None
        self.cur_corner_idx += 1
        self._cur_peak = 0.0
        self._cur_tyre = 0

    def _accumulate(self, tyre_temp) -> None:
        idx = max(range(4), key=lambda i: tyre_temp[i])
        t = tyre_temp[idx]
        if t > self._cur_peak:
            self._cur_peak = t
            self._cur_tyre = idx

    def _end_corner(self) -> None:
        self.in_corner = False
        self._exit_since = None
        i = self.cur_corner_idx - 1
        if i < 0:
            return
        while len(self.corner_peak) <= i:
            self.corner_peak.append(0.0)
            self.corner_tyre.append(0)
        if self._cur_peak > 0:
            if self.corner_peak[i] > 0:
                self.corner_peak[i] = 0.6 * self.corner_peak[i] + 0.4 * self._cur_peak
            else:
                self.corner_peak[i] = self._cur_peak
            self.corner_tyre[i] = self._cur_tyre
        # Zglos zamkniety zakret do feedbacku na biezaco.
        self._just_finished = (self.cur_corner_idx, self._cur_tyre, self._cur_peak)

    def on_lap_complete(self) -> None:
        """Przy przecieciu linii: domyka okrazenie i utrwala liczbe zakretow."""
        # Jesli akurat byliśmy w zakrecie (linia tuz za nim) - domknij go.
        if self.in_corner:
            self._end_corner()
        if self.cur_corner_idx > 0:
            self.corner_count = self.cur_corner_idx
            self.completed_laps += 1
        # Reset stanu per-okrazenie (agregaty zostaja).
        self.cur_corner_idx = 0
        self.in_corner = False
        self._enter_since = None
        self._exit_since = None
        self._cur_peak = 0.0
        self._cur_tyre = 0
        self._heading = None

    # --- Odczyt ---

    def pop_just_finished(self) -> tuple[int, int, float] | None:
        """Zwraca (numer_zakretu, indeks_opony, szczyt_temp) ostatnio zamknietego
        zakretu i czysci znacznik. None, gdy od ostatniego odczytu nic sie nie domknelo."""
        jf = self._just_finished
        self._just_finished = None
        return jf

    def hottest_corner(self) -> tuple[int, int, float] | None:
        """Zakret z najwyzsza (usredniona) temperatura opony w sesji.

        Zwraca (numer_zakretu_1.., indeks_opony, temp) albo None gdy brak danych.
        """
        if self.completed_laps < 1 or not any(v > 0 for v in self.corner_peak):
            return None
        i = max(range(len(self.corner_peak)), key=lambda k: self.corner_peak[k])
        return i + 1, self.corner_tyre[i], self.corner_peak[i]

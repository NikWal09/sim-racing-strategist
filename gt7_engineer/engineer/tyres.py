"""Auto-uczenie sekcji toru pod katem temperatury opon.

GT7 nie podaje nazw zakretow, ale daje pozycje auta i predkosc. Dzielimy okrazenie
na N rownych sekcji wg pokonanego dystansu (calkujemy predkosc po czasie), a dla
kazdej sekcji zapamietujemy najwyzsza temperature opony i ktorej (FL/FR/RL/RR).
Po kilku okrazeniach wiadomo, w ktorej sekcji opony grzeja sie najmocniej - czyli
gdzie grozi przegrzanie i szybsze zuzycie. Dziala na dowolnym torze, bez konfiguracji.
"""

from __future__ import annotations


class TyreSectionTracker:
    """Buduje mape "sekcja toru -> najgoretsza opona" na podstawie pakietow."""

    def __init__(self, n_sections: int = 12) -> None:
        self.n = max(2, int(n_sections))
        self._last_t: float | None = None
        self.lap_distance = 0.0          # dystans pokonany w biezacym okrazeniu [m]
        self.ref_distance: float | None = None  # dlugosc ostatniego pelnego okrazenia [m]
        self.completed_laps = 0          # ile pelnych okrazen juz zmierzylismy
        # Wygladzone (EMA) szczyty temperatur per sekcja i opona, ktora je osiagnela.
        self.section_peak = [0.0] * self.n
        self.section_tyre = [0] * self.n
        # Szczyty z biezacego okrazenia (zlewane do EMA po jego zakonczeniu).
        self._cur_peak = [0.0] * self.n
        self._cur_tyre = [0] * self.n

    def reset(self) -> None:
        self.__init__(self.n)

    def update(self, speed_mps: float, tyre_temp, now: float) -> None:
        """Wolane co pakiet: calkuje dystans i aktualizuje szczyt sekcji."""
        if self._last_t is not None:
            dt = now - self._last_t
            if dt > 0:
                self.lap_distance += max(0.0, speed_mps) * dt
        self._last_t = now

        if not self.ref_distance or self.ref_distance <= 0:
            return  # bez wzorca dlugosci okrazenia nie znamy jeszcze frakcji

        frac = self.lap_distance / self.ref_distance
        if frac < 0.0:
            frac = 0.0
        if frac > 0.999:
            frac = 0.999
        sec = int(frac * self.n)

        idx = max(range(4), key=lambda i: tyre_temp[i])
        t = tyre_temp[idx]
        if t > self._cur_peak[sec]:
            self._cur_peak[sec] = t
            self._cur_tyre[sec] = idx

    def on_lap_complete(self) -> None:
        """Wolane przy przecieciu linii: domyka okrazenie i zlewa dane do EMA."""
        if self.lap_distance > 0:
            self.ref_distance = self.lap_distance
        self.lap_distance = 0.0

        any_data = any(v > 0 for v in self._cur_peak)
        if any_data:
            for i in range(self.n):
                v = self._cur_peak[i]
                if v <= 0:
                    continue
                if self.section_peak[i] > 0:
                    self.section_peak[i] = 0.6 * self.section_peak[i] + 0.4 * v
                else:
                    self.section_peak[i] = v
                self.section_tyre[i] = self._cur_tyre[i]
            self.completed_laps += 1

        self._cur_peak = [0.0] * self.n
        self._cur_tyre = [0] * self.n

    def hottest_section(self):
        """Zwraca (numer_sekcji_1..N, indeks_opony, temperatura) albo None.

        Wymaga co najmniej jednego zmierzonego okrazenia.
        """
        if self.completed_laps < 1 or not any(v > 0 for v in self.section_peak):
            return None
        i = max(range(self.n), key=lambda k: self.section_peak[k])
        return i + 1, self.section_tyre[i], self.section_peak[i]

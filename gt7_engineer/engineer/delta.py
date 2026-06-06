"""Delta do najlepszego okrazenia - liczona z samej telemetrii GT7.

GT7 nie podaje gotowej delty ani nawet "dystansu na okrazeniu". Mamy za to
predkosc (speed_mps) co pakiet, a to wystarcza:

  * Dystans pokonany w biezacym okrazeniu liczymy calkujac predkosc po czasie
    (dist += speed * dt) - tak samo jak robi to TyreSectionTracker.
  * Czas od startu okrazenia mierzymy zegarem (GT7 nie ma pola "czas biezacego
    okrazenia"), zerujac go przy przecieciu linii.
  * Najlepsze okrazenie zapamietujemy jako referencje: liste par (dystans, czas).
    Na biezacym okrazeniu, dla aktualnego dystansu, interpolujemy z referencji,
    ile czasu zajelo to miejsce na najszybszym kolku -> delta = czas_teraz minus
    czas_referencyjny. Ujemna = jedziesz szybciej.

Metoda dziala na dowolnym torze, bez map i nazw zakretow, bo dystans jest sam
dla siebie punktem odniesienia. Calkowanie lekko dryfuje, ale referencja i
biezace okrazenie licza tak samo, wiec blad w duzej mierze sie znosi.

Komunikat czytamy tylko na PROSTEJ (duzy gaz, wysoka predkosc, maly kat
kierownicy jesli dostepny), zeby nie rozpraszac kierowcy w zakretach.
"""

from __future__ import annotations


class DeltaTracker:
    """Liczy delte do najlepszego okrazenia i pilnuje, kiedy mozna ja podac."""

    # Probkujemy referencje/biezace co ~5 m, by tablice byly krotkie.
    SAMPLE_EVERY_M = 5.0

    # Heurystyka "jestem na prostej" - dobrana tak, by lapac proste i odrzucac zakrety.
    STRAIGHT_THROTTLE = 218          # gaz 0-255 (~85%)
    STRAIGHT_MIN_SPEED_KPH = 90.0    # ponizej tej predkosci nie uznajemy za prosta
    STRAIGHT_MIN_DURATION_S = 0.6    # tyle musi trwac, zanim cokolwiek powiemy
    STRAIGHT_MAX_STEER_RAD = 0.12    # gdy dostepny kat kierownicy (format B/~)

    def __init__(self, min_delta_s: float = 0.15) -> None:
        self.min_delta_s = float(min_delta_s)
        self.reset()

    def reset(self) -> None:
        self._last_t: float | None = None
        self.lap_start_t: float | None = None
        self.lap_distance = 0.0
        self.cur_samples: list[tuple[float, float]] = []   # (dystans, czas[s])
        self._last_sample_dist = -1e9
        self.ref: list[tuple[float, float]] | None = None  # najlepsze okrazenie
        self.ref_ms: int | None = None
        # Stan wykrywania prostej.
        self._straight_since: float | None = None
        self._announced_on_straight = False

    # --- Pomiar dystansu i czasu ---

    def start_lap(self, now: float) -> None:
        """Rozpoczyna nowe okrazenie: zeruje dystans i licznik czasu."""
        self.lap_start_t = now
        self.lap_distance = 0.0
        self.cur_samples = []
        self._last_sample_dist = -1e9

    def update(self, speed_mps: float, now: float) -> None:
        """Wolane co pakiet: calkuje dystans i probkuje (dystans, czas)."""
        if self._last_t is not None and self.lap_start_t is not None:
            dt = now - self._last_t
            if dt > 0:
                self.lap_distance += max(0.0, speed_mps) * dt
        self._last_t = now

        if self.lap_start_t is None:
            return
        if self.lap_distance - self._last_sample_dist >= self.SAMPLE_EVERY_M:
            self.cur_samples.append((self.lap_distance, now - self.lap_start_t))
            self._last_sample_dist = self.lap_distance

    def on_lap_complete(self, last_lap_ms: int, now: float) -> None:
        """Przy przecieciu linii: jesli to najszybsze kolko - zapisz referencje."""
        if self.cur_samples and last_lap_ms and last_lap_ms > 0:
            if self.ref_ms is None or last_lap_ms < self.ref_ms:
                self.ref = self.cur_samples
                self.ref_ms = int(last_lap_ms)
        self.start_lap(now)

    # --- Delta ---

    def current_delta(self) -> float | None:
        """Aktualna delta [s] (ujemna = szybciej). None, gdy brak referencji."""
        if not self.ref or self.lap_start_t is None or self._last_t is None:
            return None
        ref_elapsed = self._interp(self.ref, self.lap_distance)
        if ref_elapsed is None:
            return None
        cur_elapsed = self._last_t - self.lap_start_t
        return cur_elapsed - ref_elapsed

    @staticmethod
    def _interp(ref: list[tuple[float, float]], d: float) -> float | None:
        """Czas referencyjny dla dystansu d (interpolacja liniowa)."""
        if not ref:
            return None
        if d <= ref[0][0]:
            return ref[0][1]
        if d >= ref[-1][0]:
            return None  # poza dlugoscia referencji - nie porownujemy
        lo, hi = 0, len(ref) - 1
        while lo + 1 < hi:
            mid = (lo + hi) // 2
            if ref[mid][0] <= d:
                lo = mid
            else:
                hi = mid
        d0, t0 = ref[lo]
        d1, t1 = ref[hi]
        if d1 == d0:
            return t1
        f = (d - d0) / (d1 - d0)
        return t0 + f * (t1 - t0)

    # --- Wykrywanie prostej (bramka na komunikat) ---

    def update_straight(self, throttle: int, steer_rad: float,
                        speed_kph: float, now: float) -> None:
        """Aktualizuje stan "jestem na prostej". steer_rad=0 -> brak danych o skrecie."""
        steer_ok = steer_rad == 0.0 or abs(steer_rad) <= self.STRAIGHT_MAX_STEER_RAD
        straight_now = (
            throttle >= self.STRAIGHT_THROTTLE
            and speed_kph >= self.STRAIGHT_MIN_SPEED_KPH
            and steer_ok
        )
        if straight_now:
            if self._straight_since is None:
                self._straight_since = now
        else:
            self._straight_since = None
            self._announced_on_straight = False

    def can_announce_straight(self, now: float) -> bool:
        """True, gdy jestesmy stabilnie na prostej i jeszcze tu nie mowilismy."""
        if self._straight_since is None or self._announced_on_straight:
            return False
        return now - self._straight_since >= self.STRAIGHT_MIN_DURATION_S

    def mark_announced(self) -> None:
        """Oznacza, ze na tej prostej juz podano delte (jeden raz na prosta)."""
        self._announced_on_straight = True

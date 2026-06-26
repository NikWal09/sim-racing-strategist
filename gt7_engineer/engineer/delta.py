"""Delta do najlepszego okrazenia - liczona z telemetrii GT7.

Metoda oparta o POZYCJE na torze (a nie o calkowanie predkosci):

  * GT7 podaje pozycje auta w swiecie (x, y, z) co pakiet - w kazdym formacie.
  * Najlepsze okrazenie zapamietujemy jako referencyjna trase: liste probek
    (x, y, z, czas_od_startu). To "slad" najszybszego kolka.
  * Na biezacym okrazeniu, dla aktualnej pozycji, znajdujemy najblizszy punkt
    na trasie referencyjnej (z rzutem na odcinek dla gladkosci) i odczytujemy,
    ile czasu zajelo dojechanie tam na najszybszym kolku. Delta = czas_teraz
    minus czas_referencyjny w tym samym miejscu toru. Ujemna = jedziesz szybciej.

Dlaczego nie calkowanie predkosci? Bo blad calkowania kumuluje sie przez
okrazenie, a dwa kolka po roznych liniach maja inny dystans w tym samym
fizycznym punkcie - stad delta potrafila skakac o sekundy. Porownanie po
pozycji nie dryfuje: zawsze porownujemy ten sam punkt toru.

Metoda dziala na dowolnym torze, bez map i nazw zakretow.

Komunikat czytamy tylko na PROSTEJ (duzy gaz, wysoka predkosc, maly kat
kierownicy jesli dostepny), zeby nie rozpraszac kierowcy w zakretach.
"""

from __future__ import annotations

Vec3 = tuple[float, float, float]
Sample = tuple[float, float, float, float]  # (x, y, z, czas[s])


class DeltaTracker:
    """Liczy delte do najlepszego okrazenia (po pozycji) i bramkuje komunikat."""

    # Probkujemy trase co ~5 m, by tablice byly krotkie. Rzut na odcinek
    # i tak wygladza wynik miedzy probkami.
    SAMPLE_EVERY_M = 5.0

    # Heurystyka "jestem na prostej" - dobrana tak, by lapac proste i odrzucac zakrety.
    STRAIGHT_THROTTLE = 218          # gaz 0-255 (~85%)
    STRAIGHT_MIN_SPEED_KPH = 90.0    # ponizej tej predkosci nie uznajemy za prosta
    STRAIGHT_MIN_DURATION_S = 0.6    # tyle musi trwac, zanim cokolwiek powiemy
    STRAIGHT_MAX_STEER_RAD = 0.12    # gdy dostepny kat kierownicy (format B/~)

    # Wykluczanie okrazen wyjazdowych z referencji (najszybszego kolka):
    #   * okrazenie wyjazdowe (start z miejsca lub wyjazd z pit) zaczyna sie
    #     wolno - lotne okrazenie przecina linie z duza predkoscia,
    #   * postoj/obrot w trakcie kolka (prawie zero predkosci) tez je dyskwalifikuje,
    #   * pierwsze okrazenie (numer 1) to zawsze start z miejsca - pomijamy.
    OUTLAP_MIN_START_KPH = 60.0      # ponizej tej predkosci na linii = okrazenie wyjazdowe
    STOPPED_KPH = 12.0               # prawie postoj w trakcie kolka = pit/obrot

    def __init__(self, min_delta_s: float = 0.15) -> None:
        self.min_delta_s = float(min_delta_s)
        self.reset()

    def reset(self) -> None:
        self._last_t: float | None = None
        self.lap_start_t: float | None = None
        self.lap_distance = 0.0
        self._last_pos: Vec3 | None = None
        self._last_sample_dist = -1e9
        self.cur_samples: list[Sample] = []          # slad biezacego okrazenia
        self.ref: list[Sample] | None = None         # slad najlepszego okrazenia
        self.ref_ms: int | None = None
        self._cur_delta: float | None = None          # ostatnio policzona delta
        self._ref_idx = 0                             # postep wzdluz referencji
        # Stan walidacji biezacego okrazenia jako kandydata na referencje.
        self.cur_valid = False                        # czy biezace kolko moze byc referencja
        self._cur_lap_no = 0                          # numer biezacego okrazenia
        # Stan wykrywania prostej.
        self._straight_since: float | None = None
        self._announced_on_straight = False

    # --- Pomiar trasy i czasu ---

    def start_lap(self, now: float, speed_mps: float = 0.0, lap_no: int = 0) -> None:
        """Rozpoczyna nowe okrazenie: zeruje slad, licznik czasu i postep referencji.

        speed_mps/lap_no sluza do oceny, czy to lotne okrazenie. Okrazenie
        wyjazdowe (lap 1 albo wolny przejazd przez linie po wyjezdzie z pit)
        nie kwalifikuje sie na referencje delty.
        """
        self.lap_start_t = now
        self.lap_distance = 0.0
        self._last_sample_dist = -1e9
        self.cur_samples = []
        self._ref_idx = 0
        self._cur_lap_no = int(lap_no)
        # Lotne okrazenie: nie pierwsze i przeciecie linii z duza predkoscia.
        self.cur_valid = (lap_no >= 2 and speed_mps * 3.6 >= self.OUTLAP_MIN_START_KPH)

    def update(self, pos: Vec3, speed_mps: float, now: float, lap_no: int = 0) -> None:
        """Wolane co pakiet: probkuje slad i przelicza biezaca delte.

        lap_no to ZYWY numer okrazenia z gry (p.current_lap) - dzieki niemu
        delta wie, ze na okrazeniu 0/1 (out-lap, np. tuz po powrocie z pit,
        gdy gra zeruje licznik) nie wolno jej pokazywac, mimo ze referencja juz jest.
        """
        self._cur_lap_no = int(lap_no)
        # Dystans sluzy tylko do rownomiernego probkowania sladu (co ~5 m).
        if self._last_t is not None and self.lap_start_t is not None:
            dt = now - self._last_t
            if dt > 0:
                self.lap_distance += max(0.0, speed_mps) * dt
        self._last_t = now
        self._last_pos = pos

        # Prawie postoj w trakcie kolka (pit/obrot) -> okrazenie nielotne.
        if speed_mps * 3.6 < self.STOPPED_KPH:
            self.cur_valid = False

        if self.lap_start_t is not None:
            if self.lap_distance - self._last_sample_dist >= self.SAMPLE_EVERY_M:
                self.cur_samples.append((pos[0], pos[1], pos[2], now - self.lap_start_t))
                self._last_sample_dist = self.lap_distance

        self._cur_delta = self._compute_delta(pos, now)

    def on_lap_complete(self, last_lap_ms: int, now: float,
                        speed_mps: float = 0.0, lap_no: int = 0) -> None:
        """Przy przecieciu linii: jesli to najszybsze LOTNE kolko - zapisz referencje.

        Okrazenia wyjazdowe (out-lapy) sa pomijane - patrz `cur_valid`.
        speed_mps/lap_no opisuja nowo rozpoczynane okrazenie.
        """
        if self.cur_valid and self.cur_samples and last_lap_ms and last_lap_ms > 0:
            if self.ref_ms is None or last_lap_ms < self.ref_ms:
                self.ref = self.cur_samples
                self.ref_ms = int(last_lap_ms)
        self.start_lap(now, speed_mps, lap_no)

    # --- Delta ---

    def current_delta(self) -> float | None:
        """Aktualna delta [s] (ujemna = szybciej). None, gdy brak referencji."""
        return self._cur_delta

    def _compute_delta(self, pos: Vec3, now: float) -> float | None:
        # Delta pokazuje sie tylko gdy: mamy referencje (najszybsze kolko)
        # ORAZ jestesmy na okrazeniu >= 2. Okrazenie 0 i 1 to out-lapy (start
        # z miejsca lub wyjazd z pit, gdzie gra zeruje licznik do 0) - tam delta
        # liczylaby od niewlasciwego punktu, wiec ja chowamy mimo istniejacej referencji.
        # Czas liczymy od lap_start_t, ktory zeruje sie na kazdej linii start/meta.
        if not self.ref or self.lap_start_t is None or self._cur_lap_no < 2:
            return None
        ref_t = self._ref_time_at(pos)
        if ref_t is None:
            return None
        return (now - self.lap_start_t) - ref_t

    # Szerokosc okna przeszukiwania referencji (w probkach, ~5 m kazda).
    SEARCH_BACK = 5      # ile probek wstecz (drobny luz na szum pozycji)
    SEARCH_AHEAD = 150   # ile probek do przodu (~750 m zapasu na luki w danych)

    def _ref_time_at(self, pos: Vec3) -> float | None:
        """Czas referencyjny w miejscu toru najblizszym pozycji 'pos'.

        Szukamy tylko w OKNIE wokol biezacego postepu (_ref_idx), a nie po calej
        referencji. Auto jedzie do przodu, wiec dzieki temu w okolicy linii
        start/meta nie pomylimy konca okrazenia (czas ~ pelne okrazenie) z jego
        poczatkiem (czas ~ 0) - to wlasnie powodowalo skoki delty o sekundy.
        """
        ref = self.ref
        if not ref or len(ref) < 2:
            return None
        n = len(ref)
        i = self._nearest_in_window(ref, pos, n)
        self._ref_idx = i
        # Rzut na sasiedni odcinek (i-1,i) lub (i,i+1) - wygladza miedzy probkami.
        best_d2: float | None = None
        best_t = ref[i][3]
        for j in (i - 1, i):
            if 0 <= j < n - 1:
                frac, d2 = self._proj_seg(pos, ref[j], ref[j + 1])
                t = ref[j][3] + frac * (ref[j + 1][3] - ref[j][3])
                if best_d2 is None or d2 < best_d2:
                    best_d2 = d2
                    best_t = t
        return best_t

    def _nearest_in_window(self, ref: list[Sample], pos: Vec3, n: int) -> int:
        """Indeks najblizszej probki w oknie [idx-BACK, idx+AHEAD] (postep do przodu)."""
        px, py, pz = pos
        lo = max(0, self._ref_idx - self.SEARCH_BACK)
        hi = min(n, self._ref_idx + self.SEARCH_AHEAD)
        best_i = lo
        best = float("inf")
        for i in range(lo, hi):
            s = ref[i]
            dx = s[0] - px
            dy = s[1] - py
            dz = s[2] - pz
            d2 = dx * dx + dy * dy + dz * dz
            if d2 < best:
                best = d2
                best_i = i
        # Jesli najlepszy wypadl na przedniej krawedzi okna (np. luka w danych),
        # przesun okno do przodu i dosukaj raz jeszcze.
        if best_i >= hi - 1 and hi < n:
            hi2 = min(n, best_i + self.SEARCH_AHEAD)
            for i in range(hi, hi2):
                s = ref[i]
                dx = s[0] - px
                dy = s[1] - py
                dz = s[2] - pz
                d2 = dx * dx + dy * dy + dz * dz
                if d2 < best:
                    best = d2
                    best_i = i
        return best_i

    @staticmethod
    def _proj_seg(pos: Vec3, a: Sample, b: Sample) -> tuple[float, float]:
        """Rzut punktu na odcinek a-b. Zwraca (frakcja 0..1, kwadrat odleglosci)."""
        px, py, pz = pos
        vx, vy, vz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
        seg2 = vx * vx + vy * vy + vz * vz
        if seg2 <= 1e-9:
            dx, dy, dz = px - a[0], py - a[1], pz - a[2]
            return 0.0, dx * dx + dy * dy + dz * dz
        t = ((px - a[0]) * vx + (py - a[1]) * vy + (pz - a[2]) * vz) / seg2
        t = 0.0 if t < 0.0 else 1.0 if t > 1.0 else t
        cx, cy, cz = a[0] + t * vx, a[1] + t * vy, a[2] + t * vz
        dx, dy, dz = px - cx, py - cy, pz - cz
        return t, dx * dx + dy * dy + dz * dz

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

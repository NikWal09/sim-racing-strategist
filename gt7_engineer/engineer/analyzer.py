"""Race engineer - przeksztalca strumien pakietow w komunikaty dla kierowcy."""

from __future__ import annotations

import time
from collections import deque
from dataclasses import dataclass

from ..config import EngineerConfig
from ..speech import Priority
from ..telemetry import GT7Packet
from .corners import CornerTracker
from .delta import DeltaTracker
from .messages import Messages
from .messages import load as load_messages
from .reference import ReferenceDelta, ReferenceInfo
from .state import SessionState


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

    # Powrot do pit przez menu pauzy: paliwo skacze w gore (dotankowanie) przy
    # niemal zerowej predkosci. Paliwa nie da sie zyskac jadac - to pewny sygnal.
    FUEL_REFILL_EPS = 0.05      # min. przyrost paliwa uznany za dotankowanie
    PIT_RETURN_MAX_KPH = 5.0    # przy tej (lub mniejszej) predkosci uznajemy postoj

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
        self.corners = CornerTracker()
        self.delta = DeltaTracker(cfg.delta_min_seconds)
        # Delta do okrazenia referencyjnego (nagrane kolko z pliku, takze z
        # innego auta). Nieaktywna, dopoki GUI nie wywola set_reference().
        self.ref_delta = ReferenceDelta(cfg.delta_min_seconds,
                                        sectors=int(getattr(cfg, "ref_sectors", 3)))
        self._laps_since_fuel_report = 0
        self._last_emit: dict[str, float] = {}
        self._last_fuel: float | None = None  # paliwo z poprzedniego pakietu (detekcja dotankowania)
        # Okrazenie z tankowaniem / wjazdem z menu daje NIEPELNA probke zuzycia
        # (liczylaby tylko odcinek od pitu do linii) - taka probke pomijamy,
        # inaczej srednia spalania nagle spada po pit stopie.
        self._fuel_lap_invalid = False
        # Diagnostyka paliwa: linie do logu GUI/CLI (bez glosu), patrz pop_fuel_debug().
        self._fuel_debug: list[str] = []
        self._clock = clock  # wstrzykiwalny zegar (ulatwia testy)
        # Srednie spalanie liczymy z okna ostatnich X okrazen (konfigurowalne).
        window = max(1, int(getattr(cfg, "fuel_avg_window", 3)))
        self.state.fuel_per_lap_history = deque(maxlen=window)

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

    # --- Okrazenie referencyjne ---

    def set_reference(self, path: str) -> ReferenceInfo:
        """Ustawia nagrane okrazenie (plik JSON recordera) jako referencje.

        Referencja moze pochodzic z INNEGO auta - delta jest pozycyjna, wiec
        porownanie dwoch pojazdow na tym samym torze dziala wprost.
        Rzuca ValueError przy niepoprawnym pliku.
        """
        info = self.ref_delta.load(path)
        self.ref_delta.start_lap(self._clock())
        return info

    def clear_reference(self) -> None:
        """Usuwa okrazenie referencyjne (DELTA REF znika)."""
        self.ref_delta.clear()

    def pop_fuel_debug(self) -> list[str]:
        """Zwraca i czysci linie diagnostyki paliwa (tylko do logu, nie do glosu)."""
        lines = self._fuel_debug
        self._fuel_debug = []
        return lines

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
            self.corners.reset()
            self.delta.reset()
            # Referencji z pliku NIE kasujemy - zmiana auta to wlasnie scenariusz
            # "porownaj dwa pojazdy na tym samym torze". Zerujemy tylko stan kolka.
            self.ref_delta.reset()
            self.state.connected = False
            self._last_fuel = None
            self._fuel_lap_invalid = False

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
            self.corners.reset()
            # UWAGA: nie resetujemy delty (self.delta.reset()) przy ponownym wejsciu
            # na tor. Powrot z pit/menu pauzy tez tu trafia - reset kasowalby slad
            # najlepszego okrazenia i delta przestawala dzialac "jakby nie bylo kolek".
            # Slad czyscimy tylko przy zmianie auta (powyzej). Tu jedynie zaczynamy
            # nowe okrazenie, zachowujac referencje, by delta dalej liczyla do best.
            # WAZNE: bez lap_no/predkosci -> cur_valid=False, wiec to czesciowe
            # okrazenie (wjazd z menu/pitu w srodku toru) NIE nadpisze referencji.
            self.delta.start_lap(self._clock())
            self.ref_delta.start_lap(self._clock())
            if p.fuel_capacity > 0:
                self.state.fuel_at_lap_start = p.current_fuel
            # Wjazd na tor w srodku okrazenia -> probka zuzycia bylaby niepelna.
            self._fuel_lap_invalid = True
            out.append(Announcement(self.M.connected(), Priority.NORMAL, key="connected", min_gap=10))
            return out

        # Sledzenie zakretow (temperatura opon) i delty (co pakiet).
        now = self._clock()

        # Powrot do pit przez menu pauzy: paliwo skacze w gore (dotankowanie)
        # przy niemal zerowej predkosci. Menu pauzy czesto NIE przelacza on_track
        # i NIE zwieksza licznika okrazen, wiec on_lap_complete sam by nie odpalil
        # i delta liczylaby od starego punktu startu (nie resetowalaby sie).
        # Tu wymuszamy nowe okrazenie: zerujemy slad (lap_start_t, _ref_idx).
        # start_lap bez lap_no -> cur_valid=False, wiec ten out-lap nie nadpisze
        # referencji (najszybszego kolka). Referencja zostaje nietknieta.
        if (self._last_fuel is not None and p.fuel_capacity > 0
                and p.current_fuel > self._last_fuel + self.FUEL_REFILL_EPS
                and p.speed_kph <= self.PIT_RETURN_MAX_KPH):
            self.delta.start_lap(now)
            self.ref_delta.start_lap(now)
            self.state.fuel_at_lap_start = p.current_fuel
            # Dotankowanie w srodku okrazenia: zuzycie tego kolka policzyloby sie
            # tylko od pitu do linii (zanizone) - oznacz probke jako niewazna.
            self._fuel_lap_invalid = True
            self._fuel_debug.append(
                f"[PALIWO] Tankowanie wykryte (paliwo {p.current_fuel:.2f}) - "
                f"probka zuzycia tego okrazenia zostanie pominieta.")
        self._last_fuel = p.current_fuel

        self.corners.update(p.position, p.velocity, p.speed_mps,
                            p.wheel_rotation_rad, p.tyre_temp, now)
        self.delta.update(p.position, p.speed_mps, now, p.current_lap)
        if self.ref_delta.loaded:
            self.ref_delta.update(p.position, p.speed_mps, now, p.current_lap)

        out.extend(self._check_lap(p))
        out.extend(self._check_position(p))
        out.extend(self._check_tyres(p))
        out.extend(self._check_corners(p))
        out.extend(self._check_delta(p))
        out.extend(self._check_ref_sectors(p))
        return out

    # --- Okrazenia + paliwo ---

    def _check_lap(self, p: GT7Packet) -> list[Announcement]:
        out: list[Announcement] = []

        # Licznik okrazen cofnal sie (powrot do pit/menu zresetowal numer kolka).
        # Zsynchronizuj licznik i zacznij nowe okrazenie - inaczej warunek nizej
        # (current_lap <= state) blokowalby na zawsze reset delty.
        if p.current_lap < self.state.current_lap:
            self.state.current_lap = p.current_lap
            self.delta.start_lap(self._clock())
            self.ref_delta.start_lap(self._clock())
            self._fuel_lap_invalid = True   # kolko po resecie licznika = niepelne
            return out

        if p.current_lap <= self.state.current_lap:
            return out

        completed_a_timed_lap = self.state.current_lap >= 1
        self.state.current_lap = p.current_lap
        # Domknij zakrety i delte dla zakonczonego okrazenia.
        self.corners.on_lap_complete()
        self.delta.on_lap_complete(p.last_lap_ms, self._clock(), p.speed_mps, p.current_lap)
        self.ref_delta.on_lap_complete(p.last_lap_ms, self._clock(), p.speed_mps, p.current_lap)

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

        # Zuzycie w minionym okrazeniu. Okrazenie z tankowaniem / wjazdem
        # z menu / resetem licznika daje NIEPELNA probke - pomijamy ja,
        # zeby nie psula sredniej spalania (patrz _fuel_lap_invalid).
        if self.state.fuel_at_lap_start is not None and not self._fuel_lap_invalid:
            used = self.state.fuel_at_lap_start - p.current_fuel
            if used > 0:
                self.state.fuel_per_lap_history.append(used)
                self._fuel_debug.append(
                    f"[PALIWO] Okr. {self.state.current_lap - 1}: zuzycie {used:.3f} "
                    f"(start {self.state.fuel_at_lap_start:.2f} -> koniec {p.current_fuel:.2f}), "
                    f"okno {list(round(v, 3) for v in self.state.fuel_per_lap_history)}, "
                    f"srednia {self.state.avg_fuel_per_lap:.3f}")
        elif self._fuel_lap_invalid:
            self._fuel_debug.append(
                f"[PALIWO] Okr. {self.state.current_lap - 1}: probka zuzycia POMINIETA "
                f"(pit/menu/reset w trakcie kolka).")
        self._fuel_lap_invalid = False
        self.state.fuel_at_lap_start = p.current_fuel

        avg = self.state.avg_fuel_per_lap
        laps_left = self.state.laps_remaining_on_fuel(p.current_fuel)
        if (avg is None or laps_left is None
                or self.state.current_lap < self.cfg.min_laps_for_fuel_calc + 1):
            return out

        self._laps_since_fuel_report += 1

        # Kandydaci na komunikaty - zbierani razem, potem limit na okrazenie
        # (najwazniejszy wygrywa), zeby inzynier nie zalewal kierowcy paliwem.
        cands: list[Announcement] = []

        if laps_left <= self.cfg.fuel_critical_laps:
            cands.append(Announcement(self.M.fuel_critical(laps_left), Priority.CRITICAL,
                                      key="fuel", min_gap=8))
        elif laps_left <= self.cfg.fuel_warning_laps:
            cands.append(Announcement(self.M.fuel_warning(laps_left), Priority.HIGH,
                                      key="fuel", min_gap=15))
        elif laps_left <= self.cfg.pit_window_laps + self.cfg.fuel_warning_laps:
            if self._laps_since_fuel_report >= 2:
                self._laps_since_fuel_report = 0
                cands.append(Announcement(self.M.fuel_laps_left(laps_left), Priority.LOW, key="fuel"))
        else:
            if self._laps_since_fuel_report >= 3:
                self._laps_since_fuel_report = 0
                cands.append(Announcement(self.M.fuel_laps_left(laps_left), Priority.LOW, key="fuel"))

        # Strategia do mety - tylko wyscigi na okreslona liczbe okrazen.
        if self.cfg.announce_fuel_strategy and p.total_laps > 0:
            cands.extend(self._fuel_strategy(p, avg, laps_left))

        # Limit: najwyzej N komunikatow paliwowych na okrazenie (Priority to
        # IntEnum, mniejsza wartosc = wazniejszy; sort jest stabilny, wiec przy
        # rownych priorytetach zostaje kolejnosc naturalna).
        limit = max(0, int(getattr(self.cfg, "fuel_max_messages_per_lap", 1)))
        cands.sort(key=lambda a: a.priority)
        out.extend(cands[:limit])
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
            # "Starczy do okrazenia X" tylko, gdy X faktycznie wypada PRZED meta.
            # Gdy X >= liczby okrazen wyscigu, komunikat nic nie wnosi
            # (deficyt dotyczyl tylko marginesu bezpieczenstwa).
            if last_full_lap < p.total_laps:
                out.append(Announcement(self.M.fuel_runs_out(last_full_lap), Priority.NORMAL,
                                        key="fuel_runs_out", min_gap=25))
            if refuel_pct > 1.0:
                out.append(Announcement(self.M.fuel_refuel_pct(refuel_pct), Priority.LOW,
                                        key="fuel_refuel", min_gap=40))
        elif getattr(self.cfg, "announce_fuel_ok_to_finish", False):
            # Starczy z zapasem - domyslnie milczymy; potwierdzenie tylko gdy
            # uzytkownik wlaczyl je w konfiguracji.
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

    def _check_ref_sectors(self, p: GT7Packet) -> list[Announcement]:
        """Strata/zysk do okrazenia referencyjnego w wlasnie zamknietym sektorze."""
        out: list[Announcement] = []
        if not self.ref_delta.loaded:
            return out
        res = self.ref_delta.pop_sector_result()
        if res is None or not getattr(self.cfg, "announce_ref_sectors", True):
            return out
        sector_no, diff = res
        if abs(diff) < float(getattr(self.cfg, "ref_sector_min_seconds", 0.3)):
            return out
        if diff > 0:
            out.append(Announcement(self.M.ref_sector_loss(sector_no, diff),
                                    Priority.LOW, key="ref_sector", min_gap=5))
        else:
            out.append(Announcement(self.M.ref_sector_gain(sector_no, -diff),
                                    Priority.LOW, key="ref_sector", min_gap=5))
        return out

    def _check_corners(self, p: GT7Packet) -> list[Announcement]:
        """Feedback po zakretach: co wlasnie przegrzales i gdzie grzeje najmocniej."""
        out: list[Announcement] = []
        if not self.cfg.announce_corner_tyres:
            return out
        warn = self.cfg.corner_temp_warning

        # 1) Na biezaco: zakret wlasnie pokonany - czy doszlo do przegrzania.
        jf = self.corners.pop_just_finished()
        if jf is not None:
            corner_no, tyre_idx, temp = jf
            if temp >= warn:
                out.append(Announcement(
                    self.M.tyre_corner_hot(corner_no, self.M.corners[tyre_idx], temp),
                    Priority.LOW, key="corner_hot", min_gap=8,
                ))

        # 2) Analiza sesji: zakret, na ktorym opony grzeja sie najmocniej.
        res = self.corners.hottest_corner()
        if res is not None:
            corner_no, tyre_idx, temp = res
            if temp >= warn:
                out.append(Announcement(
                    self.M.tyre_corner_worst(corner_no, self.M.corners[tyre_idx], temp),
                    Priority.LOW, key="corner_worst", min_gap=120,
                ))
        return out

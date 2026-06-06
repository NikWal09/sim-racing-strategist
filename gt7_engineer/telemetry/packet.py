"""Reprezentacja sparsowanego pakietu telemetrii GT7."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class GT7Packet:
    """Pojedyncza ramka telemetrii Gran Turismo 7 (format 'A', 296 bajtow).

    Wszystkie predkosci/temperatury w jednostkach SI z gry; pomocnicze
    wlasciwosci przeliczaja je na bardziej czytelne (km/h itd.).
    """

    packet_id: int = 0

    # Pozycja i ruch
    position: tuple[float, float, float] = (0.0, 0.0, 0.0)
    velocity: tuple[float, float, float] = (0.0, 0.0, 0.0)
    speed_mps: float = 0.0          # predkosc wzdluz toru jazdy [m/s]
    rpm: float = 0.0
    body_height: float = 0.0

    # Naped / paliwo
    current_fuel: float = 0.0       # aktualny poziom paliwa
    fuel_capacity: float = 0.0      # pojemnosc zbiornika (0 dla aut elektrycznych)
    boost: float = 0.0              # surowa wartosc; bar = boost - 1
    gear: int = 0                   # aktualny bieg (0 = luz/N, -1 = wsteczny widziany jako 15)
    suggested_gear: int = 0         # sugerowany bieg (15 = brak sugestii)
    throttle: int = 0               # 0-255
    brake: int = 0                  # 0-255
    clutch: float = 0.0
    clutch_engaged: float = 0.0
    rpm_after_clutch: float = 0.0

    # Plyny / temperatury
    oil_pressure: float = 0.0
    water_temp: float = 0.0
    oil_temp: float = 0.0
    tyre_temp: tuple[float, float, float, float] = (0.0, 0.0, 0.0, 0.0)  # FL, FR, RL, RR

    # Kola / opony
    wheel_speed: tuple[float, float, float, float] = (0.0, 0.0, 0.0, 0.0)
    tyre_radius: tuple[float, float, float, float] = (0.0, 0.0, 0.0, 0.0)
    suspension: tuple[float, float, float, float] = (0.0, 0.0, 0.0, 0.0)

    # Wyscig / okrazenia
    current_lap: int = 0
    total_laps: int = 0
    best_lap_ms: int = -1
    last_lap_ms: int = -1
    time_of_day_ms: int = 0
    position_in_race: int = 0
    total_cars: int = 0
    rpm_alert_min: int = 0
    rpm_alert_max: int = 0
    calc_max_speed: int = 0

    car_code: int = 0

    # Dodatkowe pola ruchu nadwozia - tylko formaty 'B' i '~' (0.0 dla 'A')
    wheel_rotation_rad: float = 0.0   # fizyczny kat skretu kierownicy [rad]
    force_feedback: float = 0.0       # sygnal sily zwrotnej (FFB)
    sway: float = 0.0                 # ruch boczny nadwozia
    heave: float = 0.0                # ruch pionowy nadwozia
    surge: float = 0.0                # ruch wzdluzny (przyspieszanie/hamowanie)

    # Pola dostepne tylko w formacie '~' (0 dla 'A'/'B')
    throttle_raw: int = 0             # niefiltrowany gaz 0-255 (widac dzialanie TCS)
    brake_raw: int = 0                # niefiltrowany hamulec 0-255 (widac dzialanie ABS)
    energy_recovery: float = 0.0      # odzysk energii (auta hybrydowe/EV)

    # Flagi (rozpakowane z 16-bitowego pola)
    on_track: bool = False
    paused: bool = False
    loading: bool = False
    in_gear: bool = False
    has_turbo: bool = False
    rev_limiter: bool = False
    handbrake: bool = False
    lights: bool = False
    high_beam: bool = False
    low_beam: bool = False
    asm_active: bool = False
    tcs_active: bool = False

    # --- Wlasciwosci pomocnicze ---

    @property
    def speed_kph(self) -> float:
        return self.speed_mps * 3.6

    @property
    def boost_bar(self) -> float:
        return self.boost - 1.0

    @property
    def fuel_pct(self) -> float:
        if self.fuel_capacity <= 0:
            return 0.0
        return 100.0 * self.current_fuel / self.fuel_capacity

    @property
    def is_electric(self) -> bool:
        # Auta elektryczne raportuja pojemnosc zbiornika = 100 i "paliwo" jako %
        return self.fuel_capacity == 100.0

    @staticmethod
    def format_laptime(ms: int) -> str:
        """Zamienia czas w ms na 'M:SS.mmm'. -1 / brak -> '--'."""
        if ms is None or ms < 0:
            return "--"
        minutes, rem = divmod(ms, 60_000)
        seconds, millis = divmod(rem, 1000)
        return f"{minutes}:{seconds:02d}.{millis:03d}"

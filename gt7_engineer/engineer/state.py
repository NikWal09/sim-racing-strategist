"""Stan sesji wyscigowej - akumulowany na podstawie kolejnych pakietow."""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field


@dataclass
class SessionState:
    """Przechowuje to, czego pojedynczy pakiet nie zawiera: historie i trendy."""

    connected: bool = False
    car_code: int | None = None

    # Sledzenie okrazen
    current_lap: int = 0
    best_lap_ms: int = -1
    last_position: int = 0

    # Paliwo
    fuel_at_lap_start: float | None = None
    # Zuzycie z ostatnich okrazen (do sredniej kroczacej)
    fuel_per_lap_history: deque[float] = field(default_factory=lambda: deque(maxlen=3))

    def reset(self) -> None:
        """Czysci stan przy nowej sesji (powrot do menu, zmiana auta itp.)."""
        self.current_lap = 0
        self.best_lap_ms = -1
        self.last_position = 0
        self.fuel_at_lap_start = None
        self.fuel_per_lap_history.clear()

    @property
    def avg_fuel_per_lap(self) -> float | None:
        if not self.fuel_per_lap_history:
            return None
        # Bierzemy tylko sensowne (dodatnie) zuzycia.
        vals = [v for v in self.fuel_per_lap_history if v > 0]
        if not vals:
            return None
        return sum(vals) / len(vals)

    def laps_remaining_on_fuel(self, current_fuel: float) -> float | None:
        avg = self.avg_fuel_per_lap
        if avg is None or avg <= 0:
            return None
        return current_fuel / avg

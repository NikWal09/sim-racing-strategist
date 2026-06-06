"""Zgodnosc wsteczna: komunikaty przeniesiono do pakietu `messages` (pl/en).

Ten modul przekierowuje na `messages.pl`, aby starsze importy nadal dzialaly.
Nowy kod powinien uzywac: `from .messages import load as load_messages`.
"""

from __future__ import annotations

from .messages.pl import (  # noqa: F401
    format_laptime_spoken,
    laps_word,
    number_pl,
    plural_pl,
)

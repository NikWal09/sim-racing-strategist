"""Polskie komunikaty inżyniera + formatowanie liczb pod TTS.

Funkcje modułowe (plural_pl, laps_word, number_pl, format_laptime_spoken) są
wystawione osobno, bo używają ich testy i klasa `PolishMessages`.

Teksty wypowiadane przez inżyniera używają pełnych polskich znaków (ą, ć, ę,
ł, ń, ó, ś, ź, ż) — neuronowe i SAPI głosy PL wymawiają je poprawnie.
"""

from __future__ import annotations

from .base import Messages


def plural_pl(n: int, one: str, few: str, many: str) -> str:
    """Polska odmiana: 1 -> one, 2-4 (poza 12-14) -> few, reszta -> many."""
    n = abs(int(n))
    if n == 1:
        return one
    if 2 <= n % 10 <= 4 and not (12 <= n % 100 <= 14):
        return few
    return many


def laps_word(n: float) -> str:
    return plural_pl(round(n), "okrążenie", "okrążenia", "okrążeń")


def number_pl(value: float) -> str:
    """Liczba do wypowiedzenia: całkowite bez ułamka, reszta z 'przecinek X'."""
    rounded = round(value, 1)
    if abs(rounded - round(rounded)) < 0.05:
        return str(int(round(rounded)))
    whole = int(rounded)
    tenths = int(round(abs(rounded - whole) * 10))
    return f"{whole} przecinek {tenths}"


def format_laptime_spoken(ms: int) -> str:
    """Czas okrążenia w ms -> wypowiadalny po polsku, np. '1 minuta 23 i 4 sekundy'."""
    if ms is None or ms < 0:
        return "brak czasu"
    minutes, rem = divmod(ms, 60_000)
    seconds = rem / 1000.0
    sec_whole = int(seconds)
    tenths = int(round((seconds - sec_whole) * 10))
    if tenths == 10:
        sec_whole += 1
        tenths = 0
    sec_part = f"{sec_whole} i {tenths}"
    if minutes > 0:
        min_word = plural_pl(minutes, "minuta", "minuty", "minut")
        return f"{minutes} {min_word} {sec_part} sekundy"
    return f"{sec_part} sekundy"


class PolishMessages(Messages):
    lang = "pl"
    corners = ("lewa przednia", "prawa przednia", "lewa tylna", "prawa tylna")

    def number(self, value: float) -> str:
        return number_pl(value)

    def laptime(self, ms: int) -> str:
        return format_laptime_spoken(ms)

    def radio_check(self) -> str:
        return self._pick(
            "Radio check. Inżynier na łączach, słyszysz mnie?",
            "Sprawdzam radio. Jestem z tobą.",
            "Radio check. Łączność działa.",
        )

    def connected(self) -> str:
        return self._pick(
            "Telemetria połączona. Inżynier na łączach.",
            "Jestem z tobą. Telemetria działa.",
            "Połączenie nawiązane. Powodzenia na torze.",
        )

    def lap_time(self, last_ms: int) -> str:
        t = self.laptime(last_ms)
        return self._pick(
            f"Ostatnie okrążenie: {t}.",
            f"Czas okrążenia {t}.",
            f"Kółko za {t}.",
        )

    def best_lap(self, best_ms: int) -> str:
        t = self.laptime(best_ms)
        return self._pick(
            f"Najlepsze okrążenie! {t}.",
            f"Rekord sesji! {t}.",
            f"Świetnie, najszybsze kółko: {t}.",
        )

    def fuel_laps_left(self, laps: float) -> str:
        n = self.number(laps)
        w = laps_word(laps)
        return self._pick(
            f"Paliwa wystarczy na około {n} {w}.",
            f"Na zbiorniku około {n} {w}.",
        )

    def fuel_warning(self, laps: float) -> str:
        n = self.number(laps)
        w = laps_word(laps)
        return self._pick(
            f"Uwaga, paliwo. Zostało około {n} {w}.",
            f"Pilnuj paliwa, około {n} {w} do końca zbiornika.",
        )

    def fuel_critical(self, laps: float) -> str:
        n = self.number(laps)
        w = laps_word(laps)
        return self._pick(
            f"Krytyczny poziom paliwa! Około {n} {w}.",
            f"Paliwo na wykończeniu! Tylko około {n} {w}.",
        )

    def fuel_short_to_finish(self, short_laps: float) -> str:
        n = self.number(short_laps)
        w = laps_word(short_laps)
        return self._pick(
            f"Tym tempem zabraknie paliwa na {n} {w} przed metą.",
            f"Nie dojedziesz tak do mety, brakuje na {n} {w}.",
        )

    def fuel_ok_to_finish(self, margin_laps: float) -> str:
        n = self.number(margin_laps)
        w = laps_word(margin_laps)
        return self._pick(
            f"Paliwa wystarczy do mety, zapas około {n} {w}.",
            f"Spokojnie z paliwem, na koniec zostanie około {n} {w}.",
        )

    def fuel_runs_out(self, lap: int) -> str:
        return self._pick(
            f"Tym tempem paliwa starczy do okrążenia {lap}.",
            f"Bez oszczędzania dojedziesz na paliwie do okrążenia {lap}.",
        )

    def fuel_save_per_lap(self, amount: float) -> str:
        n = self.number(amount)
        return self._pick(
            f"Oszczędzaj około {n} paliwa na okrążenie, żeby dojechać.",
            f"Zejdź z gazu, trzeba około {n} mniej na kółko.",
        )

    def fuel_refuel_pct(self, pct: float) -> str:
        n = self.number(pct)
        return self._pick(
            f"Dotankuj około {n} procent, żeby dojechać do mety.",
            f"Na pit stopie wlej około {n} procent zbiornika.",
        )

    def gained_position(self, pos: int) -> str:
        return self._pick(
            f"Brawo! Awans na pozycję {pos}.",
            f"Wyprzedzenie! Jesteś {pos}.",
            f"Dobra robota, pozycja {pos}.",
        )

    def lost_position(self, pos: int) -> str:
        return self._pick(
            f"Strata pozycji. Jesteś {pos}.",
            f"Przepuścili cię, teraz {pos}.",
        )

    def last_lap(self) -> str:
        return self._pick(
            "Ostatnie okrążenie! Daj z siebie wszystko.",
            "Ostatnie kółko, zostaw serce na torze.",
        )

    def delta_ahead(self, seconds: float) -> str:
        n = self.number(seconds)
        return self._pick(
            f"{n} sekundy do przodu.",
            f"Jesteś o {n} szybciej od najlepszego.",
            f"Zysk {n} sekundy do rekordu.",
        )

    def delta_behind(self, seconds: float) -> str:
        n = self.number(seconds)
        return self._pick(
            f"{n} sekundy z tyłu.",
            f"Tracisz {n} do najlepszego.",
            f"Strata {n} sekundy do rekordu.",
        )

    def ref_sector_loss(self, sector: int, seconds: float) -> str:
        n = self.number(seconds)
        return self._pick(
            f"Tracisz {n} sekundy w sektorze {sector} do referencji.",
            f"Sektor {sector}: strata {n} sekundy do okrążenia referencyjnego.",
            f"W sektorze {sector} oddajesz {n} sekundy do referencji.",
        )

    def ref_sector_gain(self, sector: int, seconds: float) -> str:
        n = self.number(seconds)
        return self._pick(
            f"Zyskujesz {n} sekundy do referencji w sektorze {sector}.",
            f"Sektor {sector}: {n} sekundy szybciej od referencji.",
            f"Świetny sektor {sector}, {n} sekundy do przodu.",
        )

    def tyre_hot(self, corner: str, temp: float) -> str:
        n = self.number(temp)
        return self._pick(
            f"Gorąca opona {corner}, {n} stopni.",
            f"Przegrzewa się opona {corner}, {n} stopni.",
        )

    def tyre_section_hot(self, section: int, total: int, corner: str, temp: float) -> str:
        n = self.number(temp)
        return self._pick(
            f"Opony najmocniej grzeją się w sekcji {section} z {total}, {corner}, {n} stopni.",
            f"W sekcji {section} z {total} opona {corner} osiąga {n} stopni, pilnuj jej.",
        )

    def tyre_corner_hot(self, corner_no: int, tyre: str, temp: float) -> str:
        n = self.number(temp)
        return self._pick(
            f"Na zakręcie {corner_no} przegrzałeś oponę {tyre}, {n} stopni.",
            f"Zakręt {corner_no}: opona {tyre} doszła do {n} stopni, za gorąca.",
            f"Uwaga, na {corner_no} zakręcie opona {tyre} ma {n} stopni.",
        )

    def tyre_corner_worst(self, corner_no: int, tyre: str, temp: float) -> str:
        n = self.number(temp)
        return self._pick(
            f"Opony najmocniej grzeją się na zakręcie {corner_no}: {tyre}, około {n} stopni.",
            f"Najgorętszy dla opon jest zakręt {corner_no}, opona {tyre}, około {n} stopni.",
        )

    def finished(self, pos: int, total: int) -> str:
        if pos > 0:
            tail = f" z {total}." if total else "."
            return f"Meta! Kończysz na pozycji {pos}{tail}"
        return "Meta! Dobra robota."

    def position(self, pos: int, total: int) -> str:
        if total > 0:
            return f"Pozycja {pos} z {total}."
        return f"Pozycja {pos}."

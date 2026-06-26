"""English race-engineer messages + TTS-friendly number/time formatting."""

from __future__ import annotations

from .base import Messages


def number_en(value: float) -> str:
    """Spoken number: integers plain, otherwise 'X point Y'."""
    rounded = round(value, 1)
    if abs(rounded - round(rounded)) < 0.05:
        return str(int(round(rounded)))
    whole = int(rounded)
    tenths = int(round(abs(rounded - whole) * 10))
    return f"{whole} point {tenths}"


def laps_word_en(n: float) -> str:
    return "lap" if round(n) == 1 else "laps"


def format_laptime_spoken_en(ms: int) -> str:
    """Lap time in ms -> spoken English, e.g. '1 minute 32 point 5 seconds'."""
    if ms is None or ms < 0:
        return "no time"
    minutes, rem = divmod(ms, 60_000)
    seconds = rem / 1000.0
    sec_whole = int(seconds)
    tenths = int(round((seconds - sec_whole) * 10))
    if tenths == 10:
        sec_whole += 1
        tenths = 0
    sec_part = f"{sec_whole} point {tenths}"
    if minutes > 0:
        min_word = "minute" if minutes == 1 else "minutes"
        return f"{minutes} {min_word} {sec_part} seconds"
    return f"{sec_part} seconds"


class EnglishMessages(Messages):
    lang = "en"
    corners = ("front left", "front right", "rear left", "rear right")

    def number(self, value: float) -> str:
        return number_en(value)

    def laptime(self, ms: int) -> str:
        return format_laptime_spoken_en(ms)

    def radio_check(self) -> str:
        return self._pick(
            "Radio check. Engineer on the radio, do you read me?",
            "Radio check. I'm with you.",
            "Radio check. Comms are live.",
        )

    def connected(self) -> str:
        return self._pick(
            "Telemetry connected. Your engineer is on the radio.",
            "I'm with you. Telemetry is live.",
            "Connection established. Have a good race.",
        )

    def lap_time(self, last_ms: int) -> str:
        t = self.laptime(last_ms)
        return self._pick(
            f"Last lap: {t}.",
            f"Lap time {t}.",
            f"That's a {t}.",
        )

    def best_lap(self, best_ms: int) -> str:
        t = self.laptime(best_ms)
        return self._pick(
            f"Fastest lap! {t}.",
            f"Session best! {t}.",
            f"Great, quickest lap: {t}.",
        )

    def fuel_laps_left(self, laps: float) -> str:
        n = self.number(laps)
        w = laps_word_en(laps)
        return self._pick(
            f"Fuel for about {n} {w}.",
            f"Around {n} {w} of fuel in the tank.",
        )

    def fuel_warning(self, laps: float) -> str:
        n = self.number(laps)
        w = laps_word_en(laps)
        return self._pick(
            f"Careful, fuel. About {n} {w} left.",
            f"Watch the fuel, around {n} {w} to go.",
        )

    def fuel_critical(self, laps: float) -> str:
        n = self.number(laps)
        w = laps_word_en(laps)
        return self._pick(
            f"Critical fuel level! About {n} {w}.",
            f"Fuel is nearly gone! Only about {n} {w}.",
        )

    def fuel_short_to_finish(self, short_laps: float) -> str:
        n = self.number(short_laps)
        w = laps_word_en(short_laps)
        return self._pick(
            f"At this pace you'll run dry {n} {w} short of the finish.",
            f"You won't make it like this, short by {n} {w}.",
        )

    def fuel_ok_to_finish(self, margin_laps: float) -> str:
        n = self.number(margin_laps)
        w = laps_word_en(margin_laps)
        return self._pick(
            f"Fuel is fine to the finish, about {n} {w} to spare.",
            f"Fuel's good, you'll finish with around {n} {w} in hand.",
        )

    def fuel_runs_out(self, lap: int) -> str:
        return self._pick(
            f"At this pace fuel lasts until lap {lap}.",
            f"Without saving you'll reach lap {lap} on fuel.",
        )

    def fuel_save_per_lap(self, amount: float) -> str:
        n = self.number(amount)
        return self._pick(
            f"Save about {n} of fuel per lap to make it.",
            f"Lift and coast, you need about {n} less per lap.",
        )

    def fuel_refuel_pct(self, pct: float) -> str:
        n = self.number(pct)
        return self._pick(
            f"Take on about {n} percent to reach the finish.",
            f"In the pits add about {n} percent of the tank.",
        )

    def gained_position(self, pos: int) -> str:
        return self._pick(
            f"Nice! Up to P{pos}.",
            f"Overtake! You're P{pos}.",
            f"Good job, position {pos}.",
        )

    def lost_position(self, pos: int) -> str:
        return self._pick(
            f"Lost a place. You're P{pos}.",
            f"They got by, now P{pos}.",
        )

    def last_lap(self) -> str:
        return self._pick(
            "Last lap! Give it everything.",
            "Final lap, leave it all out there.",
        )

    def delta_ahead(self, seconds: float) -> str:
        n = self.number(seconds)
        return self._pick(
            f"{n} seconds up.",
            f"You're {n} ahead of your best.",
            f"Gaining {n} on your best lap.",
        )

    def delta_behind(self, seconds: float) -> str:
        n = self.number(seconds)
        return self._pick(
            f"{n} seconds down.",
            f"You're {n} off your best.",
            f"Losing {n} to your best lap.",
        )

    def ref_sector_loss(self, sector: int, seconds: float) -> str:
        n = self.number(seconds)
        return self._pick(
            f"Losing {n} seconds in sector {sector} to the reference.",
            f"Sector {sector}: {n} seconds down on the reference lap.",
        )

    def ref_sector_gain(self, sector: int, seconds: float) -> str:
        n = self.number(seconds)
        return self._pick(
            f"Gaining {n} seconds on the reference in sector {sector}.",
            f"Great sector {sector}, {n} seconds up on the reference.",
        )

    def tyre_hot(self, corner: str, temp: float) -> str:
        n = self.number(temp)
        return self._pick(
            f"Hot tyre {corner}, {n} degrees.",
            f"The {corner} tyre is overheating, {n} degrees.",
        )

    def tyre_section_hot(self, section: int, total: int, corner: str, temp: float) -> str:
        n = self.number(temp)
        return self._pick(
            f"Tyres run hottest in section {section} of {total}, {corner}, {n} degrees.",
            f"In section {section} of {total} the {corner} tyre hits {n} degrees, mind it.",
        )

    def tyre_corner_hot(self, corner_no: int, tyre: str, temp: float) -> str:
        n = self.number(temp)
        return self._pick(
            f"In turn {corner_no} you overheated the {tyre} tyre, {n} degrees.",
            f"Turn {corner_no}: the {tyre} tyre reached {n} degrees, too hot.",
            f"Careful, in turn {corner_no} the {tyre} tyre hit {n} degrees.",
        )

    def tyre_corner_worst(self, corner_no: int, tyre: str, temp: float) -> str:
        n = self.number(temp)
        return self._pick(
            f"Tyres run hottest in turn {corner_no}: {tyre}, around {n} degrees.",
            f"The toughest corner for tyres is turn {corner_no}, {tyre} tyre, about {n} degrees.",
        )

    def finished(self, pos: int, total: int) -> str:
        if pos > 0:
            tail = f" of {total}." if total else "."
            return f"Finish! You end in P{pos}{tail}"
        return "Finish! Good job."

    def position(self, pos: int, total: int) -> str:
        if total > 0:
            return f"Position {pos} of {total}."
        return f"Position {pos}."

"""Backend głosu oparty o edge-tts (neuronowe głosy Microsoft, online).

Daje dostęp do dużego zestawu wysokiej jakości głosów (np. polskie
pl-PL-MarekNeural, pl-PL-ZofiaNeural i wiele angielskich), za darmo, ale
wymaga połączenia z internetem.

Wymagane pakiety:
    pip install edge-tts sounddevice miniaudio numpy

Synteza zwraca strumień MP3; dekodujemy go do PCM (miniaudio) i odtwarzamy
przez sounddevice na wybranym urządzeniu wyjściowym (można skierować na
wirtualny kabel, tak jak głos SAPI).
"""

from __future__ import annotations

import asyncio

# Sensowne domyślne głosy neuronowe dla obsługiwanych języków.
DEFAULT_VOICES = {
    "pl": "pl-PL-MarekNeural",
    "en": "en-US-AriaNeural",
}


def default_voice(language: str) -> str:
    code = (language or "pl").strip().lower()[:2]
    return DEFAULT_VOICES.get(code, DEFAULT_VOICES["pl"])


def check_available() -> tuple[bool, str]:
    """Sprawdza, czy edge-tts da sie uzyc: pakiety syntezy i odtwarzania.

    Zwraca (True, "") gdy wszystko jest, albo (False, komunikat) z lista
    brakujacych pakietow. Dzieki temu GUI moze pokazac konkretny powod, zamiast
    cicho nie odtworzyc dzwieku (najczestszy problem: brak sounddevice/miniaudio).
    """
    missing: list[str] = []
    for mod, pkg in (("edge_tts", "edge-tts"), ("sounddevice", "sounddevice"),
                     ("miniaudio", "miniaudio"), ("numpy", "numpy")):
        try:
            __import__(mod)
        except Exception:  # noqa: BLE001
            missing.append(pkg)
    if missing:
        return False, "brak pakietow: " + ", ".join(missing) + \
            " (zainstaluj: pip install " + " ".join(missing) + ")"
    return True, ""


def rate_to_pct(rate_wpm: int, baseline: int = 175) -> str:
    """Zamienia tempo z words/min (jak w SAPI) na format procentowy edge-tts."""
    pct = round((rate_wpm - baseline) / baseline * 100)
    pct = max(-50, min(100, pct))
    return f"{pct:+d}%"


def volume_to_pct(volume: float) -> str:
    """Głośność 0.0-1.0 -> format procentowy edge-tts (1.0 = +0%)."""
    pct = round((max(0.0, min(1.0, volume)) - 1.0) * 100)
    return f"{pct:+d}%"


def synth_mp3(text: str, voice: str, rate_pct: str = "+0%", volume_pct: str = "+0%") -> bytes:
    """Syntezuje tekst do bajtów MP3 przez edge-tts (blokująco)."""
    import edge_tts

    async def _run() -> bytes:
        comm = edge_tts.Communicate(text, voice, rate=rate_pct, volume=volume_pct)
        buf = bytearray()
        async for chunk in comm.stream():
            if chunk.get("type") == "audio" and chunk.get("data"):
                buf.extend(chunk["data"])
        return bytes(buf)

    return asyncio.run(_run())


def list_voices(language: str | None = None) -> list[tuple[str, str]]:
    """Zwraca listę (ShortName, opis) dostępnych głosów neuronowych.

    language: opcjonalny filtr po kodzie języka (np. 'pl', 'en').
    """
    import edge_tts

    async def _run():
        return await edge_tts.list_voices()

    voices = asyncio.run(_run())
    out: list[tuple[str, str]] = []
    lang = (language or "").strip().lower()[:2]
    for v in voices:
        short = v.get("ShortName", "")
        locale = v.get("Locale", "")
        if lang and not locale.lower().startswith(lang):
            continue
        gender = v.get("Gender", "")
        out.append((short, f"{locale} {gender}"))
    out.sort()
    return out


def find_output_device(substring: str):
    """Zwraca indeks urządzenia wyjściowego pasującego do podanego fragmentu nazwy.

    None = urządzenie domyślne systemu.
    """
    if not substring:
        return None
    import sounddevice as sd

    needle = substring.lower()
    for idx, dev in enumerate(sd.query_devices()):
        if dev.get("max_output_channels", 0) > 0 and needle in dev.get("name", "").lower():
            return idx
    return None


def play_mp3(data: bytes, output_device: str = "") -> None:
    """Dekoduje MP3 i odtwarza na wybranym urządzeniu (blokująco)."""
    import miniaudio
    import numpy as np
    import sounddevice as sd

    decoded = miniaudio.decode(data)  # domyślnie int16
    samples = np.array(decoded.samples, dtype=np.int16)
    if decoded.nchannels > 1:
        samples = samples.reshape(-1, decoded.nchannels)

    device = find_output_device(output_device)
    sd.play(samples, samplerate=decoded.sample_rate, device=device)
    sd.wait()


def speak(text: str, voice: str, rate_pct: str = "+0%", volume_pct: str = "+0%",
          output_device: str = "") -> None:
    """Pełen cykl: synteza + odtworzenie pojedynczego komunikatu."""
    play_mp3(synth_mp3(text, voice, rate_pct, volume_pct), output_device)

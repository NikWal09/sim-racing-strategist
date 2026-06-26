"""Krotkie dzwieki interfejsu (np. sygnal radiowy przy starcie inzyniera).

Sygnal radiowy gramy jak "klik" krotkofalowki w CrewChief - dwa krotkie tony.
Najpierw probujemy winsound (wbudowany w Windows, bez zaleznosci). Jesli go nie
ma (Linux/Mac) albo zawiedzie, probujemy wygenerowac ton przez sounddevice/numpy.
Gdy nic nie jest dostepne, po prostu milczymy - dzwiek jest mile widziany, ale
nie krytyczny.
"""

from __future__ import annotations

import threading


def _beep_winsound(tones) -> bool:
    """Gra sekwencje (czestotliwosc_Hz, czas_ms) przez winsound. True jesli sie udalo."""
    try:
        import winsound  # tylko Windows
    except Exception:
        return False
    try:
        for freq, ms in tones:
            winsound.Beep(int(freq), int(ms))
        return True
    except Exception:
        return False


def _beep_sounddevice(tones, output_device: str = "") -> bool:
    """Generuje i odtwarza tony przez sounddevice/numpy. True jesli sie udalo."""
    try:
        import numpy as np
        import sounddevice as sd
    except Exception:
        return False
    try:
        sr = 44100
        chunks = []
        for freq, ms in tones:
            n = int(sr * ms / 1000.0)
            t = np.linspace(0.0, ms / 1000.0, n, endpoint=False)
            wave = 0.25 * np.sin(2 * np.pi * float(freq) * t)
            # Krotki fade-in/out, by uniknac trzaskow.
            fade = max(1, int(sr * 0.005))
            env = np.ones(n)
            env[:fade] = np.linspace(0.0, 1.0, fade)
            env[-fade:] = np.linspace(1.0, 0.0, fade)
            chunks.append((wave * env).astype(np.float32))
            chunks.append(np.zeros(int(sr * 0.02), dtype=np.float32))  # mala cisza
        samples = np.concatenate(chunks)

        device = None
        if output_device:
            needle = output_device.lower()
            for idx, dev in enumerate(sd.query_devices()):
                if dev.get("max_output_channels", 0) > 0 and needle in dev.get("name", "").lower():
                    device = idx
                    break
        sd.play(samples, samplerate=sr, device=device)
        sd.wait()
        return True
    except Exception:
        return False


def radio_beep(output_device: str = "", blocking: bool = False) -> None:
    """Odtwarza krotki sygnal radiowy (dwa tony) - jak klik krotkofalowki.

    output_device: fragment nazwy urzadzenia wyjscia (dotyczy tylko sounddevice).
    blocking:      gdy False, gra w tle (nie blokuje GUI).
    """
    tones = ((1100, 70), (1500, 90))

    def _play() -> None:
        if _beep_winsound(tones):
            return
        _beep_sounddevice(tones, output_device)

    if blocking:
        _play()
    else:
        threading.Thread(target=_play, name="radio-beep", daemon=True).start()

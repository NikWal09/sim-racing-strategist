"""Silnik komunikatow glosowych oparty o pyttsx3 (offline, SAPI5 na Windows).

Mowienie odbywa sie w osobnym watku z kolejka priorytetowa, zeby nie blokowac
petli telemetrii. Komunikaty krytyczne (np. brak paliwa) wyprzedzaja blahe.
"""

from __future__ import annotations

import enum
import queue
import sys
import threading
import time
from dataclasses import dataclass, field
from itertools import count


class Priority(enum.IntEnum):
    """Nizsza wartosc = wyzszy priorytet (kolejka PriorityQueue zwraca najmniejszy)."""

    CRITICAL = 0   # brak paliwa, zolta/czerwona flaga
    HIGH = 1       # ostrzezenia (paliwo, opony)
    NORMAL = 2     # czasy okrazen, zmiany pozycji
    LOW = 3        # informacje pomocnicze


@dataclass(order=True)
class _Utterance:
    priority: int
    seq: int
    text: str = field(compare=False)


class Speaker:
    def __init__(
        self,
        enabled: bool = True,
        rate: int = 175,
        volume: float = 1.0,
        voice_substring: str = "",
        output_device: str = "",
        min_gap_seconds: float = 1.5,
        engine: str = "sapi",
        edge_voice: str = "",
        language: str = "pl",
        error_callback=None,
    ) -> None:
        self.enabled = enabled
        self.rate = rate
        self.volume = volume
        self.voice_substring = voice_substring
        self.output_device = output_device
        self.min_gap_seconds = min_gap_seconds
        # Wybor silnika glosu: "sapi" (offline, Windows) lub "edge" (neuronowe, online).
        self.engine = (engine or "sapi").strip().lower()
        self.edge_voice = edge_voice
        self.language = language
        # Callback (opcjonalny) do raportowania bledow TTS poza stderr - GUI
        # podpina go, by pokazac problem (np. brak pakietow edge) w logu zdarzen.
        self.error_callback = error_callback
        self._edge_error_logged = False

        self._queue: "queue.PriorityQueue[_Utterance]" = queue.PriorityQueue()
        self._seq = count()
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()
        # Pamiec ostatniego wypowiedzenia danej "kategorii" do anti-spamu.
        self._last_said: dict[str, float] = {}
        # Wybrany glos rozwiazujemy raz i cache'ujemy jego id.
        self._voice_id: str | None = None
        self._voice_resolved = False
        # Urzadzenie wyjsciowe raportujemy w logach tylko raz.
        self._output_resolved = False

    # --- Cykl zycia ---

    def start(self) -> None:
        if not self.enabled:
            return
        self._thread = threading.Thread(target=self._worker, name="tts-worker", daemon=True)
        self._thread.start()

    def stop(self, wait: bool = True) -> None:
        self._stop.set()
        if self._thread is not None and wait:
            self._thread.join(timeout=3.0)

    def _make_engine(self):
        """Tworzy SWIEZA instancje silnika TTS na pojedynczy komunikat.

        Na Windows (SAPI5) wielokrotne uzycie tej samej instancji w watku w tle
        czesto powoduje, ze tylko pierwszy komunikat jest wypowiadany, a petla
        runAndWait() zostaje w zablokowanym stanie. Tworzenie nowego silnika dla
        kazdej kwestii jest niezawodne i wystarczajaco szybkie dla zapowiedzi.
        """
        import pyttsx3

        engine = pyttsx3.init()
        engine.setProperty("rate", self.rate)
        engine.setProperty("volume", max(0.0, min(1.0, self.volume)))

        # Rozwiaz id glosu raz, potem korzystaj z cache.
        if self.voice_substring and not self._voice_resolved:
            self._voice_resolved = True
            for v in engine.getProperty("voices"):
                haystack = f"{v.id} {getattr(v, 'name', '')}".lower()
                if self.voice_substring.lower() in haystack:
                    self._voice_id = v.id
                    break
        if self._voice_id:
            engine.setProperty("voice", self._voice_id)

        # Kierowanie dzwieku na wskazane urzadzenie (np. kabel wirtualny do Discorda).
        if self.output_device:
            self._apply_output_device(engine)
        return engine

    def _apply_output_device(self, engine) -> None:
        """Ustawia wyjscie audio TTS na urzadzenie pasujace do output_device.

        Korzysta z obiektu SAPI (SpVoice) pod spodem silnika pyttsx3 - tylko on
        pozwala wybrac konkretne urzadzenie wyjsciowe. Dzieki temu glos inzyniera
        moze isc do wirtualnego kabla (mikrofon Discorda), a reszta dzwieku PC
        zostaje na zwyklych glosnikach.
        """
        try:
            tts = engine.proxy._driver._tts  # COM SpVoice (sterownik SAPI5)
        except Exception:
            if not self._output_resolved:
                self._output_resolved = True
                print("[TTS] Wybor urzadzenia wyjsciowego dziala tylko na Windows/SAPI5.",
                      file=sys.stderr)
            return
        try:
            outs = tts.GetAudioOutputs()
            target = None
            target_desc = ""
            for i in range(outs.Count):
                tok = outs.Item(i)
                desc = tok.GetDescription()
                if self.output_device.lower() in desc.lower():
                    target = tok
                    target_desc = desc
                    break
            if target is not None:
                tts.AudioOutput = target
                if not self._output_resolved:
                    self._output_resolved = True
                    print(f"[TTS] Wyjscie audio -> {target_desc}", file=sys.stderr)
            elif not self._output_resolved:
                self._output_resolved = True
                print(f"[TTS] Nie znalazlem urzadzenia audio pasujacego do "
                      f"'{self.output_device}'. Uzywam domyslnego "
                      f"(lista: python main.py --list-outputs).", file=sys.stderr)
        except Exception as e:  # noqa: BLE001
            if not self._output_resolved:
                self._output_resolved = True
                print(f"[TTS] Nie moge ustawic urzadzenia wyjsciowego: "
                      f"{type(e).__name__}: {e}", file=sys.stderr)

    # --- API ---

    def say(
        self,
        text: str,
        priority: Priority = Priority.NORMAL,
        key: str | None = None,
        min_gap: float | None = None,
    ) -> bool:
        """Dodaje komunikat do kolejki.

        key:     etykieta kategorii do anti-spamu (np. "fuel_warning"). Jesli
                 ten sam key padl niedawno (< min_gap s), komunikat jest pomijany.
        min_gap: nadpisuje domyslny odstep dla tego komunikatu.
        Zwraca True jesli zakolejkowano, False jesli pominieto.
        """
        if not self.enabled:
            return False

        if key is not None:
            gap = self.min_gap_seconds if min_gap is None else min_gap
            now = time.monotonic()
            last = self._last_said.get(key, 0.0)
            if now - last < gap:
                return False
            self._last_said[key] = now

        self._queue.put(_Utterance(int(priority), next(self._seq), text))
        return True

    # --- Watek roboczy ---

    def _worker(self) -> None:
        while not self._stop.is_set():
            try:
                utt = self._queue.get(timeout=0.2)
            except queue.Empty:
                continue
            try:
                if self.engine == "edge":
                    self._say_edge(utt.text)
                else:
                    engine = self._make_engine()
                    engine.say(utt.text)
                    engine.runAndWait()
                    try:
                        engine.stop()
                    except Exception:
                        pass
                    del engine  # zwolnij instancje, by kolejna byla swieza
            except Exception as e:  # noqa: BLE001
                # Nie wywracaj watku, ale pokaz problem zamiast cichego znikania.
                msg = f"[TTS] blad silnika mowy: {type(e).__name__}: {e}"
                print(msg, file=sys.stderr)
                if self.error_callback is not None:
                    try:
                        self.error_callback(msg)
                    except Exception:  # noqa: BLE001
                        pass

    def _say_edge(self, text: str) -> None:
        """Wypowiada komunikat przez edge-tts (neuronowe glosy online)."""
        from . import edge_backend as edge

        voice = self.edge_voice or edge.default_voice(self.language)
        try:
            edge.speak(
                text,
                voice=voice,
                rate_pct=edge.rate_to_pct(self.rate),
                volume_pct=edge.volume_to_pct(self.volume),
                output_device=self.output_device,
            )
        except Exception as e:  # noqa: BLE001
            if not self._edge_error_logged:
                self._edge_error_logged = True
                print(f"[TTS] edge-tts nie zadzialal ({type(e).__name__}: {e}). "
                      f"Sprawdz internet i 'pip install edge-tts sounddevice miniaudio numpy', "
                      f"albo ustaw speech.engine: sapi.", file=sys.stderr)
            raise


def list_voices() -> list[tuple[str, str]]:
    """Zwraca liste (id, nazwa) dostepnych glosow SAPI/TTS."""
    import pyttsx3

    engine = pyttsx3.init()
    out = []
    for v in engine.getProperty("voices"):
        out.append((v.id, getattr(v, "name", "")))
    return out


def list_outputs() -> list[str]:
    """Zwraca liste nazw dostepnych urzadzen wyjscia audio (SAPI).

    Sluzy do znalezienia nazwy wirtualnego kabla (np. 'CABLE Input'), ktory
    wpisuje sie potem do speech.output_device, by skierowac glos do Discorda.
    """
    import pyttsx3

    engine = pyttsx3.init()
    try:
        tts = engine.proxy._driver._tts
    except Exception as e:  # noqa: BLE001
        raise RuntimeError(
            "Lista urzadzen wyjsciowych dziala tylko na Windows/SAPI5."
        ) from e
    outs = tts.GetAudioOutputs()
    return [outs.Item(i).GetDescription() for i in range(outs.Count)]


if __name__ == "__main__":
    import sys

    if "--list" in sys.argv:
        print("Dostepne glosy TTS:")
        for vid, name in list_voices():
            print(f"  - {name}  [{vid}]")
    else:
        # Trzy kolejne kwestie - sprawdza, czy TTS dziala wielokrotnie, nie tylko raz.
        sp = Speaker()
        sp.start()
        sp.say("Pierwszy komunikat. Inzynier na laczach.", Priority.NORMAL)
        sp.say("Drugi komunikat. Paliwa na piec okrazen.", Priority.NORMAL)
        sp.say("Trzeci komunikat. Goraca opona prawa tylna.", Priority.NORMAL)
        time.sleep(12)
        sp.stop()

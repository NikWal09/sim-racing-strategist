#!/usr/bin/env python3
"""Interaktywny tester głosów i komunikatów inżyniera GT7.

Pozwala odsłuchać wszystkie voice line w wybranym języku i na wybranym
silniku głosu, bez uruchamiania telemetrii. Dzięki losowaniu wariantów
usłyszysz różne wersje tego samego komunikatu.

Uruchomienie:
    python tools/voice_demo.py
    python tools/voice_demo.py --list-edge pl     # wypisz polskie głosy edge-tts
    python tools/voice_demo.py --list-edge en      # angielskie głosy edge-tts
    python tools/voice_demo.py --list-sapi         # głosy systemowe SAPI

W menu wybierasz: język (pl/en), silnik (sapi/edge), ewentualnie konkretny
głos, a następnie kategorię komunikatu do odsłuchania.
"""

from __future__ import annotations

import os
import sys

# Konsola Windows bywa w cp1250 - wymuś UTF-8, by polskie znaki nie krzaczyły.
try:
    sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
except Exception:
    pass

# Dodaj katalog główny projektu do ścieżki importów.
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)

from gt7_engineer.engineer.messages import load as load_messages  # noqa: E402
from gt7_engineer.speech import Speaker  # noqa: E402


def _build_samples(M):
    """Lista (etykieta, funkcja-generująca-tekst) z przykładowymi argumentami.

    Funkcje wołane są wielokrotnie, więc widać losowanie wariantów.
    """
    rr = M.corners[3]  # prawa tylna / rear right
    return [
        ("Połączenie / Connected", lambda: M.connected()),
        ("Czas okrążenia / Lap time", lambda: M.lap_time(92567)),
        ("Najlepsze okrążenie / Best lap", lambda: M.best_lap(91234)),
        ("Paliwo - zostało / Fuel laps left", lambda: M.fuel_laps_left(3.4)),
        ("Paliwo - ostrzeżenie / Fuel warning", lambda: M.fuel_warning(2.4)),
        ("Paliwo - krytyczne / Fuel critical", lambda: M.fuel_critical(1.2)),
        ("Paliwo - starczy do mety / Enough", lambda: M.fuel_ok_to_finish(0.8)),
        ("Paliwo - do którego okrążenia / Runs out", lambda: M.fuel_runs_out(8)),
        ("Paliwo - ile oszczędzać / Save per lap", lambda: M.fuel_save_per_lap(0.3)),
        ("Paliwo - ile dotankować / Refuel %", lambda: M.fuel_refuel_pct(12.5)),
        ("Delta - szybciej / Delta ahead", lambda: M.delta_ahead(0.3)),
        ("Delta - wolniej / Delta behind", lambda: M.delta_behind(0.7)),
        ("Awans pozycji / Gained position", lambda: M.gained_position(3)),
        ("Strata pozycji / Lost position", lambda: M.lost_position(5)),
        ("Ostatnie okrążenie / Last lap", lambda: M.last_lap()),
        ("Gorąca opona / Tyre hot", lambda: M.tyre_hot(rr, 112.0)),
        ("Gorąca sekcja toru / Tyre section", lambda: M.tyre_section_hot(7, 12, rr, 128.0)),
        ("Meta / Finished", lambda: M.finished(1, 16)),
        ("Pozycja / Position", lambda: M.position(4, 16)),
    ]


def _ask(prompt: str, default: str = "") -> str:
    try:
        ans = input(prompt).strip()
    except EOFError:
        return default
    return ans or default


def _choose(prompt: str, options: list[str], default_idx: int = 0) -> int:
    for i, opt in enumerate(options, 1):
        mark = " (domyślne)" if i - 1 == default_idx else ""
        print(f"  {i}. {opt}{mark}")
    raw = _ask(prompt, str(default_idx + 1))
    try:
        idx = int(raw) - 1
    except ValueError:
        idx = default_idx
    return idx if 0 <= idx < len(options) else default_idx


def list_edge(language: str | None) -> int:
    from gt7_engineer.speech import edge_backend as edge
    try:
        voices = edge.list_voices(language)
    except Exception as e:  # noqa: BLE001
        print(f"Nie udało się pobrać listy głosów edge-tts: {type(e).__name__}: {e}")
        print("Upewnij się, że masz internet oraz: pip install edge-tts")
        return 1
    title = f"Głosy edge-tts" + (f" ({language})" if language else "")
    print(title + ":")
    for short, desc in voices:
        print(f"  - {short:32s} {desc}")
    print(f"\nWpisz wybrany ShortName do speech.edge_voice w config.yaml.")
    return 0


def list_sapi() -> int:
    from gt7_engineer.speech.speaker import list_voices
    print("Głosy systemowe SAPI:")
    for vid, name in list_voices():
        print(f"  - {name}  [{vid}]")
    return 0


def _make_player(engine: str, language: str, edge_voice: str,
                 voice_substring: str, rate: int, volume: float, output_device: str):
    """Zwraca funkcję play(text) odtwarzającą synchronicznie (blokująco)."""
    sp = Speaker(
        enabled=True, rate=rate, volume=volume, voice_substring=voice_substring,
        output_device=output_device, engine=engine, edge_voice=edge_voice, language=language,
    )

    def play(text: str) -> None:
        print(f"     > {text}")
        if sp.engine == "edge":
            sp._say_edge(text)
        else:
            eng = sp._make_engine()
            eng.say(text)
            eng.runAndWait()
            try:
                eng.stop()
            except Exception:
                pass

    return play


def interactive() -> int:
    print("=" * 60)
    print("  TESTER GŁOSÓW I KOMUNIKATÓW - GT7 RACE ENGINEER")
    print("=" * 60)

    langs = ["pl", "en"]
    language = langs[_choose("Wybierz język [1-2]: ", ["polski (pl)", "angielski (en)"], 0)]

    engines = ["sapi", "edge"]
    engine = engines[_choose(
        "Wybierz silnik [1-2]: ",
        ["sapi - głosy systemowe (offline)", "edge - neuronowe (online, najlepsza jakość)"], 0,
    )]

    edge_voice = ""
    voice_substring = ""
    if engine == "edge":
        from gt7_engineer.speech import edge_backend as edge
        print(f"\nDomyślny głos dla '{language}': {edge.default_voice(language)}")
        edge_voice = _ask(
            "Podaj ShortName głosu edge (Enter = domyślny, np. pl-PL-ZofiaNeural): ", "")
    else:
        voice_substring = _ask(
            "Fragment nazwy głosu SAPI (Enter = domyślny, np. Paulina): ", "")

    rate_raw = _ask("Tempo mowy [words/min, Enter = 175]: ", "175")
    try:
        rate = int(rate_raw)
    except ValueError:
        rate = 175
    output_device = _ask("Urządzenie wyjścia audio (Enter = domyślne, np. CABLE): ", "")

    M = load_messages(language)
    samples = _build_samples(M)
    play = _make_player(engine, language, edge_voice, voice_substring, rate, 1.0, output_device)

    while True:
        print("\n" + "-" * 60)
        print("Kategorie komunikatów:")
        labels = [s[0] for s in samples]
        for i, lab in enumerate(labels, 1):
            print(f"  {i:2d}. {lab}")
        print("   0. Wszystkie po kolei")
        print("   q. Wyjście")
        raw = _ask("\nWybierz numer (q = koniec): ", "q")
        if raw.lower() in ("q", "quit", "exit"):
            break

        if raw == "0":
            chosen = list(range(len(samples)))
            variants = 1
        else:
            try:
                idx = int(raw) - 1
            except ValueError:
                print("Nieprawidłowy wybór.")
                continue
            if not (0 <= idx < len(samples)):
                print("Nieprawidłowy numer.")
                continue
            chosen = [idx]
            vr = _ask("Ile wariantów odtworzyć? [Enter = 3]: ", "3")
            try:
                variants = max(1, int(vr))
            except ValueError:
                variants = 3

        try:
            for ci in chosen:
                label, fn = samples[ci]
                print(f"\n  [{label}]")
                for _ in range(variants):
                    play(fn())
        except KeyboardInterrupt:
            print("\n(przerwano odtwarzanie)")
        except Exception as e:  # noqa: BLE001
            print(f"  Błąd odtwarzania: {type(e).__name__}: {e}")

    print("Do zobaczenia na torze!")
    return 0


def main(argv: list[str]) -> int:
    if "--list-edge" in argv:
        i = argv.index("--list-edge")
        lang = argv[i + 1] if i + 1 < len(argv) and not argv[i + 1].startswith("-") else None
        return list_edge(lang)
    if "--list-sapi" in argv:
        return list_sapi()
    return interactive()


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        print("\nPrzerwano.")
        sys.exit(130)

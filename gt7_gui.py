#!/usr/bin/env python3
"""Graficzny interfejs (GUI) dla GT7 Race Engineer.

Prosty, wbudowany w Pythona interfejs (Tkinter - bez dodatkowych zaleznosci)
dla zwyklych uzytkownikow, ktorzy nie chca grzebac w pliku config.yaml ani
uruchamiac inzyniera z linii polecen.

Cztery zakladki:
  * Inzynier      - przyciski Start/Stop, status polaczenia i log zdarzen,
  * Podglad        - dane telemetrii na zywo (predkosc, bieg, paliwo, delta...),
  * Ustawienia    - edycja config.yaml z zachowaniem komentarzy,
  * Test glosow   - odsluchanie komunikatow w wybranym jezyku i silniku TTS.

Uruchomienie:
    python gt7_gui.py

Telemetria dziala w osobnym watku, a komunikaty trafiaja do GUI przez
kolejke (Tkinter nie jest bezpieczny watkowo - aktualizujemy widgety tylko
w glownym watku przez root.after).
"""

from __future__ import annotations

import os
import queue
import re
import sys
import threading
import time
import tkinter as tk
from tkinter import messagebox, ttk

# Konsola Windows bywa w cp1250 - wymus UTF-8, by polskie znaki nie krzaczyly.
try:
    sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
except Exception:
    pass

# Dodaj katalog glowny projektu do sciezki importow.
_ROOT = os.path.dirname(os.path.abspath(__file__))
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)

from gt7_engineer.config import Config  # noqa: E402
from gt7_engineer.engineer import RaceEngineer  # noqa: E402
from gt7_engineer.engineer.messages import load as load_messages  # noqa: E402
from gt7_engineer.speech import Speaker  # noqa: E402
from gt7_engineer.telemetry import GT7Listener, GT7Packet  # noqa: E402

CONFIG_PATH = os.path.join(_ROOT, "config.yaml")


# --------------------------------------------------------------------------
# Schemat ustawien wystawianych w zakladce "Ustawienia".
# Kazdy wpis: (klucz, etykieta, rodzaj, [opcje dla 'choice']).
# Rodzaje: bool, int, float, str, choice.
# --------------------------------------------------------------------------
SETTINGS_SCHEMA = [
    ("telemetry", "Telemetria", [
        ("playstation_ip", "IP konsoli PlayStation", "str"),
        ("send_port", "Port wysylania (heartbeat)", "int"),
        ("receive_port", "Port odbioru telemetrii", "int"),
        ("heartbeat_every", "Heartbeat co N pakietow", "int"),
        ("packet_format", "Format pakietu", "choice", ["A", "B", "~"]),
    ]),
    ("engineer", "Inzynier", [
        ("fuel_warning_laps", "Ostrzezenie o paliwie (okrazen)", "float"),
        ("fuel_critical_laps", "Alarm krytyczny paliwa (okrazen)", "float"),
        ("pit_window_laps", "Okno pit-stopu (okrazen)", "float"),
        ("min_laps_for_fuel_calc", "Min. okrazen do liczenia paliwa", "int"),
        ("tyre_temp_warning", "Ostrzezenie temp. opon (C)", "float"),
        ("announce_lap_times", "Czytaj czasy okrazen", "bool"),
        ("announce_position_changes", "Czytaj zmiany pozycji", "bool"),
        ("announce_best_lap", "Czytaj najlepsze okrazenie", "bool"),
        ("announce_fuel_strategy", "Strategia paliwowa", "bool"),
        ("fuel_target_margin_laps", "Zapas paliwa na koniec (okrazen)", "float"),
        ("announce_tyre_sections", "Gorace sekcje toru", "bool"),
        ("tyre_sections", "Liczba sekcji toru", "int"),
        ("tyre_section_temp_warning", "Temp. raportowania sekcji (C)", "float"),
        ("announce_delta", "Delta do najlepszego okrazenia", "bool"),
        ("delta_min_seconds", "Prog delty (s)", "float"),
    ]),
    ("speech", "Glos", [
        ("enabled", "Glos wlaczony", "bool"),
        ("rate", "Tempo mowy (slowa/min)", "int"),
        ("volume", "Glosnosc (0.0 - 1.0)", "float"),
        ("voice_substring", "Fragment nazwy glosu SAPI", "str"),
        ("output_device", "Urzadzenie wyjscia audio", "str"),
        ("language", "Jezyk", "choice", ["pl", "en"]),
        ("min_gap_seconds", "Min. odstep komunikatow (s)", "float"),
        ("engine", "Silnik glosu", "choice", ["sapi", "edge"]),
        ("edge_voice", "Glos edge-tts (ShortName)", "str"),
    ]),
    ("debug", "Diagnostyka", [
        ("print_telemetry", "Wypisuj surowa telemetrie", "bool"),
        ("log_events", "Loguj zdarzenia inzyniera", "bool"),
    ]),
]


def _find_comment(text: str) -> int | None:
    """Zwraca indeks '#' rozpoczynajacego komentarz, albo None.

    Wartosci w naszym config.yaml sa proste (liczby, true/false, krotkie
    napisy w cudzyslowach bez '#'), wiec wystarczy pierwszy '#'.
    """
    idx = text.find("#")
    return idx if idx >= 0 else None


def save_config_values(path: str, values: dict[tuple[str, str], str]) -> None:
    """Zapisuje wartosci do config.yaml, zachowujac komentarze i uklad.

    values: slownik {(sekcja, klucz): gotowy_tekst_wartosci}, gdzie wartosc
    jest juz sformatowana pod YAML (np. 'true', '3.0', '"CABLE Input"').
    """
    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    sec_re = re.compile(r"^([A-Za-z_]\w*):\s*(#.*)?$")
    key_re = re.compile(r"^(\s+)([A-Za-z_]\w*)(\s*:\s*)(.*)$")

    section: str | None = None
    out: list[str] = []
    for line in lines:
        raw = line.rstrip("\n")
        if not raw.lstrip().startswith("#"):
            msec = sec_re.match(raw)
            if msec:
                section = msec.group(1)
                out.append(line)
                continue
        mkey = key_re.match(raw)
        if mkey and section is not None:
            indent, key, sep, rest = mkey.groups()
            if (section, key) in values:
                comment = ""
                cidx = _find_comment(rest)
                if cidx is not None:
                    comment = rest[cidx:].rstrip()
                newval = values[(section, key)]
                newline = f"{indent}{key}{sep}{newval}"
                if comment:
                    newline += f"  {comment}"
                out.append(newline + "\n")
                continue
        out.append(line)

    with open(path, "w", encoding="utf-8") as f:
        f.writelines(out)


def snapshot(p: GT7Packet, engineer: RaceEngineer) -> dict:
    """Migawka telemetrii dla zakladki podgladu (lekki slownik)."""
    fmt = GT7Packet.format_laptime
    return {
        "speed": f"{p.speed_kph:.0f}",
        "gear": str(p.gear),
        "rpm": f"{p.rpm:.0f}",
        "fuel_label": "Bateria" if p.is_electric else "Paliwo",
        "fuel": f"{p.fuel_pct:.0f} %",
        "lap": f"{p.current_lap}/{p.total_laps}",
        "pos": f"{p.position_in_race}/{p.total_cars}",
        "last": fmt(p.last_lap_ms),
        "best": fmt(p.best_lap_ms),
        "tyres": tuple(p.tyre_temp),
        "delta": engineer.delta.current_delta(),
        "on_track": p.on_track,
    }


# --------------------------------------------------------------------------
# Watek roboczy: telemetria + inzynier + glos.
# --------------------------------------------------------------------------
class EngineerRunner(threading.Thread):
    """Odbiera telemetrie i karmi nia inzyniera, raportujac do kolejki GUI."""

    def __init__(self, cfg: Config, q: "queue.Queue") -> None:
        super().__init__(daemon=True)
        self.cfg = cfg
        self.q = q
        self._stop = threading.Event()

    def stop(self) -> None:
        self._stop.set()

    def run(self) -> None:
        cfg = self.cfg
        speaker = Speaker(
            enabled=cfg.speech.enabled,
            rate=cfg.speech.rate,
            volume=cfg.speech.volume,
            voice_substring=cfg.speech.voice_substring,
            output_device=cfg.speech.output_device,
            min_gap_seconds=cfg.speech.min_gap_seconds,
            engine=cfg.speech.engine,
            edge_voice=cfg.speech.edge_voice,
            language=cfg.speech.language,
        )
        speaker.start()
        engineer = RaceEngineer(cfg.engineer, language=cfg.speech.language)

        self.q.put(("status", f"Lacze z konsola {cfg.telemetry.playstation_ip}..."))
        last_tele = 0.0
        try:
            with GT7Listener(
                playstation_ip=cfg.telemetry.playstation_ip,
                send_port=cfg.telemetry.send_port,
                receive_port=cfg.telemetry.receive_port,
                heartbeat_every=cfg.telemetry.heartbeat_every,
                packet_format=cfg.telemetry.packet_format,
            ) as listener:
                self.q.put(("status", f"Nasluch na porcie {cfg.telemetry.receive_port} "
                                       f"(format '{cfg.telemetry.packet_format}'). "
                                       f"Czekam na dane z GT7..."))
                while not self._stop.is_set():
                    packet = listener.receive()
                    if packet is None:
                        continue
                    for ann in engineer.update(packet):
                        self.q.put(("event", ann.text))
                        speaker.say(ann.text, ann.priority, key=ann.key, min_gap=ann.min_gap)
                    now = time.monotonic()
                    if now - last_tele >= 0.1:
                        last_tele = now
                        self.q.put(("telemetry", snapshot(packet, engineer)))
        except Exception as e:  # noqa: BLE001
            self.q.put(("error", f"{type(e).__name__}: {e}"))
        finally:
            speaker.stop()
            self.q.put(("stopped", None))


# --------------------------------------------------------------------------
# Pomocnicze: probki komunikatow do zakladki "Test glosow".
# --------------------------------------------------------------------------
def build_samples(M):
    """Lista (etykieta, funkcja-tekst). Funkcje wolane wielokrotnie => warianty."""
    rr = M.corners[3]  # prawa tylna / rear right
    return [
        ("Polaczenie / Connected", lambda: M.connected()),
        ("Czas okrazenia / Lap time", lambda: M.lap_time(92567)),
        ("Najlepsze okrazenie / Best lap", lambda: M.best_lap(91234)),
        ("Paliwo - zostalo / Fuel laps left", lambda: M.fuel_laps_left(3.4)),
        ("Paliwo - ostrzezenie / Fuel warning", lambda: M.fuel_warning(2.4)),
        ("Paliwo - krytyczne / Fuel critical", lambda: M.fuel_critical(1.2)),
        ("Paliwo - starczy do mety / Enough", lambda: M.fuel_ok_to_finish(0.8)),
        ("Paliwo - do ktorego okr. / Runs out", lambda: M.fuel_runs_out(8)),
        ("Paliwo - ile oszczedzac / Save", lambda: M.fuel_save_per_lap(0.3)),
        ("Paliwo - ile dotankowac / Refuel %", lambda: M.fuel_refuel_pct(12.5)),
        ("Delta - szybciej / Delta ahead", lambda: M.delta_ahead(0.3)),
        ("Delta - wolniej / Delta behind", lambda: M.delta_behind(0.7)),
        ("Awans pozycji / Gained position", lambda: M.gained_position(3)),
        ("Strata pozycji / Lost position", lambda: M.lost_position(5)),
        ("Ostatnie okrazenie / Last lap", lambda: M.last_lap()),
        ("Goraca opona / Tyre hot", lambda: M.tyre_hot(rr, 112.0)),
        ("Goraca sekcja toru / Tyre section", lambda: M.tyre_section_hot(7, 12, rr, 128.0)),
        ("Meta / Finished", lambda: M.finished(1, 16)),
        ("Pozycja / Position", lambda: M.position(4, 16)),
    ]


# --------------------------------------------------------------------------
# Glowne okno.
# --------------------------------------------------------------------------
class App(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("GT7 Race Engineer")
        self.geometry("760x560")
        self.minsize(640, 480)

        self.q: "queue.Queue" = queue.Queue()
        self.cfg = Config.load(CONFIG_PATH)
        self.runner: EngineerRunner | None = None
        self._setting_vars: dict[tuple[str, str], tk.Variable] = {}
        self._setting_kinds: dict[tuple[str, str], str] = {}
        self._tele_vars: dict[str, tk.StringVar] = {}
        self._tyre_vars: list[tk.StringVar] = []
        self._delta_lbl: ttk.Label | None = None

        nb = ttk.Notebook(self)
        nb.pack(fill="both", expand=True, padx=8, pady=8)
        self._build_engineer_tab(nb)
        self._build_live_tab(nb)
        self._build_settings_tab(nb)
        self._build_voice_tab(nb)

        self.protocol("WM_DELETE_WINDOW", self._on_close)
        self.after(100, self._poll_queue)

    # --- Zakladka: Inzynier (start/stop + log) ---
    def _build_engineer_tab(self, nb: ttk.Notebook) -> None:
        tab = ttk.Frame(nb)
        nb.add(tab, text="Inzynier")

        bar = ttk.Frame(tab)
        bar.pack(fill="x", padx=10, pady=10)
        self.btn_start = ttk.Button(bar, text="Start", command=self._on_start)
        self.btn_start.pack(side="left")
        self.btn_stop = ttk.Button(bar, text="Stop", command=self._on_stop, state="disabled")
        self.btn_stop.pack(side="left", padx=(6, 0))
        self.status_var = tk.StringVar(value="Zatrzymany.")
        ttk.Label(bar, textvariable=self.status_var).pack(side="left", padx=(14, 0))

        ttk.Label(tab, text="Log zdarzen:").pack(anchor="w", padx=10)
        wrap = ttk.Frame(tab)
        wrap.pack(fill="both", expand=True, padx=10, pady=(0, 10))
        self.log = tk.Text(wrap, height=16, wrap="word", state="disabled")
        scroll = ttk.Scrollbar(wrap, command=self.log.yview)
        self.log.configure(yscrollcommand=scroll.set)
        self.log.pack(side="left", fill="both", expand=True)
        scroll.pack(side="right", fill="y")

    # --- Zakladka: Podglad na zywo ---
    def _build_live_tab(self, nb: ttk.Notebook) -> None:
        tab = ttk.Frame(nb)
        nb.add(tab, text="Podglad")

        grid = ttk.Frame(tab)
        grid.pack(fill="x", padx=14, pady=14)
        tiles = [
            ("speed", "Predkosc (km/h)"),
            ("gear", "Bieg"),
            ("rpm", "Obroty (RPM)"),
            ("fuel", "Paliwo / Bateria"),
            ("lap", "Okrazenie"),
            ("pos", "Pozycja"),
            ("last", "Ostatnie okr."),
            ("best", "Najlepsze okr."),
        ]
        for i, (key, label) in enumerate(tiles):
            cell = ttk.LabelFrame(grid, text=label)
            cell.grid(row=i // 4, column=i % 4, padx=6, pady=6, sticky="nsew")
            var = tk.StringVar(value="-")
            self._tele_vars[key] = var
            ttk.Label(cell, textvariable=var, font=("Segoe UI", 16, "bold")).pack(
                padx=12, pady=8)
        for c in range(4):
            grid.columnconfigure(c, weight=1)

        # Opony.
        tyres = ttk.LabelFrame(tab, text="Temperatura opon (C)  [LP, PP, LT, PT]")
        tyres.pack(fill="x", padx=14, pady=(0, 10))
        for i, name in enumerate(["Lewa przod", "Prawa przod", "Lewa tyl", "Prawa tyl"]):
            cell = ttk.Frame(tyres)
            cell.grid(row=0, column=i, padx=10, pady=8, sticky="nsew")
            ttk.Label(cell, text=name).pack()
            var = tk.StringVar(value="-")
            self._tyre_vars.append(var)
            ttk.Label(cell, textvariable=var, font=("Segoe UI", 14, "bold")).pack()
        for c in range(4):
            tyres.columnconfigure(c, weight=1)

        # Delta.
        deltaf = ttk.LabelFrame(tab, text="Delta do najlepszego okrazenia")
        deltaf.pack(fill="x", padx=14, pady=(0, 10))
        self.delta_var = tk.StringVar(value="-")
        self._delta_lbl = ttk.Label(deltaf, textvariable=self.delta_var,
                                    font=("Segoe UI", 18, "bold"))
        self._delta_lbl.pack(padx=12, pady=10)

    # --- Zakladka: Ustawienia ---
    def _build_settings_tab(self, nb: ttk.Notebook) -> None:
        tab = ttk.Frame(nb)
        nb.add(tab, text="Ustawienia")

        # Przewijalny obszar (duzo pol).
        canvas = tk.Canvas(tab, highlightthickness=0)
        scroll = ttk.Scrollbar(tab, orient="vertical", command=canvas.yview)
        inner = ttk.Frame(canvas)
        inner.bind("<Configure>",
                   lambda e: canvas.configure(scrollregion=canvas.bbox("all")))
        canvas.create_window((0, 0), window=inner, anchor="nw")
        canvas.configure(yscrollcommand=scroll.set)
        canvas.pack(side="left", fill="both", expand=True, padx=(10, 0), pady=10)
        scroll.pack(side="right", fill="y", pady=10)

        for section, sec_label, fields in SETTINGS_SCHEMA:
            box = ttk.LabelFrame(inner, text=sec_label)
            box.pack(fill="x", padx=8, pady=6, anchor="n")
            sec_obj = getattr(self.cfg, section)
            for row, field in enumerate(fields):
                key, label, kind = field[0], field[1], field[2]
                options = field[3] if len(field) > 3 else None
                cur = getattr(sec_obj, key)
                ttk.Label(box, text=label).grid(row=row, column=0, sticky="w",
                                                padx=8, pady=3)
                self._setting_kinds[(section, key)] = kind
                if kind == "bool":
                    var: tk.Variable = tk.BooleanVar(value=bool(cur))
                    ttk.Checkbutton(box, variable=var).grid(
                        row=row, column=1, sticky="w", padx=8, pady=3)
                elif kind == "choice":
                    var = tk.StringVar(value=str(cur))
                    ttk.Combobox(box, textvariable=var, values=options or [],
                                 state="readonly", width=18).grid(
                        row=row, column=1, sticky="w", padx=8, pady=3)
                else:
                    var = tk.StringVar(value="" if cur is None else str(cur))
                    ttk.Entry(box, textvariable=var, width=24).grid(
                        row=row, column=1, sticky="w", padx=8, pady=3)
                self._setting_vars[(section, key)] = var
            box.columnconfigure(1, weight=1)

        ttk.Button(inner, text="Zapisz ustawienia", command=self._on_save_settings).pack(
            pady=10)

    # --- Zakladka: Test glosow ---
    def _build_voice_tab(self, nb: ttk.Notebook) -> None:
        tab = ttk.Frame(nb)
        nb.add(tab, text="Test glosow")

        form = ttk.Frame(tab)
        form.pack(fill="x", padx=14, pady=12)

        ttk.Label(form, text="Jezyk:").grid(row=0, column=0, sticky="w", pady=3)
        self.v_lang = tk.StringVar(value=self.cfg.speech.language or "pl")
        ttk.Combobox(form, textvariable=self.v_lang, values=["pl", "en"],
                     state="readonly", width=8).grid(row=0, column=1, sticky="w", padx=6)

        ttk.Label(form, text="Silnik:").grid(row=1, column=0, sticky="w", pady=3)
        self.v_engine = tk.StringVar(value=self.cfg.speech.engine or "sapi")
        ttk.Combobox(form, textvariable=self.v_engine, values=["sapi", "edge"],
                     state="readonly", width=8).grid(row=1, column=1, sticky="w", padx=6)

        ttk.Label(form, text="Glos (SAPI: fragment, edge: ShortName):").grid(
            row=2, column=0, sticky="w", pady=3)
        self.v_voice = tk.StringVar(value="")
        ttk.Entry(form, textvariable=self.v_voice, width=28).grid(
            row=2, column=1, sticky="w", padx=6)

        ttk.Label(form, text="Tempo (slowa/min):").grid(row=3, column=0, sticky="w", pady=3)
        self.v_rate = tk.StringVar(value=str(self.cfg.speech.rate))
        ttk.Entry(form, textvariable=self.v_rate, width=8).grid(
            row=3, column=1, sticky="w", padx=6)

        ttk.Label(form, text="Komunikat:").grid(row=4, column=0, sticky="w", pady=3)
        self.v_sample = tk.StringVar()
        self.v_sample_box = ttk.Combobox(form, textvariable=self.v_sample,
                                         state="readonly", width=40)
        self.v_sample_box.grid(row=4, column=1, sticky="w", padx=6)
        self._reload_samples()
        self.v_lang.trace_add("write", lambda *_: self._reload_samples())

        self.btn_play = ttk.Button(form, text="Odtworz", command=self._on_play_voice)
        self.btn_play.grid(row=5, column=1, sticky="w", padx=6, pady=10)

        self.voice_status = tk.StringVar(value="")
        ttk.Label(tab, textvariable=self.voice_status).pack(anchor="w", padx=14)

    def _reload_samples(self) -> None:
        self._samples = build_samples(load_messages(self.v_lang.get() or "pl"))
        labels = [s[0] for s in self._samples]
        self.v_sample_box.configure(values=labels)
        if labels:
            self.v_sample.set(labels[0])

    # --- Akcje ---
    def _on_start(self) -> None:
        if self.runner is not None:
            return
        self.cfg = Config.load(CONFIG_PATH)  # zastosuj ewentualne zmiany ustawien
        self._append_log("--- Start inzyniera ---")
        self.runner = EngineerRunner(self.cfg, self.q)
        self.runner.start()
        self.btn_start.configure(state="disabled")
        self.btn_stop.configure(state="normal")
        self.status_var.set("Uruchamiam...")

    def _on_stop(self) -> None:
        if self.runner is not None:
            self.status_var.set("Zatrzymuje...")
            self.runner.stop()

    def _on_save_settings(self) -> None:
        values: dict[tuple[str, str], str] = {}
        try:
            for (section, key), var in self._setting_vars.items():
                kind = self._setting_kinds[(section, key)]
                raw = var.get()
                if kind == "bool":
                    values[(section, key)] = "true" if bool(raw) else "false"
                elif kind == "int":
                    values[(section, key)] = str(int(str(raw).strip()))
                elif kind == "float":
                    values[(section, key)] = str(float(str(raw).strip()))
                elif kind == "choice":
                    values[(section, key)] = f'"{raw}"'
                else:  # str
                    values[(section, key)] = f'"{str(raw)}"'
        except ValueError as e:
            messagebox.showerror("Blad", f"Nieprawidlowa wartosc liczbowa: {e}")
            return
        try:
            save_config_values(CONFIG_PATH, values)
        except Exception as e:  # noqa: BLE001
            messagebox.showerror("Blad zapisu", f"{type(e).__name__}: {e}")
            return
        self.cfg = Config.load(CONFIG_PATH)
        messagebox.showinfo("Zapisano", "Ustawienia zapisane do config.yaml.\n"
                                        "Zmiany wejda w zycie po nastepnym Starcie.")

    def _on_play_voice(self) -> None:
        label = self.v_sample.get()
        fn = None
        for lab, f in getattr(self, "_samples", []):
            if lab == label:
                fn = f
                break
        if fn is None:
            return
        try:
            rate = int(self.v_rate.get())
        except ValueError:
            rate = 175
        engine = self.v_engine.get()
        language = self.v_lang.get()
        voice = self.v_voice.get().strip()
        text = fn()
        self.voice_status.set(f"Odtwarzam: {text}")
        self.btn_play.configure(state="disabled")

        def worker() -> None:
            try:
                sp = Speaker(
                    enabled=True, rate=rate, volume=1.0,
                    voice_substring=(voice if engine == "sapi" else ""),
                    output_device=self.cfg.speech.output_device,
                    engine=engine,
                    edge_voice=(voice if engine == "edge" else ""),
                    language=language,
                )
                if engine == "edge":
                    sp._say_edge(text)
                else:
                    eng = sp._make_engine()
                    eng.say(text)
                    eng.runAndWait()
                    try:
                        eng.stop()
                    except Exception:
                        pass
            except Exception as e:  # noqa: BLE001
                self.q.put(("voice_error", f"{type(e).__name__}: {e}"))
            finally:
                self.q.put(("voice_done", None))

        threading.Thread(target=worker, daemon=True).start()

    # --- Petla odpytywania kolejki (glowny watek) ---
    def _poll_queue(self) -> None:
        try:
            while True:
                kind, payload = self.q.get_nowait()
                if kind == "status":
                    self.status_var.set(payload)
                elif kind == "event":
                    self._append_log(payload)
                elif kind == "telemetry":
                    self._update_live(payload)
                elif kind == "error":
                    self._append_log(f"[BLAD] {payload}")
                    self.status_var.set(f"Blad: {payload}")
                elif kind == "stopped":
                    self.runner = None
                    self.btn_start.configure(state="normal")
                    self.btn_stop.configure(state="disabled")
                    self.status_var.set("Zatrzymany.")
                    self._append_log("--- Inzynier zatrzymany ---")
                elif kind == "voice_error":
                    self.voice_status.set(f"Blad glosu: {payload}")
                elif kind == "voice_done":
                    self.btn_play.configure(state="normal")
        except queue.Empty:
            pass
        self.after(100, self._poll_queue)

    def _update_live(self, s: dict) -> None:
        for key in ("speed", "gear", "rpm", "fuel", "lap", "pos", "last", "best"):
            if key in self._tele_vars:
                self._tele_vars[key].set(s.get(key, "-"))
        tyres = s.get("tyres") or ()
        for i, var in enumerate(self._tyre_vars):
            var.set(f"{tyres[i]:.0f}" if i < len(tyres) else "-")
        d = s.get("delta")
        if d is None:
            self.delta_var.set("—")
            if self._delta_lbl is not None:
                self._delta_lbl.configure(foreground="")
        else:
            self.delta_var.set(f"{d:+.2f} s")
            if self._delta_lbl is not None:
                self._delta_lbl.configure(foreground=("green" if d < 0 else "red"))

    def _append_log(self, text: str) -> None:
        self.log.configure(state="normal")
        self.log.insert("end", text + "\n")
        self.log.see("end")
        self.log.configure(state="disabled")

    def _on_close(self) -> None:
        if self.runner is not None:
            self.runner.stop()
            self.runner.join(timeout=6.0)
        self.destroy()


def main() -> int:
    app = App()
    app.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())

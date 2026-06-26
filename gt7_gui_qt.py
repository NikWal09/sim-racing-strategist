#!/usr/bin/env python3
"""Nowoczesne GUI (PySide6 / Qt) dla GT7 Race Engineer.

Apka desktopowa z ciemnym motywem, okraglymi zegarami predkosci i obrotow,
paskiem delty oraz temperaturami opon - calosc renderowana natywnie przez Qt.
Logika Pythona (telemetria, inzynier, TTS) jest ta sama co w trybie konsolowym;
GUI tylko ja steruje i wizualizuje.

Wymaga jednej dodatkowej zaleznosci:
    pip install PySide6

Uruchomienie:
    python gt7_gui_qt.py

Piec zakladek:
  * Inzynier      - Start/Stop, status polaczenia, log zdarzen,
  * Podglad        - zegary predkosc/RPM, bieg, paliwo, czasy, opony, delta,
  * Nagrania      - lista nagranych okrazen, viewer HTML, usuwanie nagran,
  * Ustawienia    - edycja config.yaml z zachowaniem komentarzy,
  * Test glosow   - odsluchanie komunikatow (jezyk + silnik TTS).

Telemetria dziala w osobnym watku QThread; komunikacja z GUI przez sygnaly Qt
(bezpieczne watkowo - sloty wykonuja sie w glownym watku).
"""

from __future__ import annotations

import os
import re
import sys
import threading
import time

# Konsola Windows bywa w cp1250 - wymus UTF-8.
try:
    sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
except Exception:
    pass

_ROOT = os.path.dirname(os.path.abspath(__file__))
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)

from PySide6.QtCore import Qt, QThread, Signal, QRectF, QSize, QUrl  # noqa: E402
from PySide6.QtGui import QPainter, QColor, QPen, QFont, QDesktopServices  # noqa: E402
from PySide6.QtWidgets import (  # noqa: E402
    QApplication, QMainWindow, QWidget, QTabWidget, QVBoxLayout, QHBoxLayout,
    QGridLayout, QPushButton, QLabel, QTextEdit, QLineEdit, QCheckBox,
    QComboBox, QGroupBox, QScrollArea, QMessageBox, QFrame, QFormLayout,
    QTableWidget, QTableWidgetItem, QAbstractItemView, QHeaderView,
)

from gt7_engineer.config import Config  # noqa: E402
from gt7_engineer.engineer import RaceEngineer, TelemetryRecorder  # noqa: E402
from gt7_engineer.engineer.messages import load as load_messages  # noqa: E402
from gt7_engineer.speech import Speaker, radio_beep  # noqa: E402
from gt7_engineer.speech import edge_backend  # noqa: E402
from gt7_engineer.telemetry import GT7Listener, GT7Packet  # noqa: E402
from tools.telemetry_viewer import load_laps, build_html  # noqa: E402

CONFIG_PATH = os.path.join(_ROOT, "config.yaml")


# --------------------------------------------------------------------------
# Schemat ustawien (taki sam jak w wersji Tkinter).
# (klucz, etykieta, rodzaj, [opcje dla 'choice']).
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
        ("fuel_max_messages_per_lap", "Max komunikatow paliwa / okr.", "int"),
        ("announce_fuel_ok_to_finish", "Mow, gdy paliwa starczy do mety", "bool"),
        ("announce_corner_tyres", "Temp. opon na zakretach", "bool"),
        ("corner_temp_warning", "Temp. ostrzegania na zakrecie (C)", "float"),
        ("announce_delta", "Delta do najlepszego okrazenia", "bool"),
        ("delta_min_seconds", "Prog delty (s)", "float"),
        ("announce_ref_sectors", "Sektory do referencji (glos)", "bool"),
        ("ref_sectors", "Liczba sektorow referencji", "int"),
        ("ref_sector_min_seconds", "Prog sektora referencji (s)", "float"),
        ("fuel_show_percent", "Podglad: poziom paliwa (%)", "bool"),
        ("fuel_show_avg", "Podglad: srednie spalanie / okr.", "bool"),
        ("fuel_show_laps_left", "Podglad: okrazenia do konca paliwa", "bool"),
        ("fuel_avg_window", "Srednie spalanie z ostatnich N okrazen", "int"),
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
        ("edge_voice", "Glos edge-tts (lista lub nazwa)", "voice"),
    ]),
    ("debug", "Diagnostyka", [
        ("print_telemetry", "Wypisuj surowa telemetrie", "bool"),
        ("log_events", "Loguj zdarzenia inzyniera", "bool"),
    ]),
]


def _find_comment(text: str) -> int | None:
    idx = text.find("#")
    return idx if idx >= 0 else None


def save_config_values(path: str, values: dict[tuple[str, str], str]) -> None:
    """Zapisuje wartosci do config.yaml, zachowujac komentarze i uklad."""
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


def fuel_display(p: GT7Packet, engineer: RaceEngineer) -> str:
    """Sklada tekst kafelka paliwa wg wlaczonych opcji w configu.

    Moze pokazywac: poziom paliwa w % (2 miejsca po przecinku), srednie spalanie
    na okrazenie (z okna ostatnich X okrazen) i ile okrazen do konca paliwa.
    """
    cfg = engineer.cfg
    st = engineer.state
    lines: list[str] = []
    has_fuel = p.fuel_capacity > 0

    if getattr(cfg, "fuel_show_percent", True):
        lines.append(f"{p.fuel_pct:.2f} %" if has_fuel else "-- %")

    if getattr(cfg, "fuel_show_avg", True):
        unit = "%/okr." if p.is_electric else "L/okr."
        avg = st.avg_fuel_per_lap
        lines.append(f"Sr.: {avg:.2f} {unit}" if avg else "Sr.: --")

    if getattr(cfg, "fuel_show_laps_left", True):
        laps_left = st.laps_remaining_on_fuel(p.current_fuel) if has_fuel else None
        lines.append(f"Do konca: {laps_left:.1f} okr." if laps_left else "Do konca: --")

    if not lines:  # wszystko wylaczone - pokaz chociaz %
        return f"{p.fuel_pct:.0f} %" if has_fuel else "--"
    return "\n".join(lines)


def snapshot(p: GT7Packet, engineer: RaceEngineer) -> dict:
    """Migawka telemetrii dla zakladki podgladu."""
    fmt = GT7Packet.format_laptime
    # Skala zegarow pod konkretne auto: vmax z telemetrii (calc_max_speed, km/h)
    # i limiter obrotow (rpm_alert_max). Dodajemy maly zapas, by wskazowka nie
    # bila stale w maks. Gdy GT7 nie poda danych (0) - zwracamy 0, GUI uzyje fallbacku.
    speed_max = float(p.calc_max_speed) * 1.05 if p.calc_max_speed > 0 else 0.0
    rpm_max = float(p.rpm_alert_max) * 1.02 if p.rpm_alert_max > 0 else 0.0
    return {
        "speed": float(p.speed_kph),
        "rpm": float(p.rpm),
        "speed_max": speed_max,
        "rpm_max": rpm_max,
        "gear": str(p.gear),
        "fuel_label": "Bateria" if p.is_electric else "Paliwo",
        "fuel": fuel_display(p, engineer),
        "lap": f"{p.current_lap}/{p.total_laps}",
        "pos": f"{p.position_in_race}/{p.total_cars}",
        "last": fmt(p.last_lap_ms),
        "best": fmt(p.best_lap_ms),
        "tyres": tuple(float(t) for t in p.tyre_temp),
        "delta": engineer.delta.current_delta(),
        "ref_delta": (engineer.ref_delta.current_delta()
                      if engineer.ref_delta.loaded else None),
        "ref_loaded": engineer.ref_delta.loaded,
        "on_track": p.on_track,
    }


def build_samples(M):
    """Lista (etykieta, funkcja-tekst) z przykladowymi argumentami."""
    rr = M.corners[3]
    return [
        ("Radio check / Radio check", lambda: M.radio_check()),
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
        ("Goracy zakret / Corner tyre hot", lambda: M.tyre_corner_hot(3, rr, 122.0)),
        ("Najgoretszy zakret / Worst corner", lambda: M.tyre_corner_worst(7, rr, 128.0)),
        ("Meta / Finished", lambda: M.finished(1, 16)),
        ("Pozycja / Position", lambda: M.position(4, 16)),
    ]


# --------------------------------------------------------------------------
# Ciemny motyw (QSS).
# --------------------------------------------------------------------------
DARK_QSS = """
QMainWindow, QWidget { background-color: #12151a; color: #e6e8eb; }
QTabWidget::pane { border: 1px solid #232a33; border-radius: 10px; top: -1px; }
QTabBar::tab {
    background: transparent; color: #8d95a3; padding: 10px 20px;
    border-top-left-radius: 9px; border-top-right-radius: 9px; margin-right: 2px;
    border-bottom: 2px solid transparent; font-weight: 600;
}
QTabBar::tab:hover { color: #c8cdd6; }
QTabBar::tab:selected {
    background: #1b212a; color: #ffffff; border-bottom: 2px solid #3d7bfd;
}
QGroupBox {
    border: 1px solid #29313c; border-radius: 11px; margin-top: 15px; padding-top: 10px;
    font-weight: 600; background: #161a21;
}
QGroupBox::title { subcontrol-origin: margin; left: 12px; padding: 0 6px; color: #8ab4f8; }
QPushButton {
    background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 #3d7bfd, stop:1 #2a63e0);
    color: white; border: none; border-radius: 9px;
    padding: 9px 20px; font-weight: 600;
}
QPushButton:hover { background: #4a86ff; }
QPushButton:pressed { background: #2558c9; }
QPushButton:disabled { background: #2a313c; color: #6b7280; }
QPushButton#stop { background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 #d04438, stop:1 #b3392f); }
QPushButton#stop:hover { background: #e0554a; }
QLineEdit, QComboBox {
    background: #1a202a; border: 1px solid #2c3542; border-radius: 7px;
    padding: 6px 9px; color: #e6e8eb;
    selection-background-color: #3d7bfd;
}
QLineEdit:focus, QComboBox:focus { border: 1px solid #3d7bfd; }
QComboBox::drop-down { border: none; width: 22px; }
QComboBox QAbstractItemView {
    background: #1a202a; border: 1px solid #2c3542;
    selection-background-color: #3d7bfd;
}
QCheckBox::indicator { width: 17px; height: 17px; border-radius: 5px;
    border: 1px solid #3a4452; background: #1a202a; }
QCheckBox::indicator:checked { background: #3d7bfd; border-color: #3d7bfd; }
QTextEdit {
    background: #0e1116; border: 1px solid #29313c; border-radius: 9px;
    font-family: Consolas, monospace; font-size: 12px;
    selection-background-color: #3d7bfd;
}
QTableWidget {
    background: #12161d; border: 1px solid #29313c; border-radius: 9px;
    gridline-color: #222a34; alternate-background-color: #151a22;
    selection-background-color: #21314e; selection-color: #ffffff;
}
QHeaderView::section {
    background: #1b212a; color: #8d95a3; border: none;
    border-bottom: 1px solid #2c3542; border-right: 1px solid #222a34;
    padding: 7px 9px; font-weight: 600;
}
QTableWidget::item { padding: 3px 6px; }
QScrollArea { border: none; }
QScrollBar:vertical {
    background: transparent; width: 10px; margin: 2px;
}
QScrollBar::handle:vertical {
    background: #2e3744; border-radius: 5px; min-height: 28px;
}
QScrollBar::handle:vertical:hover { background: #3a4555; }
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0; }
QScrollBar:horizontal { background: transparent; height: 10px; margin: 2px; }
QScrollBar::handle:horizontal { background: #2e3744; border-radius: 5px; min-width: 28px; }
QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal { width: 0; }
QLabel#tileValue { font-size: 21px; font-weight: 700; color: #ffffff; }
QLabel#tileTitle { color: #8d95a3; font-size: 11px; letter-spacing: 1px; }
QFrame#tile {
    background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 #1d242e, stop:1 #171c24);
    border: 1px solid #2a3340; border-radius: 11px;
}
"""


# --------------------------------------------------------------------------
# Okragly zegar (QPainter).
# --------------------------------------------------------------------------
class CircularGauge(QWidget):
    """Okragly zegar z podzialka i opcjonalna czerwona strefa (redline).

    redline_frac > 0 rysuje koncowke skali na czerwono (np. 0.88 dla RPM);
    gdy wskazanie wejdzie w strefe, wartosc rowniez robi sie czerwona.
    """

    def __init__(self, label: str, max_value: float, color: str = "#3d7bfd",
                 redline_frac: float = 0.0) -> None:
        super().__init__()
        self._label = label
        self._max = max(1.0, float(max_value))
        self._color = color
        self._redline = max(0.0, min(1.0, float(redline_frac)))
        self._value = 0.0
        self.setMinimumSize(190, 190)

    def sizeHint(self) -> QSize:
        return QSize(210, 210)

    def set_value(self, v: float) -> None:
        self._value = max(0.0, float(v))
        self.update()

    def set_max(self, m: float) -> None:
        m = max(1.0, float(m))
        if abs(m - self._max) > 1e-6:
            self._max = m
            self.update()

    START_ANGLE = 225      # gora-lewo
    FULL_SPAN = -270       # zgodnie z ruchem wskazowek

    def paintEvent(self, _event) -> None:
        import math as _m
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        w, h = self.width(), self.height()
        side = min(w, h)
        margin = 20
        rect = QRectF((w - side) / 2 + margin, (h - side) / 2 + margin,
                      side - 2 * margin, side - 2 * margin)
        cx, cy = rect.center().x(), rect.center().y()
        radius = rect.width() / 2

        # Tlo luku.
        p.setPen(QPen(QColor("#272f3a"), 13, Qt.SolidLine, Qt.RoundCap))
        p.drawArc(rect, int(self.START_ANGLE * 16), int(self.FULL_SPAN * 16))

        # Czerwona strefa (redline) na tle skali.
        if self._redline > 0:
            red_start = self.START_ANGLE + self.FULL_SPAN * self._redline
            red_span = self.FULL_SPAN * (1.0 - self._redline)
            p.setPen(QPen(QColor(224, 85, 74, 130), 13, Qt.SolidLine, Qt.FlatCap))
            p.drawArc(rect, int(red_start * 16), int(red_span * 16))

        # Podzialka: 9 kresek co 1/8 skali (na zewnatrz luku wartosci).
        p.setPen(QPen(QColor("#3a4452"), 2))
        for i in range(9):
            f = i / 8.0
            ang = _m.radians(self.START_ANGLE + self.FULL_SPAN * f)
            r1, r2 = radius - 18, radius - 11
            p.drawLine(int(cx + r1 * _m.cos(ang)), int(cy - r1 * _m.sin(ang)),
                       int(cx + r2 * _m.cos(ang)), int(cy - r2 * _m.sin(ang)))

        # Luk wartosci (czerwienieje w strefie redline).
        frac = max(0.0, min(1.0, self._value / self._max))
        in_red = self._redline > 0 and frac >= self._redline
        p.setPen(QPen(QColor("#e0554a" if in_red else self._color),
                      13, Qt.SolidLine, Qt.RoundCap))
        p.drawArc(rect, int(self.START_ANGLE * 16), int(self.FULL_SPAN * frac * 16))

        # Wartosc.
        p.setPen(QColor("#ff6e63" if in_red else "#ffffff"))
        p.setFont(QFont("Segoe UI", 27, QFont.Bold))
        val_rect = QRectF(rect.x(), rect.y() + rect.height() * 0.30,
                          rect.width(), rect.height() * 0.40)
        p.drawText(val_rect, Qt.AlignCenter, f"{self._value:.0f}")

        # Etykieta.
        p.setPen(QColor("#8d95a3"))
        p.setFont(QFont("Segoe UI", 10))
        lbl_rect = QRectF(rect.x(), rect.y() + rect.height() * 0.62,
                          rect.width(), 26)
        p.drawText(lbl_rect, Qt.AlignCenter, self._label)
        p.end()


# --------------------------------------------------------------------------
# Watek roboczy (telemetria + inzynier + glos).
# --------------------------------------------------------------------------
class EngineerWorker(QThread):
    status = Signal(str)
    event = Signal(str)
    telemetry = Signal(dict)
    failed = Signal(str)
    stopped = Signal()

    def __init__(self, cfg: Config, ref_path: str | None = None) -> None:
        super().__init__()
        self.cfg = cfg
        self._stop = threading.Event()
        # Okrazenie referencyjne: sciezka startowa + kolejka zmian w trakcie
        # jazdy (GUI dopisuje, petla telemetrii zdejmuje - bezpieczne pod GIL).
        self._ref_path = ref_path
        self._ref_changes: list[str | None] = []

    def stop(self) -> None:
        self._stop.set()

    def set_reference(self, path: str | None) -> None:
        """Zmiana referencji w trakcie jazdy (None = wyczysc). Watkowo bezpieczne."""
        self._ref_changes.append(path)

    def run(self) -> None:
        cfg = self.cfg
        # Preflight silnika edge: jesli brak pakietow, nie probuj cicho (najczestszy
        # powod "edge nie dziala w apce") - pokaz powod i wroc do sapi.
        engine = cfg.speech.engine
        if engine == "edge":
            ok, why = edge_backend.check_available()
            if not ok:
                self.event.emit(f"[GLOS] edge niedostepny: {why}. Przelaczam na sapi.")
                engine = "sapi"
        speaker = Speaker(
            enabled=cfg.speech.enabled,
            rate=cfg.speech.rate,
            volume=cfg.speech.volume,
            voice_substring=cfg.speech.voice_substring,
            output_device=cfg.speech.output_device,
            min_gap_seconds=cfg.speech.min_gap_seconds,
            engine=engine,
            edge_voice=cfg.speech.edge_voice,
            language=cfg.speech.language,
            error_callback=self.event.emit,
        )
        speaker.start()
        engineer = RaceEngineer(cfg.engineer, language=cfg.speech.language)
        # Nagrywanie telemetrii per-okrazenie (Garage 61). base_dir = folder projektu.
        recorder = TelemetryRecorder(cfg.recording, base_dir=os.path.dirname(os.path.abspath(__file__)))

        # Okrazenie referencyjne wybrane przed startem.
        if self._ref_path:
            try:
                info = engineer.set_reference(self._ref_path)
                self.event.emit(f"[REFERENCJA] {info.car_name}, {info.lap_time} ({info.track_key})")
            except (OSError, ValueError) as e:
                self.event.emit(f"[REFERENCJA] Nie udalo sie wczytac: {e}")

        # Sygnal startowy jak w CrewChief: krotki beep radiowy + "radio check".
        radio_beep(output_device=cfg.speech.output_device)
        speaker.say(engineer.M.radio_check(), key="radio_check", min_gap=0)

        self.status.emit(f"Lacze z konsola {cfg.telemetry.playstation_ip}...")
        last_tele = 0.0
        try:
            with GT7Listener(
                playstation_ip=cfg.telemetry.playstation_ip,
                send_port=cfg.telemetry.send_port,
                receive_port=cfg.telemetry.receive_port,
                heartbeat_every=cfg.telemetry.heartbeat_every,
                packet_format=cfg.telemetry.packet_format,
            ) as listener:
                self.status.emit(
                    f"Nasluch na porcie {cfg.telemetry.receive_port} "
                    f"(format '{cfg.telemetry.packet_format}'). Czekam na dane z GT7...")
                while not self._stop.is_set():
                    # Zmiana referencji zlecona z GUI w trakcie jazdy.
                    while self._ref_changes:
                        new_ref = self._ref_changes.pop(0)
                        try:
                            if new_ref is None:
                                engineer.clear_reference()
                                self.event.emit("[REFERENCJA] Wyczyszczona.")
                            else:
                                info = engineer.set_reference(new_ref)
                                self.event.emit(
                                    f"[REFERENCJA] {info.car_name}, {info.lap_time} ({info.track_key})")
                        except (OSError, ValueError) as e:
                            self.event.emit(f"[REFERENCJA] Nie udalo sie wczytac: {e}")
                    packet = listener.receive()
                    if packet is None:
                        continue
                    for ann in engineer.update(packet):
                        self.event.emit(ann.text)
                        speaker.say(ann.text, ann.priority, key=ann.key, min_gap=ann.min_gap)
                    # Diagnostyka paliwa: tylko do logu (bez glosu) - pomaga
                    # przesledzic, jak liczona jest srednia spalania.
                    for line in engineer.pop_fuel_debug():
                        self.event.emit(line)
                    saved = recorder.update(packet)
                    if saved:
                        self.event.emit(f"[NAGRYWANIE] Zapisano okrazenie: {os.path.basename(saved)}")
                    now = time.monotonic()
                    if now - last_tele >= 0.1:
                        last_tele = now
                        self.telemetry.emit(snapshot(packet, engineer))
        except Exception as e:  # noqa: BLE001
            self.failed.emit(f"{type(e).__name__}: {e}")
        finally:
            speaker.stop()
            self.stopped.emit()


class VoiceWorker(QThread):
    failed = Signal(str)

    def __init__(self, text: str, engine: str, language: str, voice: str,
                 rate: int, output_device: str) -> None:
        super().__init__()
        self.text = text
        self.engine = engine
        self.language = language
        self.voice = voice
        self.rate = rate
        self.output_device = output_device

    def run(self) -> None:
        try:
            if self.engine == "edge":
                ok, why = edge_backend.check_available()
                if not ok:
                    self.failed.emit(f"edge niedostepny: {why}")
                    return
            sp = Speaker(
                enabled=True, rate=self.rate, volume=1.0,
                voice_substring=(self.voice if self.engine == "sapi" else ""),
                output_device=self.output_device,
                engine=self.engine,
                edge_voice=(self.voice if self.engine == "edge" else ""),
                language=self.language,
            )
            if self.engine == "edge":
                sp._say_edge(self.text)
            else:
                eng = sp._make_engine()
                eng.say(self.text)
                eng.runAndWait()
                try:
                    eng.stop()
                except Exception:
                    pass
        except Exception as e:  # noqa: BLE001
            self.failed.emit(f"{type(e).__name__}: {e}")


class VoiceListWorker(QThread):
    """Pobiera liste glosow w tle (edge: online, filtrowane po jezyku; sapi: lokalne).

    Synteza listy edge wymaga sieci, a lokalne pyttsx3 inicjuje COM - oba moga
    chwile potrwac, wiec robimy to poza glownym watkiem, by GUI nie zamarzlo.
    """
    done = Signal(list)   # lista (wartosc_do_uzycia, etykieta)
    failed = Signal(str)

    def __init__(self, engine: str, language: str) -> None:
        super().__init__()
        self.engine = engine
        self.language = language

    def run(self) -> None:
        try:
            if self.engine == "edge":
                voices = edge_backend.list_voices(self.language)
                items = [(short, f"{short}  ({desc})") for short, desc in voices]
            else:
                from gt7_engineer.speech.speaker import list_voices as sapi_voices
                items = [(name, f"{name}") for _vid, name in sapi_voices()]
            self.done.emit(items)
        except Exception as e:  # noqa: BLE001
            self.failed.emit(f"{type(e).__name__}: {e}")


# --------------------------------------------------------------------------
# Glowne okno.
# --------------------------------------------------------------------------
class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("GT7 Race Engineer")
        self.resize(940, 660)

        self.cfg = Config.load(CONFIG_PATH)
        self.worker: EngineerWorker | None = None
        self.voice_worker: VoiceWorker | None = None
        self._setting_widgets: dict[tuple[str, str], object] = {}
        self._setting_kinds: dict[tuple[str, str], str] = {}
        self._tiles: dict[str, QLabel] = {}
        self._tyre_labels: list[QLabel] = []
        self._samples: list = []
        self.ref_path: str | None = None   # okrazenie referencyjne (sciezka nagrania)

        tabs = QTabWidget()
        tabs.addTab(self._engineer_tab(), "Inzynier")
        tabs.addTab(self._live_tab(), "Podglad")
        tabs.addTab(self._recordings_tab(), "Nagrania")
        tabs.addTab(self._settings_tab(), "Ustawienia")
        tabs.addTab(self._voice_tab(), "Test glosow")
        self.setCentralWidget(tabs)

    # --- Zakladka: Inzynier ---
    def _engineer_tab(self) -> QWidget:
        w = QWidget()
        lay = QVBoxLayout(w)
        lay.setContentsMargins(16, 16, 16, 16)

        bar = QHBoxLayout()
        self.btn_start = QPushButton("Start")
        self.btn_start.clicked.connect(self._on_start)
        self.btn_stop = QPushButton("Stop")
        self.btn_stop.setObjectName("stop")
        self.btn_stop.setEnabled(False)
        self.btn_stop.clicked.connect(self._on_stop)
        self.status_lbl = QLabel("Zatrzymany.")
        self.status_lbl.setStyleSheet("color:#9aa0a6;")
        bar.addWidget(self.btn_start)
        bar.addWidget(self.btn_stop)
        bar.addSpacing(12)
        bar.addWidget(self.status_lbl, 1)
        lay.addLayout(bar)

        lay.addWidget(QLabel("Log zdarzen:"))
        self.log = QTextEdit()
        self.log.setReadOnly(True)
        lay.addWidget(self.log, 1)
        return w

    # --- Zakladka: Podglad ---
    def _make_tile(self, key: str, title: str) -> QFrame:
        frame = QFrame()
        frame.setObjectName("tile")
        v = QVBoxLayout(frame)
        v.setContentsMargins(14, 10, 14, 10)
        t = QLabel(title)
        t.setObjectName("tileTitle")
        val = QLabel("-")
        val.setObjectName("tileValue")
        v.addWidget(t)
        v.addWidget(val)
        self._tiles[key] = val
        return frame

    def _live_tab(self) -> QWidget:
        w = QWidget()
        lay = QVBoxLayout(w)
        lay.setContentsMargins(16, 16, 16, 16)
        lay.setSpacing(14)

        # Gora: zegary + srodek (bieg + delta).
        top = QHBoxLayout()
        self.gauge_speed = CircularGauge("km/h", 340, "#3d7bfd")
        # RPM z czerwona strefa: koncowe ~12% skali (limiter z telemetrii
        # ustawia max, wiec strefa trzyma sie tuz pod odcieciem).
        self.gauge_rpm = CircularGauge("RPM", 9000, "#f4a72a", redline_frac=0.88)

        center = QVBoxLayout()
        center.addStretch(1)
        gear_title = QLabel("BIEG")
        gear_title.setAlignment(Qt.AlignCenter)
        gear_title.setStyleSheet("color:#9aa0a6; font-size:12px;")
        self.gear_lbl = QLabel("-")
        self.gear_lbl.setAlignment(Qt.AlignCenter)
        self.gear_lbl.setStyleSheet("font-size:56px; font-weight:800; color:#ffffff;")
        delta_title = QLabel("DELTA")
        delta_title.setAlignment(Qt.AlignCenter)
        delta_title.setStyleSheet("color:#9aa0a6; font-size:12px;")
        self.delta_lbl = QLabel("—")
        self.delta_lbl.setAlignment(Qt.AlignCenter)
        self.delta_lbl.setStyleSheet("font-size:30px; font-weight:800; color:#9aa0a6;")
        # Delta do okrazenia referencyjnego (z pliku) - widoczna, gdy ustawiona.
        self.ref_delta_title = QLabel("DELTA REF")
        self.ref_delta_title.setAlignment(Qt.AlignCenter)
        self.ref_delta_title.setStyleSheet("color:#9aa0a6; font-size:12px;")
        self.ref_delta_lbl = QLabel("—")
        self.ref_delta_lbl.setAlignment(Qt.AlignCenter)
        self.ref_delta_lbl.setStyleSheet("font-size:24px; font-weight:800; color:#9aa0a6;")
        self.ref_delta_title.setVisible(False)
        self.ref_delta_lbl.setVisible(False)
        center.addWidget(gear_title)
        center.addWidget(self.gear_lbl)
        center.addSpacing(8)
        center.addWidget(delta_title)
        center.addWidget(self.delta_lbl)
        center.addSpacing(6)
        center.addWidget(self.ref_delta_title)
        center.addWidget(self.ref_delta_lbl)
        center.addStretch(1)

        top.addWidget(self.gauge_speed, 1)
        top.addLayout(center, 1)
        top.addWidget(self.gauge_rpm, 1)
        lay.addLayout(top, 1)

        # Srodek: kafelki.
        tiles = QHBoxLayout()
        for key, title in [("fuel", "Paliwo / Bateria"), ("lap", "Okrazenie"),
                           ("pos", "Pozycja"), ("last", "Ostatnie okr."),
                           ("best", "Najlepsze okr.")]:
            tiles.addWidget(self._make_tile(key, title))
        lay.addLayout(tiles)

        # Dol: opony.
        tyre_box = QGroupBox("Temperatura opon (C)")
        tg = QGridLayout(tyre_box)
        names = ["Lewa przod", "Prawa przod", "Lewa tyl", "Prawa tyl"]
        for i, name in enumerate(names):
            t = QLabel(name)
            t.setStyleSheet("color:#9aa0a6; font-size:11px;")
            t.setAlignment(Qt.AlignCenter)
            val = QLabel("-")
            val.setAlignment(Qt.AlignCenter)
            val.setStyleSheet("font-size:18px; font-weight:700;")
            self._tyre_labels.append(val)
            tg.addWidget(t, 0, i)
            tg.addWidget(val, 1, i)
        lay.addWidget(tyre_box)
        return w

    # --- Zakladka: Nagrania ---
    def _recordings_dir(self) -> str:
        """Katalog nagran z configu (wzgledny = wzgledem folderu projektu)."""
        d = getattr(getattr(self.cfg, "recording", None), "output_dir", "recordings")
        return d if os.path.isabs(d) else os.path.join(_ROOT, d)

    def _recordings_tab(self) -> QWidget:
        w = QWidget()
        lay = QVBoxLayout(w)
        lay.setContentsMargins(16, 16, 16, 16)
        lay.setSpacing(10)

        bar = QHBoxLayout()
        btn_refresh = QPushButton("Odswiez")
        btn_refresh.clicked.connect(self._refresh_recordings)
        self.btn_viewer = QPushButton("Generuj i otworz podglad HTML")
        self.btn_viewer.clicked.connect(self._on_open_viewer)
        self.btn_del_rec = QPushButton("Usun zaznaczone")
        self.btn_del_rec.setObjectName("stop")
        self.btn_del_rec.clicked.connect(self._on_delete_recordings)
        self.rec_count_lbl = QLabel("")
        self.rec_count_lbl.setStyleSheet("color:#9aa0a6;")
        bar.addWidget(btn_refresh)
        bar.addWidget(self.btn_viewer)
        bar.addWidget(self.btn_del_rec)
        bar.addSpacing(12)
        bar.addWidget(self.rec_count_lbl, 1)
        lay.addLayout(bar)

        # Okrazenie referencyjne: dowolne nagrane kolko (takze z innego auta).
        ref_bar = QHBoxLayout()
        self.btn_set_ref = QPushButton("Ustaw jako referencje")
        self.btn_set_ref.clicked.connect(self._on_set_reference)
        self.btn_clear_ref = QPushButton("Wyczysc referencje")
        self.btn_clear_ref.clicked.connect(self._on_clear_reference)
        self.btn_tyre_report = QPushButton("Raport opon")
        self.btn_tyre_report.clicked.connect(self._on_tyre_report)
        self.ref_lbl = QLabel("Referencja: brak")
        self.ref_lbl.setStyleSheet("color:#9aa0a6;")
        ref_bar.addWidget(self.btn_set_ref)
        ref_bar.addWidget(self.btn_clear_ref)
        ref_bar.addWidget(self.btn_tyre_report)
        ref_bar.addSpacing(12)
        ref_bar.addWidget(self.ref_lbl, 1)
        lay.addLayout(ref_bar)

        self.rec_table = QTableWidget(0, 6)
        self.rec_table.setHorizontalHeaderLabels(
            ["Tor", "Okr.", "Czas", "Auto", "Nagrano", "Plik"])
        self.rec_table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.rec_table.setSelectionMode(QAbstractItemView.ExtendedSelection)
        self.rec_table.setEditTriggers(QAbstractItemView.NoEditTriggers)
        self.rec_table.verticalHeader().setVisible(False)
        self.rec_table.setAlternatingRowColors(True)
        self.rec_table.setSortingEnabled(True)
        hdr = self.rec_table.horizontalHeader()
        hdr.setSectionResizeMode(QHeaderView.ResizeToContents)
        hdr.setStretchLastSection(True)
        lay.addWidget(self.rec_table, 1)

        self._refresh_recordings()
        return w

    def _refresh_recordings(self) -> None:
        """Przeladowuje tabele nagran z katalogu recordings."""
        rec_dir = self._recordings_dir()
        laps = load_laps(rec_dir) if os.path.isdir(rec_dir) else []
        self.rec_table.setSortingEnabled(False)
        self.rec_table.setRowCount(len(laps))
        for row, lap in enumerate(laps):
            lap_time = lap.get("lap_time") or GT7Packet.format_laptime(
                int(lap.get("lap_ms", 0)))
            recorded = str(lap.get("recorded_at", ""))[:19].replace("T", " ")
            cells = [
                str(lap.get("track_key", "?")),
                str(lap.get("lap_number", "?")),
                lap_time,
                str(lap.get("car_name") or lap.get("car_code", "?")),
                recorded,
                str(lap.get("_file", "")),
            ]
            for col, text in enumerate(cells):
                item = QTableWidgetItem(text)
                if col in (1, 2):
                    item.setTextAlignment(Qt.AlignRight | Qt.AlignVCenter)
                self.rec_table.setItem(row, col, item)
        self.rec_table.setSortingEnabled(True)
        n_tracks = len({lap.get("track_key") for lap in laps})
        self.rec_count_lbl.setText(
            f"Okrazen: {len(laps)} | torow: {n_tracks}" if laps
            else "Brak nagran. Nagrania powstaja automatycznie podczas jazdy.")
        has = bool(laps)
        self.btn_viewer.setEnabled(has)
        self.btn_del_rec.setEnabled(has)

    def _selected_recording_files(self) -> list[str]:
        rec_dir = self._recordings_dir()
        rows = {i.row() for i in self.rec_table.selectedIndexes()}
        files = []
        for row in rows:
            item = self.rec_table.item(row, 5)
            if item and item.text():
                files.append(os.path.join(rec_dir, item.text()))
        return files

    def _on_open_viewer(self) -> None:
        """Generuje samodzielna strone HTML z nagran i otwiera w przegladarce."""
        rec_dir = self._recordings_dir()
        try:
            laps = load_laps(rec_dir)
            if not laps:
                QMessageBox.information(self, "Brak nagran",
                                        "Nie znaleziono zadnych nagran okrazen.")
                return
            out = os.path.join(rec_dir, "telemetria.html")
            with open(out, "w", encoding="utf-8") as f:
                f.write(build_html(laps))
        except Exception as e:  # noqa: BLE001
            QMessageBox.critical(self, "Blad", f"{type(e).__name__}: {e}")
            return
        QDesktopServices.openUrl(QUrl.fromLocalFile(out))

    def _on_delete_recordings(self) -> None:
        files = self._selected_recording_files()
        if not files:
            QMessageBox.information(self, "Nic nie zaznaczono",
                                    "Zaznacz w tabeli nagrania do usuniecia.")
            return
        ans = QMessageBox.question(
            self, "Usun nagrania",
            f"Usunac trwale {len(files)} nagran(ie/ia)?",
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No)
        if ans != QMessageBox.Yes:
            return
        errors = 0
        for path in files:
            try:
                os.remove(path)
            except OSError:
                errors += 1
        if errors:
            QMessageBox.warning(self, "Uwaga",
                                f"Nie udalo sie usunac {errors} plik(ow).")
        self._refresh_recordings()

    # --- Okrazenie referencyjne ---
    def _on_set_reference(self) -> None:
        """Ustawia zaznaczone nagranie jako okrazenie referencyjne.

        Referencja moze pochodzic z innego auta niz obecnie prowadzone -
        delta jest pozycyjna, wiec porownanie dwoch pojazdow dziala wprost.
        """
        files = self._selected_recording_files()
        if len(files) != 1:
            QMessageBox.information(self, "Wybierz jedno nagranie",
                                    "Zaznacz dokladnie jedno okrazenie z tabeli.")
            return
        path = files[0]
        # Walidacja pliku od razu (nie czekajac na start inzyniera).
        try:
            from gt7_engineer.engineer.reference import ReferenceDelta
            info = ReferenceDelta().load(path)
        except (OSError, ValueError) as e:
            QMessageBox.critical(self, "Niepoprawne nagranie", str(e))
            return
        self.ref_path = path
        self.ref_lbl.setText(
            f"Referencja: {info.car_name}, {info.lap_time} ({info.track_key})")
        # Jesli inzynier dziala - podmien referencje w locie.
        if self.worker is not None:
            self.worker.set_reference(path)
        else:
            self._append_log(f"[REFERENCJA] Ustawiona: {info.car_name}, {info.lap_time}")

    def _on_clear_reference(self) -> None:
        self.ref_path = None
        self.ref_lbl.setText("Referencja: brak")
        if self.worker is not None:
            self.worker.set_reference(None)
        else:
            self._append_log("[REFERENCJA] Wyczyszczona.")

    def _on_tyre_report(self) -> None:
        """Generuje raport temperatur opon (HTML) z nagran i otwiera go."""
        rec_dir = self._recordings_dir()
        try:
            from tools.tyre_report import build_report_html
            laps = load_laps(rec_dir)
            if not laps:
                QMessageBox.information(self, "Brak nagran",
                                        "Nie znaleziono zadnych nagran okrazen.")
                return
            out = os.path.join(rec_dir, "raport_opon.html")
            with open(out, "w", encoding="utf-8") as f:
                f.write(build_report_html(laps))
        except Exception as e:  # noqa: BLE001
            QMessageBox.critical(self, "Blad", f"{type(e).__name__}: {e}")
            return
        QDesktopServices.openUrl(QUrl.fromLocalFile(out))

    # --- Zakladka: Ustawienia ---
    def _settings_tab(self) -> QWidget:
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        inner = QWidget()
        lay = QVBoxLayout(inner)
        lay.setContentsMargins(16, 16, 16, 16)

        for section, sec_label, fields in SETTINGS_SCHEMA:
            box = QGroupBox(sec_label)
            form = QFormLayout(box)
            form.setLabelAlignment(Qt.AlignRight)
            sec_obj = getattr(self.cfg, section)
            for field in fields:
                key, label, kind = field[0], field[1], field[2]
                options = field[3] if len(field) > 3 else None
                cur = getattr(sec_obj, key)
                self._setting_kinds[(section, key)] = kind
                if kind == "bool":
                    widget: object = QCheckBox()
                    widget.setChecked(bool(cur))
                elif kind == "choice":
                    widget = QComboBox()
                    widget.addItems(options or [])
                    idx = widget.findText(str(cur))
                    if idx >= 0:
                        widget.setCurrentIndex(idx)
                elif kind == "voice":
                    # Edytowalna lista glosow edge - wypelniana w tle (mozna tez
                    # wpisac wlasna nazwe ShortName).
                    widget = QComboBox()
                    widget.setEditable(True)
                    widget.setMinimumWidth(320)
                    widget.setEditText("" if cur is None else str(cur))
                    self._settings_voice_combo = widget
                else:
                    widget = QLineEdit("" if cur is None else str(cur))
                self._setting_widgets[(section, key)] = widget
                form.addRow(label, widget)
            lay.addWidget(box)

        save = QPushButton("Zapisz ustawienia")
        save.clicked.connect(self._on_save_settings)
        lay.addWidget(save)
        lay.addStretch(1)

        # Wypelnij liste glosow edge w tle i odswiezaj ja przy zmianie jezyka.
        self.settings_voice_worker: VoiceListWorker | None = None
        lang_w = self._setting_widgets.get(("speech", "language"))
        if isinstance(lang_w, QComboBox):
            lang_w.currentTextChanged.connect(lambda _=None: self._populate_settings_voice())
        self._populate_settings_voice()

        scroll.setWidget(inner)
        return scroll

    def _populate_settings_voice(self) -> None:
        """Wczytuje glosy edge dla biezacego jezyka do listy w Ustawieniach (w tle)."""
        combo = getattr(self, "_settings_voice_combo", None)
        if combo is None:
            return
        if self.settings_voice_worker is not None and self.settings_voice_worker.isRunning():
            return
        keep = combo.currentText()
        lang_w = self._setting_widgets.get(("speech", "language"))
        lang = (lang_w.currentText() if isinstance(lang_w, QComboBox)
                else (self.cfg.speech.language or "pl"))
        combo.setEnabled(False)
        self.settings_voice_worker = VoiceListWorker("edge", lang or "pl")
        self.settings_voice_worker.done.connect(
            lambda items: self._fill_settings_voice(items, keep))
        self.settings_voice_worker.failed.connect(lambda _m: combo.setEnabled(True))
        self.settings_voice_worker.start()

    def _fill_settings_voice(self, items: list, keep: str) -> None:
        combo = self._settings_voice_combo
        combo.blockSignals(True)
        combo.clear()
        for value, label in items:
            combo.addItem(label, value)
        idx = combo.findData(keep) if keep else -1
        if idx >= 0:
            combo.setCurrentIndex(idx)
        else:
            combo.setEditText(keep)
        combo.blockSignals(False)
        combo.setEnabled(True)

    # --- Zakladka: Test glosow ---
    def _voice_tab(self) -> QWidget:
        w = QWidget()
        lay = QVBoxLayout(w)
        lay.setContentsMargins(16, 16, 16, 16)
        form = QFormLayout()

        self.v_lang = QComboBox()
        self.v_lang.addItems(["pl", "en"])
        self.v_lang.setCurrentText(self.cfg.speech.language or "pl")
        self.v_lang.currentTextChanged.connect(self._reload_samples)
        form.addRow("Jezyk:", self.v_lang)

        self.v_engine = QComboBox()
        self.v_engine.addItems(["sapi", "edge"])
        self.v_engine.setCurrentText(self.cfg.speech.engine or "sapi")
        self.v_engine.currentTextChanged.connect(self._reload_voices)
        form.addRow("Silnik:", self.v_engine)

        # Edytowalna lista rozwijana glosow - wypelniana w tle (edge: wszystkie
        # glosy danego jezyka, sapi: lokalne). Mozna tez wpisac wlasna nazwe.
        self.v_voice = QComboBox()
        self.v_voice.setEditable(True)
        self.v_voice.setMinimumWidth(320)
        cur_voice = (self.cfg.speech.edge_voice
                     if (self.cfg.speech.engine or "sapi") == "edge"
                     else self.cfg.speech.voice_substring)
        self.v_voice.setEditText(cur_voice or "")
        form.addRow("Glos (lista lub wlasna nazwa):", self.v_voice)
        self.v_lang.currentTextChanged.connect(self._reload_voices)

        self.v_rate = QLineEdit(str(self.cfg.speech.rate))
        form.addRow("Tempo (slowa/min):", self.v_rate)

        self.v_sample = QComboBox()
        form.addRow("Komunikat:", self.v_sample)

        lay.addLayout(form)
        self.btn_play = QPushButton("Odtworz")
        self.btn_play.clicked.connect(self._on_play_voice)
        lay.addWidget(self.btn_play)
        self.voice_status = QLabel("")
        self.voice_status.setStyleSheet("color:#9aa0a6;")
        lay.addWidget(self.voice_status)
        lay.addStretch(1)

        self.voice_list_worker: VoiceListWorker | None = None
        self._reload_samples()
        self._reload_voices()
        return w

    def _reload_samples(self) -> None:
        self._samples = build_samples(load_messages(self.v_lang.currentText() or "pl"))
        self.v_sample.clear()
        self.v_sample.addItems([s[0] for s in self._samples])

    def _reload_voices(self) -> None:
        """Wypelnia liste glosow w tle, zachowujac biezacy wpis uzytkownika."""
        if self.voice_list_worker is not None and self.voice_list_worker.isRunning():
            return
        keep = self.v_voice.currentText()
        engine = self.v_engine.currentText()
        self.v_voice.setEnabled(False)
        self.voice_status.setText("Wczytuje liste glosow...")
        self.voice_list_worker = VoiceListWorker(engine, self.v_lang.currentText() or "pl")
        self.voice_list_worker.done.connect(lambda items: self._fill_voices(items, keep))
        self.voice_list_worker.failed.connect(self._on_voices_failed)
        self.voice_list_worker.start()

    def _fill_voices(self, items: list, keep: str) -> None:
        self.v_voice.blockSignals(True)
        self.v_voice.clear()
        for value, label in items:
            self.v_voice.addItem(label, value)
        # Przywroc wybor uzytkownika (po wartosci albo jako wolny tekst).
        idx = self.v_voice.findData(keep) if keep else -1
        if idx >= 0:
            self.v_voice.setCurrentIndex(idx)
        else:
            self.v_voice.setEditText(keep)
        self.v_voice.blockSignals(False)
        self.v_voice.setEnabled(True)
        self.voice_status.setText(f"Glosow na liscie: {len(items)}.")

    def _on_voices_failed(self, msg: str) -> None:
        self.v_voice.setEnabled(True)
        self.voice_status.setText(f"Nie udalo sie wczytac glosow: {msg}")

    # --- Akcje ---
    def _on_start(self) -> None:
        if self.worker is not None:
            return
        self.cfg = Config.load(CONFIG_PATH)
        self._append_log("--- Start inzyniera ---")
        self.worker = EngineerWorker(self.cfg, ref_path=self.ref_path)
        self.worker.status.connect(self.status_lbl.setText)
        self.worker.event.connect(self._append_log)
        self.worker.telemetry.connect(self._update_live)
        self.worker.failed.connect(self._on_error)
        self.worker.stopped.connect(self._on_stopped)
        self.worker.start()
        self.btn_start.setEnabled(False)
        self.btn_stop.setEnabled(True)
        self.status_lbl.setText("Uruchamiam...")

    def _on_stop(self) -> None:
        if self.worker is not None:
            self.status_lbl.setText("Zatrzymuje...")
            self.worker.stop()

    def _on_error(self, msg: str) -> None:
        self._append_log(f"[BLAD] {msg}")
        self.status_lbl.setText(f"Blad: {msg}")

    def _on_stopped(self) -> None:
        self.worker = None
        self.btn_start.setEnabled(True)
        self.btn_stop.setEnabled(False)
        self.status_lbl.setText("Zatrzymany.")
        self._append_log("--- Inzynier zatrzymany ---")

    def _on_save_settings(self) -> None:
        values: dict[tuple[str, str], str] = {}
        try:
            for (section, key), widget in self._setting_widgets.items():
                kind = self._setting_kinds[(section, key)]
                if kind == "bool":
                    values[(section, key)] = "true" if widget.isChecked() else "false"
                elif kind == "choice":
                    values[(section, key)] = f'"{widget.currentText()}"'
                elif kind == "voice":
                    # Wybrana pozycja listy ma dane (ShortName); inaczej wpisany tekst.
                    data = widget.currentData()
                    typed = widget.currentText().strip()
                    val = (data if data and widget.findData(data) == widget.currentIndex()
                           else typed)
                    values[(section, key)] = f'"{val}"'
                elif kind == "int":
                    values[(section, key)] = str(int(widget.text().strip()))
                elif kind == "float":
                    values[(section, key)] = str(float(widget.text().strip()))
                else:
                    values[(section, key)] = f'"{widget.text()}"'
        except ValueError as e:
            QMessageBox.critical(self, "Blad", f"Nieprawidlowa wartosc liczbowa: {e}")
            return
        try:
            save_config_values(CONFIG_PATH, values)
        except Exception as e:  # noqa: BLE001
            QMessageBox.critical(self, "Blad zapisu", f"{type(e).__name__}: {e}")
            return
        self.cfg = Config.load(CONFIG_PATH)
        QMessageBox.information(self, "Zapisano",
                               "Ustawienia zapisane do config.yaml.\n"
                               "Zmiany wejda w zycie po nastepnym Starcie.")

    def _on_play_voice(self) -> None:
        label = self.v_sample.currentText()
        fn = None
        for lab, f in self._samples:
            if lab == label:
                fn = f
                break
        if fn is None:
            return
        try:
            rate = int(self.v_rate.text())
        except ValueError:
            rate = 175
        text = fn()
        self.voice_status.setText(f"Odtwarzam: {text}")
        self.btn_play.setEnabled(False)
        # Wartosc glosu: jesli wybrano pozycje z listy - bierzemy jej dane
        # (ShortName/identyfikator), inaczej to, co uzytkownik wpisal recznie.
        data = self.v_voice.currentData()
        typed = self.v_voice.currentText().strip()
        # Gdy biezaca pozycja listy ma dane = uzyj ich (np. ShortName edge),
        # w przeciwnym razie potraktuj tekst jako recznie wpisana nazwe.
        voice = (data if data and self.v_voice.findData(data) == self.v_voice.currentIndex()
                 else typed)
        self.voice_worker = VoiceWorker(
            text=text,
            engine=self.v_engine.currentText(),
            language=self.v_lang.currentText(),
            voice=voice,
            rate=rate,
            output_device=self.cfg.speech.output_device,
        )
        self.voice_worker.failed.connect(
            lambda m: self.voice_status.setText(f"Blad glosu: {m}"))
        self.voice_worker.finished.connect(lambda: self.btn_play.setEnabled(True))
        self.voice_worker.start()

    # --- Aktualizacja podgladu ---
    def _update_live(self, s: dict) -> None:
        # Skala zegarow pod auto: vmax i limiter z telemetrii (fallback gdy 0).
        smax = s.get("speed_max", 0.0)
        if smax and smax > 1.0:
            self.gauge_speed.set_max(smax)
        rmax = s.get("rpm_max", 0.0)
        if rmax and rmax > 1.0:
            self.gauge_rpm.set_max(rmax)
        self.gauge_speed.set_value(s.get("speed", 0.0))
        self.gauge_rpm.set_value(s.get("rpm", 0.0))
        self.gear_lbl.setText(s.get("gear", "-"))
        for key in ("fuel", "lap", "pos", "last", "best"):
            if key in self._tiles:
                self._tiles[key].setText(str(s.get(key, "-")))

        tyres = s.get("tyres") or ()
        warn = self.cfg.engineer.tyre_temp_warning
        for i, lbl in enumerate(self._tyre_labels):
            if i < len(tyres):
                t = tyres[i]
                lbl.setText(f"{t:.0f}")
                if t >= warn:
                    color = "#e0554a"
                elif t >= warn - 15:
                    color = "#f4a72a"
                else:
                    color = "#5bd17a"
                lbl.setStyleSheet(f"font-size:18px; font-weight:700; color:{color};")
            else:
                lbl.setText("-")

        d = s.get("delta")
        if d is None:
            self.delta_lbl.setText("—")
            self.delta_lbl.setStyleSheet("font-size:30px; font-weight:800; color:#9aa0a6;")
        else:
            color = "#5bd17a" if d < 0 else "#e0554a"
            self.delta_lbl.setText(f"{d:+.2f} s")
            self.delta_lbl.setStyleSheet(f"font-size:30px; font-weight:800; color:{color};")

        # Delta do referencji - sekcja widoczna tylko, gdy referencja ustawiona.
        ref_loaded = bool(s.get("ref_loaded"))
        self.ref_delta_title.setVisible(ref_loaded)
        self.ref_delta_lbl.setVisible(ref_loaded)
        rd = s.get("ref_delta")
        if rd is None:
            self.ref_delta_lbl.setText("—")
            self.ref_delta_lbl.setStyleSheet("font-size:24px; font-weight:800; color:#9aa0a6;")
        else:
            color = "#5bd17a" if rd < 0 else "#e0554a"
            self.ref_delta_lbl.setText(f"{rd:+.2f} s")
            self.ref_delta_lbl.setStyleSheet(f"font-size:24px; font-weight:800; color:{color};")

    def _append_log(self, text: str) -> None:
        self.log.append(text)
        # Zapis okrazenia przez recorder -> odswiez tabele w zakladce Nagrania.
        if text.startswith("[NAGRYWANIE]"):
            self._refresh_recordings()

    def closeEvent(self, event) -> None:
        if self.worker is not None:
            self.worker.stop()
            self.worker.wait(6000)
        super().closeEvent(event)


def main() -> int:
    app = QApplication(sys.argv)
    app.setStyleSheet(DARK_QSS)
    win = MainWindow()
    win.show()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())

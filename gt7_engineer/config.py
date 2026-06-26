"""Wczytywanie i walidacja konfiguracji z config.yaml."""

from __future__ import annotations

import os
from dataclasses import dataclass, field, fields
from typing import Any

import yaml


def _only_known(dc_type, raw: dict | None) -> dict:
    """Odsiewa nieznane klucze z config.yaml, by stare/nowe pliki sie nie wywracaly.

    Dzieki temu po zmianie nazw opcji (np. usunieciu stref toru) stary config.yaml
    nie powoduje bledu - nieznane klucze sa po prostu ignorowane.
    """
    raw = raw or {}
    allowed = {f.name for f in fields(dc_type)}
    return {k: v for k, v in raw.items() if k in allowed}


@dataclass
class TelemetryConfig:
    playstation_ip: str = "192.168.1.100"
    send_port: int = 33739
    receive_port: int = 33740
    heartbeat_every: int = 100
    packet_format: str = "A"   # "A" (296B), "B" (316B, +ruch), "~" (344B, +surowe pedaly)


@dataclass
class EngineerConfig:
    fuel_warning_laps: float = 3.0
    fuel_critical_laps: float = 1.5
    pit_window_laps: float = 2.0
    min_laps_for_fuel_calc: int = 1
    tyre_temp_warning: float = 110.0
    announce_lap_times: bool = True
    announce_position_changes: bool = True
    announce_best_lap: bool = True
    # Strategia paliwowa: czy starczy do mety, ile oszczedzac, ile dotankowac.
    announce_fuel_strategy: bool = True
    fuel_target_margin_laps: float = 0.5   # zapas paliwa na koniec (w okrazeniach)
    # Limit gadania o paliwie: inzynier mowi najwyzej tyle komunikatow
    # paliwowych na okrazenie (najwazniejszy wygrywa: krytyczny > ostrzezenie
    # > oszczedzanie > reszta). 0 = paliwo calkiem wyciszone.
    fuel_max_messages_per_lap: int = 1
    # "Paliwa starczy do mety z zapasem X" - domyslnie wylaczone (gdy paliwa
    # wystarcza, inzynier po prostu milczy).
    announce_fuel_ok_to_finish: bool = False
    # Auto-wykrywanie zakretow pod katem przegrzewania opon (zamiast stref toru).
    announce_corner_tyres: bool = True
    corner_temp_warning: float = 95.0      # od jakiej temp. raportowac goracy zakret
    # Delta do najlepszego okrazenia - czytana tylko na prostej (anty-rozpraszanie).
    announce_delta: bool = True
    delta_min_seconds: float = 0.15        # ponizej tej delty (w sek.) nie raportujemy
    # Okrazenie referencyjne (nagrane kolko z pliku, takze z innego auta):
    # komunikaty o stracie/zysku per sektor toru.
    announce_ref_sectors: bool = True
    ref_sectors: int = 3                   # na ile sektorow dzielic okrazenie
    ref_sector_min_seconds: float = 0.3    # min. zmiana delty w sektorze, by ja czytac
    # Podglad paliwa: ktore informacje pokazywac w kafelku "Paliwo".
    fuel_show_percent: bool = True         # poziom paliwa w % (2 miejsca po przecinku)
    fuel_show_avg: bool = True             # srednie spalanie na okrazenie
    fuel_show_laps_left: bool = True       # ile okrazen do konca paliwa
    fuel_avg_window: int = 3               # z ilu ostatnich okrazen liczyc srednia


@dataclass
class RecordingConfig:
    """Nagrywanie telemetrii w stylu Garage 61: zapis pelnych okrazen do plikow.

    Kazde poprawne okrazenie laduje w osobnym pliku JSON w katalogu output_dir.
    Probki zapisujemy z czestotliwoscia sample_hz (GT7 nadaje ~60 Hz, wiec
    20 Hz wystarcza na gladka linie toru, a plik pozostaje maly).
    """
    enabled: bool = True
    output_dir: str = "recordings"
    sample_hz: float = 20.0            # ile probek na sekunde zapisywac
    min_lap_seconds: float = 10.0      # krotsze "okrazenia" odrzucamy (smieci)


@dataclass
class SpeechConfig:
    enabled: bool = True
    rate: int = 175
    volume: float = 1.0
    voice_substring: str = ""
    output_device: str = ""   # fragment nazwy urzadzenia wyjscia audio (np. "CABLE")
    language: str = "pl"
    min_gap_seconds: float = 1.5
    engine: str = "sapi"      # "sapi" (offline, Windows) lub "edge" (neuronowe, online)
    edge_voice: str = ""      # glos edge-tts, np. "pl-PL-MarekNeural" (pusty = domyslny dla jezyka)


@dataclass
class DebugConfig:
    print_telemetry: bool = False
    log_events: bool = True


@dataclass
class Config:
    telemetry: TelemetryConfig = field(default_factory=TelemetryConfig)
    engineer: EngineerConfig = field(default_factory=EngineerConfig)
    recording: RecordingConfig = field(default_factory=RecordingConfig)
    speech: SpeechConfig = field(default_factory=SpeechConfig)
    debug: DebugConfig = field(default_factory=DebugConfig)

    @classmethod
    def load(cls, path: str = "config.yaml") -> "Config":
        if not os.path.exists(path):
            # Brak pliku -> uzyj wartosci domyslnych.
            return cls()
        with open(path, "r", encoding="utf-8") as f:
            raw: dict[str, Any] = yaml.safe_load(f) or {}
        return cls(
            telemetry=TelemetryConfig(**_only_known(TelemetryConfig, raw.get("telemetry"))),
            engineer=EngineerConfig(**_only_known(EngineerConfig, raw.get("engineer"))),
            recording=RecordingConfig(**_only_known(RecordingConfig, raw.get("recording"))),
            speech=SpeechConfig(**_only_known(SpeechConfig, raw.get("speech"))),
            debug=DebugConfig(**_only_known(DebugConfig, raw.get("debug"))),
        )

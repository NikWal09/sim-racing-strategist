"""Wczytywanie i walidacja konfiguracji z config.yaml."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Any

import yaml


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
    # Auto-uczenie sekcji toru pod katem przegrzewania opon.
    announce_tyre_sections: bool = True
    tyre_sections: int = 12                # na ile sekcji dzielimy okrazenie
    tyre_section_temp_warning: float = 95.0  # od jakiej temp. raportowac goraca sekcje
    # Delta do najlepszego okrazenia - czytana tylko na prostej (anty-rozpraszanie).
    announce_delta: bool = True
    delta_min_seconds: float = 0.15        # ponizej tej delty (w sek.) nie raportujemy


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
            telemetry=TelemetryConfig(**(raw.get("telemetry") or {})),
            engineer=EngineerConfig(**(raw.get("engineer") or {})),
            speech=SpeechConfig(**(raw.get("speech") or {})),
            debug=DebugConfig(**(raw.get("debug") or {})),
        )

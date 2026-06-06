#!/usr/bin/env python3
"""GT7 Race Engineer - punkt wejscia.

Uruchamia odbior telemetrii GT7, analize wyscigu i komunikaty glosowe.

Przyklady:
    python main.py                      # uzyj config.yaml
    python main.py --config inny.yaml
    python main.py --ip 192.168.1.50    # nadpisz IP konsoli
    python main.py --no-speech          # tylko logi na konsole (bez TTS)
    python main.py --list-voices        # wypisz dostepne glosy TTS i zakoncz
    python main.py --list-outputs       # wypisz urzadzenia wyjscia audio i zakoncz
"""

from __future__ import annotations

import argparse
import sys
import time

from gt7_engineer.config import Config
from gt7_engineer.engineer import RaceEngineer
from gt7_engineer.speech import Speaker
from gt7_engineer.telemetry import GT7Listener


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="GT7 Race Engineer - asystent kierowcy.")
    ap.add_argument("--config", default="config.yaml", help="sciezka do pliku konfiguracji")
    ap.add_argument("--ip", default=None, help="IP konsoli PlayStation (nadpisuje config)")
    ap.add_argument("--no-speech", action="store_true", help="wylacz TTS, tylko logi")
    ap.add_argument("--list-voices", action="store_true", help="wypisz dostepne glosy i zakoncz")
    ap.add_argument("--list-outputs", action="store_true",
                    help="wypisz urzadzenia wyjscia audio (np. kabel wirtualny) i zakoncz")
    return ap.parse_args()


def main() -> int:
    args = parse_args()

    if args.list_voices:
        from gt7_engineer.speech.speaker import list_voices
        print("Dostepne glosy TTS:")
        for vid, name in list_voices():
            print(f"  - {name}  [{vid}]")
        return 0

    if args.list_outputs:
        from gt7_engineer.speech.speaker import list_outputs
        print("Dostepne urzadzenia wyjscia audio:")
        try:
            for desc in list_outputs():
                print(f"  - {desc}")
            print("\nWpisz fragment nazwy do speech.output_device w config.yaml,")
            print("np. 'CABLE', by skierowac glos inzyniera na kabel wirtualny.")
        except Exception as e:  # noqa: BLE001
            print(f"  Blad: {e}")
        return 0

    cfg = Config.load(args.config)
    if args.ip:
        cfg.telemetry.playstation_ip = args.ip
    if args.no_speech:
        cfg.speech.enabled = False

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

    print("=" * 60)
    print("  GT7 RACE ENGINEER")
    print(f"  Konsola PlayStation: {cfg.telemetry.playstation_ip}:{cfg.telemetry.send_port}")
    print(f"  Nasluch telemetrii:  port {cfg.telemetry.receive_port} (format '{cfg.telemetry.packet_format}')")
    print(f"  Glos: {'wlaczony' if cfg.speech.enabled else 'WYLACZONY (tryb logow)'}  (jezyk: {cfg.speech.language})")
    print("  Wcisnij Ctrl+C aby zakonczyc.")
    print("=" * 60)

    last_packet_time = 0.0
    waiting_logged = False

    try:
        with GT7Listener(
            playstation_ip=cfg.telemetry.playstation_ip,
            send_port=cfg.telemetry.send_port,
            receive_port=cfg.telemetry.receive_port,
            heartbeat_every=cfg.telemetry.heartbeat_every,
            packet_format=cfg.telemetry.packet_format,
        ) as listener:
            while True:
                packet = listener.receive()
                if packet is None:
                    if not waiting_logged:
                        print("[...] Czekam na telemetrie z GT7 (gra musi byc w trybie jazdy)...")
                        waiting_logged = True
                    continue
                waiting_logged = False
                last_packet_time = time.monotonic()

                if cfg.debug.print_telemetry:
                    _print_telemetry(packet)

                for ann in engineer.update(packet):
                    if cfg.debug.log_events:
                        print(f"[ENG] {ann.text}")
                    spoken = speaker.say(ann.text, ann.priority, key=ann.key, min_gap=ann.min_gap)
                    if not spoken and not cfg.speech.enabled and not cfg.debug.log_events:
                        print(f"[ENG] {ann.text}")
    except KeyboardInterrupt:
        print("\nKonczenie pracy inzyniera. Do zobaczenia na torze!")
    finally:
        speaker.stop()

    return 0


def _print_telemetry(p) -> None:
    """Pelny zrzut wszystkich pol pakietu - kompletna diagnostyka co ramke."""

    def f4(t, fmt="{:6.1f}"):
        return "[" + ", ".join(fmt.format(x) for x in t) + "]"

    flags = [name for name, on in (
        ("on_track", p.on_track), ("paused", p.paused), ("loading", p.loading),
        ("in_gear", p.in_gear), ("turbo", p.has_turbo), ("rev_limiter", p.rev_limiter),
        ("handbrake", p.handbrake), ("lights", p.lights), ("high_beam", p.high_beam),
        ("low_beam", p.low_beam), ("ASM", p.asm_active), ("TCS", p.tcs_active),
    ) if on] or ["-"]

    tod_s = p.time_of_day_ms / 1000.0
    tod = f"{int(tod_s // 3600) % 24:02d}:{int(tod_s // 60) % 60:02d}:{int(tod_s) % 60:02d}"

    print("=" * 70)
    print(f"  pakiet #{p.packet_id}   car_code={p.car_code}   flagi: {', '.join(flags)}")
    print(f"  WYSCIG  okr {p.current_lap}/{p.total_laps}   poz {p.position_in_race}/{p.total_cars}"
          f"   last {p.format_laptime(p.last_lap_ms)}  best {p.format_laptime(p.best_lap_ms)}"
          f"   pora dnia {tod}")
    print(f"  NAPED   {p.speed_kph:6.1f} km/h  ({p.speed_mps:6.2f} m/s)   bieg {p.gear}"
          f"  (sugerowany {p.suggested_gear})   RPM {p.rpm:6.0f}"
          f"  alert {p.rpm_alert_min}-{p.rpm_alert_max}   Vmax~{p.calc_max_speed} km/h")
    print(f"  STERY   gaz {p.throttle:3d}/255   hamulec {p.brake:3d}/255   sprzeglo {p.clutch:4.2f}"
          f"  (zazeb. {p.clutch_engaged:4.2f}, RPM po sprz. {p.rpm_after_clutch:6.0f})")
    if p.is_electric:
        print(f"  BATERIA {p.fuel_pct:5.1f} %   (auto elektryczne)")
    else:
        print(f"  PALIWO  {p.current_fuel:6.2f} / {p.fuel_capacity:.0f}  ({p.fuel_pct:5.1f} %)"
              f"   doladowanie/boost {p.boost_bar:+.2f} bar")
    print(f"  PLYNY   olej: cisn. {p.oil_pressure:5.1f}  temp {p.oil_temp:5.1f} C"
          f"   woda {p.water_temp:5.1f} C")
    print(f"  OPONY   temp [FL,FR,RL,RR] {f4(p.tyre_temp)} C")
    print(f"  KOLA    obroty {f4(p.wheel_speed)}   promien {f4(p.tyre_radius, '{:5.3f}')} m")
    print(f"  ZAWIESZ {f4(p.suspension, '{:6.3f}')}   wys. nadwozia {p.body_height:5.3f}")
    print(f"  POZYCJA {f4(p.position, '{:8.2f}')}   predkosc XYZ {f4(p.velocity, '{:7.2f}')}")

    # Pola dostepne tylko w formatach 'B' / '~' (puste przy 'A').
    has_motion = (p.wheel_rotation_rad or p.force_feedback or p.sway
                  or p.heave or p.surge)
    has_raw = (p.throttle_raw or p.brake_raw or p.energy_recovery)
    if has_motion:
        print(f"  RUCH    kierownica {p.wheel_rotation_rad:+.3f} rad  FFB {p.force_feedback:+.3f}"
              f"   sway {p.sway:+.2f}  heave {p.heave:+.2f}  surge {p.surge:+.2f}")
    if has_raw:
        print(f"  SUROWE  gaz {p.throttle_raw:3d}/255  hamulec {p.brake_raw:3d}/255"
              f"   odzysk energii {p.energy_recovery:.2f}")


if __name__ == "__main__":
    sys.exit(main())

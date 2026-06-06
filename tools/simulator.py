#!/usr/bin/env python3
"""Symulator telemetrii GT7 - udaje konsole, zeby przetestowac asystenta bez PS.

Uruchom w jednym terminalu:
    python tools/simulator.py
W drugim:
    python main.py --ip 127.0.0.1

Symulator nasluchuje heartbeatu 'A' na porcie 33739 i wysyla zaszyfrowane
pakiety na port nadawcy (33740), symulujac krotki wyscig: paliwo maleje,
okrazenia rosna, czasy okrazen sie poprawiaja.
"""

from __future__ import annotations

import argparse
import os
import socket
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from gt7_engineer.telemetry.encoder import build_packet, encrypt_packet  # noqa: E402


def run(host: str = "0.0.0.0", listen_port: int = 33739, hz: int = 60) -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((host, listen_port))
    sock.settimeout(1.0)
    print(f"[SIM] Symulator GT7 nasluchuje heartbeatu na {host}:{listen_port}")
    print("[SIM] Uruchom w drugim terminalu: python main.py --ip 127.0.0.1")

    client = None
    # Parametry symulowanego wyscigu
    total_laps = 5
    fuel_capacity = 60.0
    fuel = fuel_capacity
    fuel_per_lap = 11.0          # spali sie okolo 5.5 okrazenia -> wymusza ostrzezenia
    lap = 0
    lap_start_time = time.monotonic()
    base_laptime = 92.0          # sekundy
    best_ms = -1
    last_ms = -1
    position = 4
    packet_id = 0
    started = False

    dt = 1.0 / hz
    while True:
        # Odbierz heartbeat (nieblokujaco-ish).
        try:
            data, addr = sock.recvfrom(64)
            if data[:1] == b"A":
                client = (addr[0], 33740)
                if not started:
                    print(f"[SIM] Heartbeat od {addr[0]} - start transmisji.")
                    started = True
                    lap = 1
                    lap_start_time = time.monotonic()
        except socket.timeout:
            pass

        if client is None:
            continue

        now = time.monotonic()
        elapsed = now - lap_start_time

        # Zakonczenie okrazenia.
        target = base_laptime - (lap * 0.4)   # z kazdym okrazeniem nieco szybciej
        if elapsed >= target and lap >= 1:
            last_ms = int(target * 1000)
            if best_ms < 0 or last_ms < best_ms:
                best_ms = last_ms
            fuel = max(0.0, fuel - fuel_per_lap)
            if position > 1 and lap % 2 == 0:
                position -= 1     # awansujemy co drugie okrazenie
            lap += 1
            lap_start_time = now
            print(f"[SIM] Okrazenie {lap-1} -> {target:.1f}s, paliwo {fuel:.1f}, P{position}")
            if lap > total_laps:
                print("[SIM] Wyscig zakonczony. Restart za 3s.")
                time.sleep(3)
                fuel = fuel_capacity
                lap = 1
                best_ms = -1
                position = 4

        # Zmienne "na zywo".
        speed = 180.0 + 40.0 * abs(((elapsed * 0.7) % 2) - 1)   # 180-220 km/h pulsujaco
        rpm = 6000 + 1500 * abs(((elapsed) % 2) - 1)
        gear = 4

        plaintext = build_packet(
            packet_id=packet_id,
            current_fuel=fuel,
            fuel_capacity=fuel_capacity,
            speed_mps=speed / 3.6,
            rpm=rpm,
            current_lap=lap,
            total_laps=total_laps,
            best_lap_ms=best_ms,
            last_lap_ms=last_ms,
            position_in_race=position,
            total_cars=8,
            gear=gear,
            throttle=220,
            tyre_temp=(85.0, 86.0, 90.0, 112.0),  # tylna prawa goraca -> komunikat o oponie
            car_code=1234,
            on_track=True,
        )
        packet = encrypt_packet(plaintext, iv=packet_id & 0xFFFFFFFF)
        try:
            sock.sendto(packet, client)
        except OSError:
            pass
        packet_id += 1
        time.sleep(dt)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Symulator telemetrii GT7.")
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=33739)
    ap.add_argument("--hz", type=int, default=60)
    args = ap.parse_args()
    try:
        run(args.host, args.port, args.hz)
    except KeyboardInterrupt:
        print("\n[SIM] Zatrzymano symulator.")

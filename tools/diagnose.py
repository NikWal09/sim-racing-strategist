#!/usr/bin/env python3
"""Diagnostyka polaczenia z telemetria GT7.

Wysyla heartbeat do konsoli i przez 12 s nasluchuje odpowiedzi, raportujac
DOKLADNIE gdzie sie urywa: czy w ogole przychodza pakiety, czy maja wlasciwy
rozmiar i czy daja sie odszyfrowac.

Uzycie:
    python tools/diagnose.py                 # IP z config.yaml
    python tools/diagnose.py --ip 192.168.1.14
"""

from __future__ import annotations

import argparse
import os
import socket
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from gt7_engineer.config import Config  # noqa: E402
from gt7_engineer.telemetry.decoder import PACKET_SIZE, decrypt_packet, parse_packet  # noqa: E402

HEARTBEAT = b"A"


def local_ips() -> list[str]:
    ips = set()
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None):
            ip = info[4][0]
            if "." in ip:  # tylko IPv4
                ips.add(ip)
    except Exception:
        pass
    # Najpewniejszy sposob na "wychodzace" IP:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ips.add(s.getsockname()[0])
        s.close()
    except Exception:
        pass
    return sorted(ips)


def run(ps_ip: str, send_port: int, recv_port: int, seconds: int = 12) -> int:
    print("=" * 64)
    print("  DIAGNOSTYKA TELEMETRII GT7")
    print("=" * 64)
    print(f"  IP konsoli (z configu/--ip): {ps_ip}")
    print(f"  Porty: heartbeat -> {send_port}, nasluch <- {recv_port}")
    pc_ips = local_ips()
    print(f"  IP tego PC w sieci: {', '.join(pc_ips) or 'nie wykryto'}")
    if pc_ips and ps_ip in pc_ips:
        print("  !! UWAGA: podane IP to adres TEGO PC, a nie konsoli.")
        print("     W config.yaml musi byc IP PlayStation (PS: Ustawienia -> Siec ->")
        print("     Stan polaczenia -> Adres IP), bo to konsola wysyla telemetrie.")
    # Czy PC i konsola sa w tej samej podsieci /24?
    if pc_ips:
        ps_net = ".".join(ps_ip.split(".")[:3])
        same = any(ip.rsplit(".", 1)[0] == ps_net for ip in pc_ips)
        if not same:
            print(f"  !! UWAGA: PC ({pc_ips}) i konsola ({ps_ip}) wygladaja na rozne")
            print("     podsieci. Upewnij sie, ze sa w tej samej sieci LAN.")
    print("-" * 64)

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(("0.0.0.0", recv_port))
        sock.settimeout(1.0)
    except OSError as e:
        print(f"BLAD: nie moge zajac portu {recv_port}: {e}")
        print("  -> Inny program (albo druga instancja) juz go uzywa? Zamknij i sprobuj.")
        return 1

    print(f"Wysylam heartbeat ('A') do {ps_ip}:{send_port} i nasluchuje {seconds} s...")
    print("(Wejdz w GT7 w tryb jazdy - wyscig albo time trial.)\n")

    received = 0
    good = 0
    bad_size = 0
    bad_decrypt = 0
    first_sender = None
    last_hb = 0.0
    t_end = time.monotonic() + seconds

    while time.monotonic() < t_end:
        now = time.monotonic()
        if now - last_hb > 1.0:        # heartbeat co sekunde
            try:
                sock.sendto(HEARTBEAT, (ps_ip, send_port))
            except OSError as e:
                print(f"BLAD wysylania heartbeatu: {e}")
                return 1
            last_hb = now
        try:
            data, addr = sock.recvfrom(4096)
        except socket.timeout:
            continue
        received += 1
        if first_sender is None:
            first_sender = addr
            print(f"  + Pierwszy pakiet od {addr[0]}:{addr[1]} ({len(data)} B)")
        if len(data) < PACKET_SIZE:
            bad_size += 1
            continue
        dec = decrypt_packet(data)
        if dec is None:
            bad_decrypt += 1
            continue
        good += 1
        if good == 1:
            p = parse_packet(dec)
            print("  + Pakiet ODSZYFROWANY poprawnie. Przyklad danych:")
            print(f"      okrazenie {p.current_lap}/{p.total_laps}, "
                  f"predkosc {p.speed_kph:.0f} km/h, bieg {p.gear}, "
                  f"paliwo {p.current_fuel:.1f}/{p.fuel_capacity:.0f}")

    print("\n" + "-" * 64)
    print(f"Pakiety odebrane:        {received}")
    print(f"  - poprawnie odczytane: {good}")
    print(f"  - zly rozmiar:         {bad_size}")
    print(f"  - blad deszyfrowania:  {bad_decrypt}")
    print("-" * 64)

    if good > 0:
        print("WYNIK: Polaczenie dziala. Mozesz uruchamiac main.py.")
        return 0
    if received == 0:
        print("WYNIK: ZERO pakietow. To problem sieciowy, nie kodu. Sprawdz:")
        print("  1. Czy IP w config.yaml to NA PEWNO IP konsoli (nie PC).")
        print("  2. Firewall Windows: pozwol Pythonowi na ruch przychodzacy UDP")
        print(f"     na porcie {recv_port} (lub na czas testu wylacz firewall).")
        print("  3. PC i konsola w tej samej sieci, bez izolacji klientow (AP isolation)")
        print("     na routerze/WiFi. Najlepiej PC po kablu w tej samej podsieci.")
        print("  4. GT7 musi byc w trybie jazdy (nie w menu/garazu).")
        return 2
    if bad_decrypt > 0 and good == 0:
        print("WYNIK: Pakiety przychodza, ale sie nie deszyfruja.")
        print("  -> To moga byc pakiety w innym formacie/wersji. Daj znac - dostroimy dekoder.")
        return 3
    print("WYNIK: Pakiety przychodza, ale maja niespodziewany rozmiar.")
    return 4


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Diagnostyka telemetrii GT7.")
    ap.add_argument("--ip", default=None, help="IP konsoli (nadpisuje config.yaml)")
    ap.add_argument("--config", default="config.yaml")
    ap.add_argument("--seconds", type=int, default=12)
    args = ap.parse_args()

    cfg = Config.load(args.config)
    ip = args.ip or cfg.telemetry.playstation_ip
    try:
        sys.exit(run(ip, cfg.telemetry.send_port, cfg.telemetry.receive_port, args.seconds))
    except KeyboardInterrupt:
        print("\nPrzerwano.")

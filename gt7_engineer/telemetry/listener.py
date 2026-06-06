"""Listener UDP telemetrii GT7 z obsluga heartbeatu.

GT7 wysyla telemetrie dopiero po otrzymaniu pojedynczego bajtu 'A' na porcie
33739. Konsola tnie strumien po okolo 100 pakietach, wiec heartbeat trzeba
okresowo ponawiac.
"""

from __future__ import annotations

import socket
from collections.abc import Iterator

from .decoder import FORMATS, decrypt_packet, parse_packet
from .packet import GT7Packet


class GT7Listener:
    def __init__(
        self,
        playstation_ip: str,
        send_port: int = 33739,
        receive_port: int = 33740,
        heartbeat_every: int = 100,
        timeout: float = 5.0,
        packet_format: str = "A",
    ) -> None:
        self.playstation_ip = playstation_ip
        self.send_port = send_port
        self.receive_port = receive_port
        self.heartbeat_every = max(1, heartbeat_every)
        self.timeout = timeout
        # Format telemetrii decyduje o bajcie heartbeatu i rozmiarze pakietu.
        self.packet_format = packet_format if packet_format in FORMATS else "A"
        spec = FORMATS[self.packet_format]
        self.heartbeat: bytes = spec["heartbeat"]
        self.packet_size: int = spec["size"]
        self._sock: socket.socket | None = None
        self._since_heartbeat = 0

    def __enter__(self) -> "GT7Listener":
        self.open()
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    def open(self) -> None:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(("0.0.0.0", self.receive_port))
        sock.settimeout(self.timeout)
        self._sock = sock
        self._send_heartbeat()

    def close(self) -> None:
        if self._sock is not None:
            self._sock.close()
            self._sock = None

    def _send_heartbeat(self) -> None:
        assert self._sock is not None
        self._sock.sendto(self.heartbeat, (self.playstation_ip, self.send_port))
        self._since_heartbeat = 0

    def receive(self) -> GT7Packet | None:
        """Odbiera i parsuje jeden pakiet. Zwraca None przy timeoucie/blednym pakiecie."""
        if self._sock is None:
            raise RuntimeError("Listener nie jest otwarty - uzyj open() lub kontekstu 'with'.")

        if self._since_heartbeat >= self.heartbeat_every:
            self._send_heartbeat()

        try:
            data, _addr = self._sock.recvfrom(4096)
        except socket.timeout:
            # Brak danych - ponow heartbeat, moze konsola przestala wysylac.
            self._send_heartbeat()
            return None

        self._since_heartbeat += 1

        if len(data) < self.packet_size:
            return None
        decrypted = decrypt_packet(data, self.packet_format)
        if decrypted is None:
            return None
        return parse_packet(decrypted, self.packet_format)

    def stream(self) -> Iterator[GT7Packet]:
        """Nieskonczony generator pakietow (pomija None)."""
        while True:
            packet = self.receive()
            if packet is not None:
                yield packet

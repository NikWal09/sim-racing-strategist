/// Listener UDP telemetrii GT7 z obsluga heartbeatu.
///
/// Port z `gt7_engineer/telemetry/listener.py`. GT7 wysyla telemetrie dopiero po
/// otrzymaniu pojedynczego bajtu formatu ('A'/'B'/'~') na porcie 33739. Konsola
/// tnie strumien po okolo 100 pakietach, wiec heartbeat trzeba okresowo ponawiac.
///
/// Wystawia strumien [packets] z gotowymi obiektami [Gt7Packet]. Dziala na
/// Androidzie i iOS (dart:io RawDatagramSocket). Telefon musi byc w tej samej
/// sieci Wi-Fi co PlayStation.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'decoder.dart';
import 'gt7_packet.dart';
import 'telemetry_source.dart';

class Gt7Listener implements TelemetrySource {
  Gt7Listener({
    required this.playstationIp,
    this.sendPort = 33739,
    this.receivePort = 33740,
    this.heartbeatEvery = 100,
    this.packetFormat = 'A',
  }) : _format = formats.containsKey(packetFormat) ? packetFormat : 'A';

  final String playstationIp;
  final int sendPort;
  final int receivePort;
  final int heartbeatEvery;
  final String packetFormat;

  final String _format;
  RawDatagramSocket? _socket;
  int _sinceHeartbeat = 0;

  final StreamController<Gt7Packet> _controller =
      StreamController<Gt7Packet>.broadcast();

  /// Strumien sparsowanych pakietow (bledne/za krotkie sa pomijane).
  @override
  Stream<Gt7Packet> get packets => _controller.stream;

  @override
  bool get isRunning => _socket != null;

  @override
  String get label => 'PS5 $playstationIp (format $_format)';

  /// Otwiera gniazdo, wysyla pierwszy heartbeat i zaczyna nasluch.
  @override
  Future<void> start() async {
    if (_socket != null) return;
    final spec = formats[_format]!;

    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      receivePort,
      reuseAddress: true,
    );
    _socket = socket;
    _sendHeartbeat();

    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = socket.receive();
      if (dg == null) return;
      final data = Uint8List.fromList(dg.data);
      if (data.length < spec.size) return;

      _sinceHeartbeat++;
      if (_sinceHeartbeat >= heartbeatEvery) _sendHeartbeat();

      final decrypted = decryptPacket(data, _format);
      if (decrypted == null) return;
      _controller.add(parsePacket(decrypted, _format));
    });
  }

  void _sendHeartbeat() {
    final socket = _socket;
    if (socket == null) return;
    final spec = formats[_format]!;
    socket.send(
      Uint8List.fromList([spec.heartbeat]),
      InternetAddress(playstationIp),
      sendPort,
    );
    _sinceHeartbeat = 0;
  }

  /// Zamyka gniazdo i strumien.
  @override
  Future<void> stop() async {
    _socket?.close();
    _socket = null;
    await _controller.close();
  }
}

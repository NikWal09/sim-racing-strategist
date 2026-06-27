/// Automatyczne wykrywanie konsoli z GT7 w sieci lokalnej.
///
/// GT7 nie rozgłasza telemetrii — konsola odpowiada dopiero po otrzymaniu
/// heartbeatu na port 33739 i streamuje zaszyfrowane pakiety na port 33740
/// nadawcy. Dlatego wykrywanie jest AKTYWNE: wysyłamy heartbeat na każdy adres
/// w podsieci /24 i czekamy na pierwszą odpowiedź, którą da się odszyfrować
/// (reużywamy [decryptPacket]) — to gwarantuje brak fałszywych trafień, bo żaden
/// inny serwis nie odpowie poprawnym pakietem GT7.
///
/// Wymaga: telefon i konsola w tej samej sieci Wi-Fi, GT7 uruchomione i „na
/// torze" (jazda/replay). iOS: zgoda na dostęp do sieci lokalnej (Info.plist).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'decoder.dart';

class Gt7Discovery {
  /// Skanuje lokalną podsieć (/24). Zwraca IP konsoli albo null
  /// (brak sieci / izolacja AP / GT7 nie streamuje / nie znaleziono w czasie).
  ///
  /// [preferIp] (np. ostatnio zapisane) jest sondowane najpierw — jeśli konsola
  /// nadal tam jest, odpowie niemal natychmiast.
  static Future<String?> scan({
    String packetFormat = 'A',
    String? preferIp,
    Duration timeout = const Duration(seconds: 3),
    int sendPort = 33739,
    int receivePort = 33740,
  }) async {
    final spec = formats[packetFormat] ?? formats['A']!;

    final localIp = await _localIPv4();
    if (localIp == null) return null;
    final prefix = localIp.substring(0, localIp.lastIndexOf('.') + 1);

    final RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        receivePort,
        reuseAddress: true,
      );
    } catch (_) {
      return null; // port zajęty (np. już połączeni) albo brak uprawnień
    }

    final completer = Completer<String?>();
    Timer? deadline;

    void finish(String? ip) {
      if (completer.isCompleted) return;
      deadline?.cancel();
      try {
        socket.close();
      } catch (_) {}
      completer.complete(ip);
    }

    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = socket.receive();
      if (dg == null) return;
      final data = Uint8List.fromList(dg.data);
      // Walidacja „za darmo": poprawny pakiet GT7 = na pewno konsola.
      if (decryptPacket(data, packetFormat) != null) {
        finish(dg.address.address);
      }
    });

    void burst() {
      final hb = Uint8List.fromList([spec.heartbeat]);
      void ping(String ip) {
        try {
          socket.send(hb, InternetAddress(ip), sendPort);
        } catch (_) {}
      }

      if (preferIp != null && preferIp.startsWith(prefix)) ping(preferIp);
      for (var h = 1; h <= 254; h++) {
        ping('$prefix$h');
      }
    }

    burst();
    // Druga seria w trakcie okna — konsola mogła akurat ciąć strumień (~100 pkt).
    Timer(Duration(milliseconds: (timeout.inMilliseconds / 3).round()), () {
      if (!completer.isCompleted) burst();
    });
    deadline = Timer(timeout, () => finish(null));

    return completer.future;
  }

  /// Pierwszy prywatny adres IPv4 (najpewniej Wi-Fi LAN); null gdy brak.
  static Future<String?> _localIPv4() async {
    try {
      final ifaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      String? fallback;
      for (final iface in ifaces) {
        for (final a in iface.addresses) {
          final ip = a.address;
          if (ip.startsWith('169.254.')) continue; // link-local
          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              _is172Private(ip)) {
            return ip;
          }
          fallback ??= ip;
        }
      }
      return fallback;
    } catch (_) {
      return null;
    }
  }

  static bool _is172Private(String ip) {
    if (!ip.startsWith('172.')) return false;
    final parts = ip.split('.');
    if (parts.length < 2) return false;
    final second = int.tryParse(parts[1]) ?? 0;
    return second >= 16 && second <= 31;
  }
}

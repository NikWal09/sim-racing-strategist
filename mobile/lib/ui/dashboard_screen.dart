/// Dashboard na zywo — Etap 2.
///
/// Subskrybuje dowolne [TelemetrySource] (PS5 albo symulator) i pokazuje zegary:
/// pasek RPM, bieg, predkosc, paliwo, okrazenie/pozycje, czasy okrazen, gaz i
/// hamulec oraz temperatury opon. Ekran trzyma sie w pionie i poziomie.
library;

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../telemetry/gt7_packet.dart';
import '../telemetry/telemetry_source.dart';
import 'gauges.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.source});

  final TelemetrySource source;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Gt7Packet? _p;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    widget.source.packets.listen((p) {
      if (mounted) setState(() => _p = p);
    });
    if (!widget.source.isRunning) widget.source.start();
  }

  @override
  void dispose() {
    widget.source.stop();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0C),
      appBar: AppBar(
        title: Text(widget.source.label),
        backgroundColor: const Color(0xFF161616),
      ),
      body: p == null
          ? const Center(
              child: Text('Czekam na dane...',
                  style: TextStyle(color: Colors.white54)))
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RpmBar(
                      rpm: p.rpm,
                      maxRpm: p.rpmAlertMax > 0 ? p.rpmAlertMax + 600 : 8000,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 3, child: _leftColumn(p)),
                          Expanded(flex: 4, child: _centerColumn(p)),
                          Expanded(flex: 3, child: _rightColumn(p)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  // --- Lewa kolumna: opony + paliwo ---

  Widget _leftColumn(Gt7Packet p) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _tyres(p),
        _tile('PALIWO', '${p.fuelPct.toStringAsFixed(1)} %',
            sub: '${p.currentFuel.toStringAsFixed(1)} / ${p.fuelCapacity.toStringAsFixed(0)} l'),
      ],
    );
  }

  Widget _tyres(Gt7Packet p) {
    Widget cell(int i) {
      final t = p.tyreTemp[i];
      return Container(
        margin: const EdgeInsets.all(3),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: _tyreColor(t).withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text('${t.toStringAsFixed(0)}°',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.black)),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('OPONY',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 4),
        Row(children: [Expanded(child: cell(0)), Expanded(child: cell(1))]),
        Row(children: [Expanded(child: cell(2)), Expanded(child: cell(3))]),
      ],
    );
  }

  // --- Srodek: bieg + predkosc ---

  Widget _centerColumn(Gt7Packet p) {
    final gear = p.gear == 0 ? 'R' : (p.gear == 15 ? 'N' : '${p.gear}');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(gear,
            style: const TextStyle(
                fontSize: 120,
                height: 1.0,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        Text('${p.speedKph.toStringAsFixed(0)}',
            style: const TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.bold,
                color: Colors.cyanAccent)),
        const Text('km/h', style: TextStyle(color: Colors.white54)),
      ],
    );
  }

  // --- Prawa kolumna: okrazenie, czasy, pedaly ---

  Widget _rightColumn(Gt7Packet p) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tile('OKRAZENIE', '${p.currentLap} / ${p.totalLaps}',
            sub: 'pozycja ${p.positionInRace} / ${p.totalCars}'),
        _tile('OSTATNIE', Gt7Packet.formatLaptime(p.lastLapMs)),
        _tile('NAJLEPSZE', Gt7Packet.formatLaptime(p.bestLapMs)),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            PedalBar(value: p.throttle / 255, color: Colors.greenAccent, label: 'GAZ'),
            PedalBar(value: p.brake / 255, color: Colors.redAccent, label: 'HAM.'),
          ],
        ),
      ],
    );
  }

  // --- Pomocnicze ---

  Widget _tile(String label, String value, {String? sub}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          if (sub != null)
            Text(sub, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }

  /// Kolor opony wg temperatury: zimno (niebieski) -> optymalnie (zielony) ->
  /// goraco (zolty/czerwony).
  Color _tyreColor(double t) {
    if (t < 70) return Colors.lightBlueAccent;
    if (t < 90) return Colors.greenAccent;
    if (t < 100) return Colors.amber;
    return Colors.redAccent;
  }
}

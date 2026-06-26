/// Test okrążenia referencyjnego: wczytanie nagrania, metadane, czyszczenie.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gt7_engineer_mobile/engineer/delta_tracker.dart';
import 'package:gt7_engineer_mobile/engineer/telemetry_recorder.dart';

Map<String, dynamic> _fakeLap() {
  // Pętla (okrąg) jako ślad referencji; t rośnie równomiernie.
  const n = 200;
  final samples = <List<num>>[];
  for (var i = 0; i < n; i++) {
    final a = 2 * pi * i / n;
    final row = List<num>.filled(recorderChannels.length, 0);
    row[0] = i * 0.2; // t
    row[1] = 200 * cos(a); // x
    row[2] = 0; // y
    row[3] = 200 * sin(a); // z
    samples.add(row);
  }
  return {
    'channels': recorderChannels,
    'samples': samples,
    'lap_ms': 44000,
    'car_code': 3604,
    'car_name': 'Auto 3604',
    'lap_time': '0:44.000',
    'track_key': 'L1250-W400-H400',
  };
}

void main() {
  test('wczytanie referencji i metadane', () {
    final rd = ReferenceDelta(sectors: 3);
    expect(rd.loaded, isFalse);

    final info = rd.loadFromData(_fakeLap());
    expect(rd.loaded, isTrue);
    expect(info.lapMs, 44000);
    expect(info.trackKey, 'L1250-W400-H400');
    expect(info.carName, 'Auto 3604');
  });

  test('clear usuwa referencję', () {
    final rd = ReferenceDelta(sectors: 3);
    rd.loadFromData(_fakeLap());
    expect(rd.loaded, isTrue);
    rd.clear();
    expect(rd.loaded, isFalse);
  });

  test('niepoprawne nagranie rzuca', () {
    final rd = ReferenceDelta();
    expect(() => rd.loadFromData({'channels': [], 'samples': [], 'lap_ms': 0}),
        throwsArgumentError);
  });
}

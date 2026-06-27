/// Race engineer — przekształca strumień pakietów w komunikaty dla kierowcy.
/// Port `gt7_engineer/engineer/analyzer.py` (bez okrążenia referencyjnego —
/// referencja dojdzie w Etapie 6). Logika okrążeń, paliwa, pozycji, opon,
/// zakrętów i delty jest przeniesiona 1:1.
library;

import 'dart:math' as math;

import '../messages/messages_pl.dart';
import '../speech/speaker.dart';
import '../telemetry/gt7_packet.dart';
import 'corner_tracker.dart';
import 'stint_calculator.dart';
import 'delta_tracker.dart';
import 'engineer_config.dart';
import 'session_state.dart';

class Announcement {
  Announcement(this.text,
      {this.priority = Priority.normal, this.key, this.minGap});
  final String text;
  final Priority priority;
  final String? key;
  final double? minGap;
}

class RaceEngineer {
  RaceEngineer(this.cfg, {double Function()? clock})
      : _clock = clock ?? (() => DateTime.now().microsecondsSinceEpoch / 1e6) {
    state.fuelWindow = math.max(1, cfg.fuelAvgWindow);
    delta = DeltaTracker(cfg.deltaMinSeconds);
    refDelta = ReferenceDelta(
        minDeltaS: cfg.deltaMinSeconds, sectors: cfg.refSectors);
  }

  final EngineerConfig cfg;
  final double Function() _clock;
  final PolishMessages M = PolishMessages();
  final SessionState state = SessionState();
  final CornerTracker corners = CornerTracker();
  late DeltaTracker delta;
  late ReferenceDelta refDelta;

  /// Ustawia nagrane okrążenie jako referencję (delta REF + sektory).
  ReferenceInfo setReference(Map<String, dynamic> data) {
    final info = refDelta.loadFromData(data);
    refDelta.startLap(_clock());
    return info;
  }

  void clearReference() => refDelta.clear();

  static const double defaultMinGap = 2.0;
  static const double fuelRefillEps = 0.05;
  static const double pitReturnMaxKph = 5.0;

  int _lapsSinceFuelReport = 0;
  final Map<String, double> _lastEmit = {};
  double? _lastFuel;
  bool _fuelLapInvalid = false;
  final List<String> _fuelDebug = [];

  List<String> popFuelDebug() {
    final lines = List<String>.from(_fuelDebug);
    _fuelDebug.clear();
    return lines;
  }

  List<Announcement> update(Gt7Packet p) => _throttle(_update(p));

  List<Announcement> _throttle(List<Announcement> anns) {
    final now = _clock();
    final kept = <Announcement>[];
    for (final a in anns) {
      if (a.key == null) {
        kept.add(a);
        continue;
      }
      final gap = a.minGap ?? defaultMinGap;
      final last = _lastEmit[a.key!] ?? double.negativeInfinity;
      if (now - last >= gap) {
        _lastEmit[a.key!] = now;
        kept.add(a);
      }
    }
    return kept;
  }

  List<Announcement> _update(Gt7Packet p) {
    final out = <Announcement>[];
    if (p.paused || p.loading) return out;

    if (state.carCode == null) {
      state.carCode = p.carCode;
    } else if (p.carCode != state.carCode) {
      state.carCode = p.carCode;
      state.reset();
      corners.reset();
      delta.reset();
      refDelta.reset(); // referencja z pliku przeżywa zmianę auta
      state.connected = false;
      _lastFuel = null;
      _fuelLapInvalid = false;
    }

    if (!p.onTrack) {
      state.connected = false;
      return out;
    }

    if (!state.connected) {
      state.connected = true;
      state.currentLap = p.currentLap;
      state.lastPosition = p.positionInRace;
      state.bestLapMs = p.bestLapMs;
      corners.reset();
      delta.startLap(_clock());
      refDelta.startLap(_clock());
      if (p.fuelCapacity > 0) state.fuelAtLapStart = p.currentFuel;
      _fuelLapInvalid = true;
      out.add(Announcement(M.connected(),
          priority: Priority.normal, key: 'connected', minGap: 10));
      return out;
    }

    final now = _clock();

    // Powrót do pit przez menu pauzy: skok paliwa przy ~0 km/h.
    if (_lastFuel != null &&
        p.fuelCapacity > 0 &&
        p.currentFuel > _lastFuel! + fuelRefillEps &&
        p.speedKph <= pitReturnMaxKph) {
      delta.startLap(now);
      refDelta.startLap(now);
      state.fuelAtLapStart = p.currentFuel;
      _fuelLapInvalid = true;
      _fuelDebug.add('[PALIWO] Tankowanie wykryte (paliwo '
          '${p.currentFuel.toStringAsFixed(2)}) - próbka zużycia pominięta.');
    }
    _lastFuel = p.currentFuel;

    corners.update(p.position, p.velocity, p.speedMps, p.wheelRotationRad,
        p.tyreTemp, now);
    delta.update(p.position, p.speedMps, now, lapNo: p.currentLap);
    if (refDelta.loaded) {
      refDelta.update(p.position, p.speedMps, now, lapNo: p.currentLap);
    }

    out.addAll(_checkLap(p));
    out.addAll(_checkPosition(p));
    out.addAll(_checkTyres(p));
    out.addAll(_checkCorners(p));
    out.addAll(_checkDelta(p));
    out.addAll(_checkRefSectors(p));
    return out;
  }

  List<Announcement> _checkLap(Gt7Packet p) {
    final out = <Announcement>[];

    if (p.currentLap < state.currentLap) {
      state.currentLap = p.currentLap;
      delta.startLap(_clock());
      refDelta.startLap(_clock());
      _fuelLapInvalid = true;
      return out;
    }
    if (p.currentLap <= state.currentLap) return out;

    final completedTimedLap = state.currentLap >= 1;
    state.currentLap = p.currentLap;
    corners.onLapComplete();
    delta.onLapComplete(p.lastLapMs, _clock(),
        speedMps: p.speedMps, lapNo: p.currentLap);
    refDelta.onLapComplete(p.lastLapMs, _clock(),
        speedMps: p.speedMps, lapNo: p.currentLap);

    if (cfg.announceLapTimes && p.totalLaps > 0 && p.currentLap == p.totalLaps) {
      out.add(Announcement(M.lastLap(),
          priority: Priority.high, key: 'last_lap', minGap: 30));
    }

    if (!completedTimedLap) {
      if (p.fuelCapacity > 0) state.fuelAtLapStart = p.currentFuel;
      return out;
    }

    final improvedBest = p.bestLapMs > 0 &&
        (state.bestLapMs <= 0 || p.bestLapMs < state.bestLapMs);
    if (improvedBest) {
      state.bestLapMs = p.bestLapMs;
      if (cfg.announceBestLap) {
        out.add(Announcement(M.bestLap(p.bestLapMs),
            priority: Priority.high, key: 'lap_time'));
      } else if (cfg.announceLapTimes && p.lastLapMs > 0) {
        out.add(Announcement(M.lapTime(p.lastLapMs),
            priority: Priority.normal, key: 'lap_time'));
      }
    } else if (cfg.announceLapTimes && p.lastLapMs > 0) {
      out.add(Announcement(M.lapTime(p.lastLapMs),
          priority: Priority.normal, key: 'lap_time'));
    }

    out.addAll(_checkFuel(p));
    return out;
  }

  List<Announcement> _checkFuel(Gt7Packet p) {
    final out = <Announcement>[];
    if (p.fuelCapacity <= 0) return out;

    if (state.fuelAtLapStart != null && !_fuelLapInvalid) {
      final used = state.fuelAtLapStart! - p.currentFuel;
      if (used > 0) state.addFuelSample(used);
    }
    _fuelLapInvalid = false;
    state.fuelAtLapStart = p.currentFuel;

    final avg = state.avgFuelPerLap;
    final lapsLeft = state.lapsRemainingOnFuel(p.currentFuel);
    if (avg == null ||
        lapsLeft == null ||
        state.currentLap < cfg.minLapsForFuelCalc + 1) {
      return out;
    }

    _lapsSinceFuelReport += 1;
    final cands = <Announcement>[];

    if (lapsLeft <= cfg.fuelCriticalLaps) {
      cands.add(Announcement(M.fuelCritical(lapsLeft),
          priority: Priority.critical, key: 'fuel', minGap: 8));
    } else if (lapsLeft <= cfg.fuelWarningLaps) {
      cands.add(Announcement(M.fuelWarning(lapsLeft),
          priority: Priority.high, key: 'fuel', minGap: 15));
    } else if (lapsLeft <= cfg.pitWindowLaps + cfg.fuelWarningLaps) {
      if (_lapsSinceFuelReport >= 2) {
        _lapsSinceFuelReport = 0;
        cands.add(Announcement(M.fuelLapsLeft(lapsLeft),
            priority: Priority.low, key: 'fuel'));
      }
    } else {
      if (_lapsSinceFuelReport >= 3) {
        _lapsSinceFuelReport = 0;
        cands.add(Announcement(M.fuelLapsLeft(lapsLeft),
            priority: Priority.low, key: 'fuel'));
      }
    }

    if (cfg.announceFuelStrategy && p.totalLaps > 0) {
      cands.addAll(_fuelStrategy(p, avg, lapsLeft));
    }

    final limit = math.max(0, cfg.fuelMaxMessagesPerLap);
    cands.sort((a, b) => a.priority.index - b.priority.index);
    out.addAll(cands.take(limit));
    return out;
  }

  List<Announcement> _fuelStrategy(Gt7Packet p, double avg, double lapsLeft) {
    final out = <Announcement>[];
    final raceLapsLeft = p.totalLaps - p.currentLap + 1;
    if (raceLapsLeft <= 0 || avg <= 0) return out;

    // Rdzeń obliczeń paliwa wydzielony do StintCalculator (wspólny z ekranem
    // „Stint"). Tu zostaje tylko kontekst sesji (numer okrążenia) i komunikaty.
    final plan = StintCalculator.fuel(
      FuelInput(
        tankL: p.fuelCapacity,
        currentL: p.currentFuel,
        perLapL: avg,
        lapsRemaining: raceLapsLeft,
      ),
      marginLaps: cfg.fuelTargetMarginLaps,
    );

    if (!plan.finishesWithoutPit) {
      var lastFullLap = p.currentLap + lapsLeft.toInt() - 1;
      if (lastFullLap < p.currentLap) lastFullLap = p.currentLap;

      if (plan.savePerLapL > 0.01) {
        out.add(Announcement(M.fuelSavePerLap(plan.savePerLapL),
            priority: Priority.high, key: 'fuel_finish', minGap: 20));
      }
      if (lastFullLap < p.totalLaps) {
        out.add(Announcement(M.fuelRunsOut(lastFullLap),
            priority: Priority.normal, key: 'fuel_runs_out', minGap: 25));
      }
      if (plan.refuelPct > 1.0) {
        out.add(Announcement(M.fuelRefuelPct(plan.refuelPct),
            priority: Priority.low, key: 'fuel_refuel', minGap: 40));
      }
    } else if (cfg.announceFuelOkToFinish) {
      if (plan.spareLaps > 0) {
        out.add(Announcement(M.fuelOkToFinish(plan.spareLaps),
            priority: Priority.low, key: 'fuel_finish', minGap: 60));
      }
    }
    return out;
  }

  List<Announcement> _checkPosition(Gt7Packet p) {
    final out = <Announcement>[];
    if (!cfg.announcePositionChanges || p.totalCars <= 0) return out;
    if (p.positionInRace <= 0) return out;
    final prev = state.lastPosition;
    if (prev <= 0) {
      state.lastPosition = p.positionInRace;
      return out;
    }
    if (p.positionInRace < prev) {
      out.add(Announcement(M.gainedPosition(p.positionInRace),
          priority: Priority.normal, key: 'position', minGap: 3));
    } else if (p.positionInRace > prev) {
      out.add(Announcement(M.lostPosition(p.positionInRace),
          priority: Priority.normal, key: 'position', minGap: 3));
    }
    state.lastPosition = p.positionInRace;
    return out;
  }

  List<Announcement> _checkTyres(Gt7Packet p) {
    final out = <Announcement>[];
    final threshold = cfg.tyreTempWarning;
    var hottest = 0;
    for (var i = 1; i < 4; i++) {
      if (p.tyreTemp[i] > p.tyreTemp[hottest]) hottest = i;
    }
    if (p.tyreTemp[hottest] >= threshold) {
      out.add(Announcement(
          M.tyreHot(PolishMessages.corners[hottest], p.tyreTemp[hottest]),
          priority: Priority.normal,
          key: 'tyre_hot',
          minGap: 25));
    }
    return out;
  }

  List<Announcement> _checkDelta(Gt7Packet p) {
    final out = <Announcement>[];
    if (!cfg.announceDelta) return out;
    final now = _clock();
    delta.updateStraight(p.throttle, p.wheelRotationRad, p.speedKph, now);
    if (!delta.canAnnounceStraight(now)) return out;
    final d = delta.currentDelta();
    if (d == null || d.abs() < cfg.deltaMinSeconds) return out;
    delta.markAnnounced();
    if (d < 0) {
      out.add(Announcement(M.deltaAhead(-d),
          priority: Priority.low, key: 'delta', minGap: 4));
    } else {
      out.add(Announcement(M.deltaBehind(d),
          priority: Priority.low, key: 'delta', minGap: 4));
    }
    return out;
  }

  List<Announcement> _checkRefSectors(Gt7Packet p) {
    final out = <Announcement>[];
    if (!refDelta.loaded) return out;
    final res = refDelta.popSectorResult();
    if (res == null || !cfg.announceRefSectors) return out;
    final (sectorNo, diff) = res;
    if (diff.abs() < cfg.refSectorMinSeconds) return out;
    if (diff > 0) {
      out.add(Announcement(M.refSectorLoss(sectorNo, diff),
          priority: Priority.low, key: 'ref_sector', minGap: 5));
    } else {
      out.add(Announcement(M.refSectorGain(sectorNo, -diff),
          priority: Priority.low, key: 'ref_sector', minGap: 5));
    }
    return out;
  }

  List<Announcement> _checkCorners(Gt7Packet p) {
    final out = <Announcement>[];
    if (!cfg.announceCornerTyres) return out;
    final warn = cfg.cornerTempWarning;

    final jf = corners.popJustFinished();
    if (jf != null) {
      final (cornerNo, tyreIdx, temp) = jf;
      if (temp >= warn) {
        out.add(Announcement(
            M.tyreCornerHot(cornerNo, PolishMessages.corners[tyreIdx], temp),
            priority: Priority.low,
            key: 'corner_hot',
            minGap: 8));
      }
    }

    final res = corners.hottestCorner();
    if (res != null) {
      final (cornerNo, tyreIdx, temp) = res;
      if (temp >= warn) {
        out.add(Announcement(
            M.tyreCornerWorst(cornerNo, PolishMessages.corners[tyreIdx], temp),
            priority: Priority.low,
            key: 'corner_worst',
            minGap: 120));
      }
    }
    return out;
  }
}

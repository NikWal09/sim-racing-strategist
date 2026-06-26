/// Wspólny stan aplikacji dzielony przez zakładki.
///
/// Trzyma aktywne źródło telemetrii (PS5 albo symulator), inżyniera (analizę
/// na żywo), mówcę (TTS), ostatni pakiet, deltę, status i log zdarzeń. Zakładki
/// słuchają przez [ListenableBuilder].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'cloud/user_settings_service.dart';
import 'engineer/delta_tracker.dart';
import 'engineer/engineer_config.dart';
import 'engineer/race_engineer.dart';
import 'engineer/recording_store.dart';
import 'engineer/telemetry_recorder.dart';
import 'engineer/track_labels.dart';
import 'messages/messages_pl.dart';
import 'speech/speaker.dart';
import 'telemetry/gt7_packet.dart';
import 'telemetry/listener.dart';
import 'telemetry/simulator.dart';
import 'telemetry/telemetry_source.dart';

class TelemetryController extends ChangeNotifier {
  TelemetrySource? _source;
  Gt7Packet? _last;
  String _status = 'Zatrzymany.';
  final List<String> _log = [];

  final EngineerConfig engineerCfg = EngineerConfig();
  final Speaker speaker = Speaker();
  RaceEngineer _engineer = RaceEngineer(EngineerConfig());
  double? _currentDelta;
  bool voiceEnabled = true;

  // Nazwy torów (przypisania po obrysie śladu).
  final TrackLabelStore trackLabels = TrackLabelStore();

  // Nagrywanie telemetrii (Garage 61).
  final RecordingStore recordings = RecordingStore();
  final RecordingConfig recordingCfg = RecordingConfig();
  TelemetryRecorder _recorder = TelemetryRecorder(RecordingConfig());
  int recordingsRev = 0; // rośnie po zapisaniu okrążenia (do odświeżenia listy)

  // Ustawienia połączenia (synchronizowane do chmury per użytkownik).
  String playstationIp = '192.168.1.100';
  String packetFormat = 'B';

  // Synchronizacja ustawień użytkownika (Firestore).
  final UserSettingsService _userSettings = UserSettingsService();
  String? uid; // ustawiany po zalogowaniu; null = tryb lokalny
  Timer? _saveTimer;

  void setUser(String? id) => uid = id;

  Future<void> loadCloudSettings() async {
    if (uid == null) return;
    final m = await _userSettings.load(uid!);
    if (m != null) applySettings(m);
  }

  /// Zapis ustawień do chmury z opóźnieniem (debounce) - nie zalewa zapisami.
  void scheduleSettingsSave() {
    if (uid == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1200), () {
      _userSettings.save(uid!, exportSettings());
    });
  }

  Map<String, dynamic> exportSettings() => {
        'connection': {'ip': playstationIp, 'format': packetFormat},
        'voice': {'enabled': voiceEnabled, 'rate': speaker.speechRate},
        'engineer': {
          'fuelWarningLaps': engineerCfg.fuelWarningLaps,
          'fuelCriticalLaps': engineerCfg.fuelCriticalLaps,
          'pitWindowLaps': engineerCfg.pitWindowLaps,
          'tyreTempWarning': engineerCfg.tyreTempWarning,
          'announceLapTimes': engineerCfg.announceLapTimes,
          'announcePositionChanges': engineerCfg.announcePositionChanges,
          'announceBestLap': engineerCfg.announceBestLap,
          'announceFuelStrategy': engineerCfg.announceFuelStrategy,
          'announceFuelOkToFinish': engineerCfg.announceFuelOkToFinish,
          'announceCornerTyres': engineerCfg.announceCornerTyres,
          'cornerTempWarning': engineerCfg.cornerTempWarning,
          'announceDelta': engineerCfg.announceDelta,
          'deltaMinSeconds': engineerCfg.deltaMinSeconds,
          'announceRefSectors': engineerCfg.announceRefSectors,
          'refSectors': engineerCfg.refSectors,
          'refSectorMinSeconds': engineerCfg.refSectorMinSeconds,
        },
        'recording': {
          'enabled': recordingCfg.enabled,
          'sampleHz': recordingCfg.sampleHz,
          'minLapSeconds': recordingCfg.minLapSeconds,
        },
      };

  void applySettings(Map<String, dynamic> s) {
    double d(Map m, String k, double dft) => (m[k] as num?)?.toDouble() ?? dft;
    int i(Map m, String k, int dft) => (m[k] as num?)?.toInt() ?? dft;
    bool b(Map m, String k, bool dft) => (m[k] as bool?) ?? dft;

    final conn = s['connection'];
    if (conn is Map) {
      playstationIp = '${conn['ip'] ?? playstationIp}';
      packetFormat = '${conn['format'] ?? packetFormat}';
    }
    final v = s['voice'];
    if (v is Map) {
      voiceEnabled = b(v, 'enabled', voiceEnabled);
      speaker.enabled = voiceEnabled;
      speaker.speechRate = d(v, 'rate', speaker.speechRate);
    }
    final e = s['engineer'];
    if (e is Map) {
      engineerCfg.fuelWarningLaps = d(e, 'fuelWarningLaps', engineerCfg.fuelWarningLaps);
      engineerCfg.fuelCriticalLaps = d(e, 'fuelCriticalLaps', engineerCfg.fuelCriticalLaps);
      engineerCfg.pitWindowLaps = d(e, 'pitWindowLaps', engineerCfg.pitWindowLaps);
      engineerCfg.tyreTempWarning = d(e, 'tyreTempWarning', engineerCfg.tyreTempWarning);
      engineerCfg.announceLapTimes = b(e, 'announceLapTimes', engineerCfg.announceLapTimes);
      engineerCfg.announcePositionChanges = b(e, 'announcePositionChanges', engineerCfg.announcePositionChanges);
      engineerCfg.announceBestLap = b(e, 'announceBestLap', engineerCfg.announceBestLap);
      engineerCfg.announceFuelStrategy = b(e, 'announceFuelStrategy', engineerCfg.announceFuelStrategy);
      engineerCfg.announceFuelOkToFinish = b(e, 'announceFuelOkToFinish', engineerCfg.announceFuelOkToFinish);
      engineerCfg.announceCornerTyres = b(e, 'announceCornerTyres', engineerCfg.announceCornerTyres);
      engineerCfg.cornerTempWarning = d(e, 'cornerTempWarning', engineerCfg.cornerTempWarning);
      engineerCfg.announceDelta = b(e, 'announceDelta', engineerCfg.announceDelta);
      engineerCfg.deltaMinSeconds = d(e, 'deltaMinSeconds', engineerCfg.deltaMinSeconds);
      engineerCfg.announceRefSectors = b(e, 'announceRefSectors', engineerCfg.announceRefSectors);
      engineerCfg.refSectors = i(e, 'refSectors', engineerCfg.refSectors);
      engineerCfg.refSectorMinSeconds = d(e, 'refSectorMinSeconds', engineerCfg.refSectorMinSeconds);
    }
    final rec = s['recording'];
    if (rec is Map) {
      recordingCfg.enabled = b(rec, 'enabled', recordingCfg.enabled);
      recordingCfg.sampleHz = d(rec, 'sampleHz', recordingCfg.sampleHz);
      recordingCfg.minLapSeconds = d(rec, 'minLapSeconds', recordingCfg.minLapSeconds);
    }
    notifyListeners();
  }

  // Okrążenie referencyjne (DELTA REF + sektory).
  Map<String, dynamic>? _refData;
  ReferenceInfo? refInfo;

  Gt7Packet? get last => _last;
  double? get currentDelta => _currentDelta;

  // --- Wyliczenia paliwa (z analizy inżyniera) — dla widgetów dashboardu ---

  /// Średnie zużycie paliwa na okrążenie (krocząca średnia). null = za mało danych.
  double? get avgFuelPerLap => _engineer.state.avgFuelPerLap;

  /// Ile okrążeń zostało na obecnym paliwie. null = brak danych / auto bez paliwa.
  double? get fuelLapsRemaining {
    final p = _last;
    if (p == null || p.fuelCapacity <= 0) return null;
    return _engineer.state.lapsRemainingOnFuel(p.currentFuel);
  }

  /// Zapas paliwa względem mety, wyrażony w okrążeniach (dodatni = wystarczy
  /// z zapasem, ujemny = zabraknie). null gdy nie znamy zużycia lub liczby okrążeń.
  double? get fuelMarginLaps {
    final p = _last;
    final left = fuelLapsRemaining;
    if (p == null || left == null || p.totalLaps <= 0) return null;
    final lapsToFinish = p.totalLaps - p.currentLap + 1;
    return left - lapsToFinish;
  }

  bool get refLoaded => refInfo != null;
  double? get refDelta =>
      _engineer.refDelta.loaded ? _engineer.refDelta.currentDelta() : null;
  String get status => _status;
  bool get isRunning => _source?.isRunning ?? false;
  String get sourceLabel => _source?.label ?? '—';
  List<String> get log => List.unmodifiable(_log);

  void _appendLog(String line) {
    _log.add(line);
    if (_log.length > 500) _log.removeRange(0, _log.length - 500);
  }

  void setVoiceEnabled(bool v) {
    voiceEnabled = v;
    speaker.enabled = v;
    if (!v) speaker.stopNow();
    scheduleSettingsSave();
    notifyListeners();
  }

  Future<void> startDemo() async {
    await stop();
    _engineer = RaceEngineer(engineerCfg);
    if (_refData != null) _engineer.setReference(_refData!);
    _recorder = TelemetryRecorder(recordingCfg);
    final src = TelemetrySimulator();
    _bind(src);
    await src.start();
    _status = 'Tryb demo uruchomiony.';
    _appendLog('--- Start: tryb demo ---');
    _radioCheck();
    notifyListeners();
  }

  Future<void> connectPs5({String? ip, String? format}) async {
    await stop();
    if (ip != null && ip.trim().isNotEmpty) playstationIp = ip.trim();
    if (format != null) packetFormat = format;
    _engineer = RaceEngineer(engineerCfg);
    if (_refData != null) _engineer.setReference(_refData!);
    _recorder = TelemetryRecorder(recordingCfg);
    final src = Gt7Listener(
      playstationIp: playstationIp,
      packetFormat: packetFormat,
    );
    _bind(src);
    await src.start();
    _status = 'Nasłuch... czekam na dane z GT7 ($playstationIp).';
    _appendLog('--- Start: PS5 $playstationIp (format $packetFormat) ---');
    _radioCheck();
    notifyListeners();
  }

  void _radioCheck() {
    if (voiceEnabled) {
      speaker.say(PolishMessages().radioCheck(), priority: Priority.high);
    }
  }

  /// Ustawia nagrane okrążenie (pełne dane z próbkami) jako referencję.
  void setReference(Map<String, dynamic> fullData) {
    try {
      // Walidacja + metadane (działa też, gdy inżynier nie jest uruchomiony).
      final info = ReferenceDelta(
        minDeltaS: engineerCfg.deltaMinSeconds,
        sectors: engineerCfg.refSectors,
      ).loadFromData(fullData);
      _refData = fullData;
      refInfo = info;
      _engineer.setReference(fullData); // jeśli jedzie - od razu aktywne
      _appendLog(
          '[REFERENCJA] ${info.carName}, ${info.lapTime} (${info.trackKey})');
    } catch (e) {
      _appendLog('[REFERENCJA] Niepoprawne nagranie: $e');
    }
    notifyListeners();
  }

  /// Ustawia referencję z pliku nagrania (wczytuje pełne dane).
  Future<void> setReferenceFromPath(String path) async {
    final data = await recordings.loadFull(path);
    setReference(data);
  }

  void clearReference() {
    _refData = null;
    refInfo = null;
    _engineer.clearReference();
    _appendLog('[REFERENCJA] Wyczyszczona.');
    notifyListeners();
  }

  void _bind(TelemetrySource src) {
    _source = src;
    src.packets.listen((p) {
      if (_disposed) return; // pakiet w trakcie sprzątania - ignoruj
      _last = p;
      if (_status.startsWith('Nasłuch')) _status = 'Odbieram dane.';
      // Analiza na żywo -> komunikaty inżyniera.
      for (final a in _engineer.update(p)) {
        _appendLog(a.text);
        if (voiceEnabled) {
          speaker.say(a.text, priority: a.priority, key: a.key, minGap: a.minGap);
        }
      }
      _currentDelta = _engineer.delta.currentDelta();
      // Nagrywanie okrążeń: zapis pliku przy zamknięciu poprawnego okrążenia.
      final lap = _recorder.update(p);
      if (lap != null) {
        recordings.save(lap.data, lap.filename).then((path) {
          _appendLog('[NAGRYWANIE] Zapisano okrazenie: ${lap.filename}');
          recordingsRev++;
          notifyListeners();
        }).catchError((_) {});
      }
      notifyListeners();
    });
  }

  Future<void> stop() async {
    if (_source != null) {
      _appendLog('--- Stop ---');
      await speaker.stopNow();
      await _source!.stop();
      _source = null;
      _last = null;
      _currentDelta = null;
      _status = 'Zatrzymany.';
      notifyListeners();
    }
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    _source?.stop();
    super.dispose();
  }
}

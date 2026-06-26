/// Przypisania nazw torów po OBRYSIE śladu (fingerprint) — WSPÓLNE dla wszystkich
/// użytkowników (Firestore `track_labels`), z lokalnym cache offline.
///
/// Telemetria GT7 nie podaje ID toru, więc tor rozpoznajemy po fingerprincie
/// (długość + obrys x-z). Bounding box jest stały dla układu niezależnie od linii,
/// dlatego dopasowujemy z tolerancją. Gdy jeden użytkownik nazwie tor, wpis ląduje
/// w chmurze i widzą go wszyscy. Bez Firebase działa lokalnie (plik na telefonie).
library;

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';

import '../auth/auth_service.dart';

class _Label {
  _Label(this.l, this.w, this.h, this.name);
  final double l, w, h;
  final String name;
}

class TrackLabelStore {
  final List<_Label> _labels = [];
  bool _loaded = false;

  static const double _tolWh = 0.08;
  static const double _tolL = 0.06;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<File> _file() async {
    final base = await getApplicationDocumentsDirectory();
    return File('${base.path}/track_labels.json');
  }

  /// Wczytuje etykiety: najpierw lokalny cache (szybko), potem chmura (źródło
  /// prawdy), którą cache'ujemy lokalnie do trybu offline.
  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    await _loadLocal();
    await _loadCloud();
    _loaded = true;
  }

  Future<void> _loadLocal() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final list = jsonDecode(await f.readAsString()) as List;
        _labels
          ..clear()
          ..addAll(list.map((m) => _Label(
                (m['l'] as num).toDouble(),
                (m['w'] as num).toDouble(),
                (m['h'] as num).toDouble(),
                '${m['name']}',
              )));
      }
    } catch (_) {}
  }

  Future<void> _loadCloud() async {
    if (!AuthService.firebaseReady) return;
    try {
      final snap = await _db.collection('track_labels').get();
      _labels
        ..clear()
        ..addAll(snap.docs.map((d) {
          final m = d.data();
          return _Label(
            (m['l'] as num).toDouble(),
            (m['w'] as num).toDouble(),
            (m['h'] as num).toDouble(),
            '${m['name']}',
          );
        }));
      await _saveLocal(); // odśwież cache offline
    } catch (_) {
      // brak sieci / uprawnień - zostajemy na cache lokalnym
    }
  }

  double _rel(double a, double b) =>
      b == 0 ? (a == 0 ? 0 : 1) : (a - b).abs() / b.abs();

  bool _matches(_Label lab, double l, double w, double h) =>
      _rel(lab.w, w) <= _tolWh && _rel(lab.h, h) <= _tolWh && _rel(lab.l, l) <= _tolL;

  ({double l, double w, double h})? _fp(Map<String, dynamic>? fp) {
    if (fp == null) return null;
    final l = (fp['length_m'] as num?)?.toDouble();
    final w = (fp['width_m'] as num?)?.toDouble();
    final h = (fp['height_m'] as num?)?.toDouble();
    if (l == null || w == null || h == null) return null;
    return (l: l, w: w, h: h);
  }

  /// Nazwa przypisana do toru pasującego do fingerprintu, albo null.
  String? nameFor(Map<String, dynamic>? fingerprint) {
    final p = _fp(fingerprint);
    if (p == null) return null;
    for (final lab in _labels) {
      if (_matches(lab, p.l, p.w, p.h)) return lab.name;
    }
    return null;
  }

  /// Klucz dokumentu (kwantyzowany obrys) - jeden wpis na tor, zapobiega duplikatom.
  String _docId(double l, double w, double h) =>
      'L${(l / 50).round() * 50}_W${(w / 20).round() * 20}_H${(h / 20).round() * 20}';

  /// Przypisuje nazwę torowi o danym fingerprincie (lokalnie + w chmurze).
  Future<void> assign(Map<String, dynamic>? fingerprint, String name) async {
    final p = _fp(fingerprint);
    if (p == null) return;
    _labels.removeWhere((lab) => _matches(lab, p.l, p.w, p.h));
    _labels.add(_Label(p.l, p.w, p.h, name));
    await _saveLocal();
    if (AuthService.firebaseReady) {
      try {
        await _db.collection('track_labels').doc(_docId(p.l, p.w, p.h)).set({
          'l': p.l,
          'w': p.w,
          'h': p.h,
          'name': name,
          'by': AuthService().currentUser?.uid,
          'at': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }
  }

  Future<void> _saveLocal() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode([
        for (final lab in _labels)
          {'l': lab.l, 'w': lab.w, 'h': lab.h, 'name': lab.name}
      ]));
    } catch (_) {}
  }
}

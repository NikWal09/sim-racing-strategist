/// Magazyn nagrań okrążeń na dysku telefonu.
///
/// Pliki JSON trzymamy w katalogu dokumentów aplikacji (podkatalog "recordings").
/// Odpowiednik katalogu `recordings/` z desktopu. Udostępnia zapis, listę
/// (lekkie metadane bez próbek), wczytanie pełne i usuwanie.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class RecordingStore {
  Directory? _dir;

  Future<Directory> _recordingsDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/recordings');
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  /// Zapisuje okrążenie. Zwraca ścieżkę pliku.
  Future<String> save(Map<String, dynamic> data, String filename) async {
    final d = await _recordingsDir();
    final f = File('${d.path}/$filename');
    await f.writeAsString(jsonEncode(data));
    return f.path;
  }

  /// Lista nagrań — metadane bez ciężkich próbek, posortowane po (tor, czas okr.).
  Future<List<Map<String, dynamic>>> list() async {
    final d = await _recordingsDir();
    final out = <Map<String, dynamic>>[];
    for (final e in d.listSync()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      if (e.uri.pathSegments.last.startsWith('_')) continue;
      try {
        final m = jsonDecode(await e.readAsString()) as Map<String, dynamic>;
        m.remove('samples'); // lista nie potrzebuje próbek
        m['_file'] = e.path;
        out.add(m);
      } catch (_) {
        // pomiń uszkodzony plik
      }
    }
    out.sort((a, b) {
      final tk = '${a['track_key']}'.compareTo('${b['track_key']}');
      if (tk != 0) return tk;
      return ((a['lap_ms'] ?? 0) as num).compareTo((b['lap_ms'] ?? 0) as num);
    });
    return out;
  }

  /// Wczytuje pełne nagranie (z próbkami) do podglądu.
  Future<Map<String, dynamic>> loadFull(String path) async {
    final m = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    m['_file'] = path;
    return m;
  }

  /// Wszystkie nagrania z PEŁNYMI próbkami (do generowania HTML/raportu).
  Future<List<Map<String, dynamic>>> listFull() async {
    final d = await _recordingsDir();
    final out = <Map<String, dynamic>>[];
    for (final e in d.listSync()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      if (e.uri.pathSegments.last.startsWith('_')) continue;
      try {
        final m = jsonDecode(await e.readAsString()) as Map<String, dynamic>;
        if ((m['samples'] as List?)?.isNotEmpty != true) continue;
        m['_file'] = e.path;
        out.add(m);
      } catch (_) {}
    }
    out.sort((a, b) {
      final tk = '${a['track_key']}'.compareTo('${b['track_key']}');
      if (tk != 0) return tk;
      return ((a['lap_ms'] ?? 0) as num).compareTo((b['lap_ms'] ?? 0) as num);
    });
    return out;
  }

  Future<void> delete(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}

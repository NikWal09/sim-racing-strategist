/// Zapis układów dashboardu na dysku telefonu (lokalnie, per użytkownik).
///
/// Plik JSON w katalogu dokumentów: dashboard_<uid>.json (albo dashboard_local
/// gdy brak logowania). Gdy pliku nie ma — zwracamy układ domyślny.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'dashboard_model.dart';

class DashboardStore {
  Future<File> _file(String? uid) async {
    final base = await getApplicationDocumentsDirectory();
    final tag = (uid == null || uid.isEmpty) ? 'local' : uid;
    return File('${base.path}/dashboard_$tag.json');
  }

  Future<DashboardConfig> load(String? uid) async {
    try {
      final f = await _file(uid);
      if (!await f.exists()) return DashboardConfig.defaultConfig();
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return DashboardConfig.fromJson(m);
    } catch (_) {
      return DashboardConfig.defaultConfig();
    }
  }

  Future<void> save(String? uid, DashboardConfig cfg) async {
    try {
      final f = await _file(uid);
      await f.writeAsString(jsonEncode(cfg.toJson()));
    } catch (_) {
      // Brak dostępu do dysku (np. środowisko testowe) — pomijamy.
    }
  }
}

/// Globalne ustawienia aplikacji: motyw (jasny/ciemny/systemowy) i język.
///
/// Singleton — zmiana powiadamia słuchaczy (MaterialApp przebudowuje się i motyw
/// / język zmieniają się od razu). Zapis lokalny w katalogu dokumentów.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'i18n.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  ThemeMode themeMode = ThemeMode.system;
  String locale = 'pl'; // 'pl' albo 'en'
  String units = 'metric'; // 'metric' albo 'imperial'

  bool get imperial => units == 'imperial';

  /// Tłumaczenie klucza w aktualnym języku.
  String t(String key) => tr(key, locale);

  Future<File> _file() async {
    final base = await getApplicationDocumentsDirectory();
    return File('${base.path}/app_settings.json');
  }

  Future<void> load() async {
    // Domyślnie język wg systemu: polski gdy system po polsku, inaczej angielski.
    // Motyw domyślnie „systemowy" (śledzi jasny/ciemny telefonu).
    _applySystemLanguage();
    try {
      final f = await _file();
      if (!await f.exists()) return; // pierwszy raz — zostaje język systemowy
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      themeMode = _modeFrom('${m['themeMode']}');
      final l = '${m['locale']}';
      if (l == 'pl' || l == 'en') locale = l; // ręczny wybór ma pierwszeństwo
      final u = '${m['units']}';
      if (u == 'metric' || u == 'imperial') units = u;
    } catch (_) {
      // brak/uszkodzony plik — zostają domyślne (język systemowy)
    }
  }

  void _applySystemLanguage() {
    final sys =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    locale = sys == 'pl' ? 'pl' : 'en';
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(
          {'themeMode': themeMode.name, 'locale': locale, 'units': units}));
    } catch (_) {}
  }

  void setThemeMode(ThemeMode m) {
    if (m == themeMode) return;
    themeMode = m;
    notifyListeners();
    _save();
  }

  void setLocale(String l) {
    if (l == locale || (l != 'pl' && l != 'en')) return;
    locale = l;
    notifyListeners();
    _save();
  }

  void setUnits(String u) {
    if (u == units || (u != 'metric' && u != 'imperial')) return;
    units = u;
    notifyListeners();
    _save();
  }

  ThemeMode _modeFrom(String s) => s == 'light'
      ? ThemeMode.light
      : s == 'dark'
          ? ThemeMode.dark
          : ThemeMode.system;
}

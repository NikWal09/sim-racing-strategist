/// Sterowanie dozwoloną orientacją ekranu per widok.
///
/// Założenie: większość ekranów (menu, listy, ustawienia, logowanie) można
/// obracać w pionie i poziomie. Podgląd (dashboard) i strony HTML z telemetrią
/// zostają w poziomie, bo w pionie nie miałyby sensu.
library;

import 'package:flutter/services.dart';

class ScreenOrientation {
  /// Wszystkie kierunki — dla zwykłych ekranów (menu/listy/ustawienia).
  static Future<void> all() =>
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

  /// Tylko poziom (oba kierunki) — dla Podglądu/dashboardu.
  static Future<void> landscape() =>
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

  /// Poziom w JEDNYM kierunku — dla stron HTML w WebView. Pojedynczy kierunek
  /// omija błąd webview_flutter, który w odwróconym poziomie renderuje treść
  /// do góry nogami.
  static Future<void> landscapeFixed() =>
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
      ]);
}

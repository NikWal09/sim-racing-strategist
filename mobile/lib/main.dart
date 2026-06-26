/// GT7 Race Engineer (mobile).
///
/// Wersja mobilna z tym samym układem zakładek i wyglądem co aplikacja
/// desktopowa. Konta + chmura przez Firebase (logowanie e-mail/Google). Gdy
/// Firebase nie jest skonfigurowany, apka działa w trybie lokalnym bez kont.
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_settings.dart';
import 'auth/auth_service.dart';
import 'firebase_options.dart';
import 'orientation_modes.dart';
import 'ui/auth_gate.dart';
import 'ui/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Domyślnie pozwalamy obracać ekran (pion+poziom). Podgląd i strony HTML same
  // wymuszają poziom, gdy są na wierzchu (patrz HomeShell / HtmlViewScreen).
  await ScreenOrientation.all();
  // Pełny ekran: chowamy pasek powiadomień i pasek nawigacji (przyciski).
  // immersiveSticky = znikają na stałe, a przesunięcie od krawędzi pokazuje je
  // chwilowo i znów chowa - idealne dla dashboardu.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // Wczytaj zapisany motyw i język przed startem UI.
  await AppSettings.instance.load();
  // Inicjalizacja Firebase z opcjami z firebase_options.dart (działa na każdej
  // platformie: Android, iOS, Windows). Gdy się nie uda - apka wchodzi w tryb
  // lokalny bez kont, zamiast się wywracać.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    AuthService.firebaseReady = true;
  } catch (_) {
    AuthService.firebaseReady = false;
  }
  runApp(const Gt7App());
}

class Gt7App extends StatelessWidget {
  const Gt7App({super.key});

  @override
  Widget build(BuildContext context) {
    // Przebudowa przy zmianie motywu/języka (AppSettings powiadamia).
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'GT7 Race Engineer',
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: AppSettings.instance.themeMode,
          home: const AuthGate(),
        );
      },
    );
  }
}

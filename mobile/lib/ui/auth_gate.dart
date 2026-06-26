/// Bramka logowania: decyduje, co pokazać.
///
/// - Firebase niedostępny (brak konfiguracji) -> tryb lokalny: od razu HomeShell.
/// - Brak zalogowanego użytkownika -> LoginScreen.
/// - Zalogowany bez nazwy -> SetupScreen.
/// - Zalogowany z nazwą -> HomeShell.
///
/// Na Android/iOS używamy strumienia authStateChanges. Na Windows/Linux strumień
/// `firebase_auth` wywala apkę (zdarzenia z wątku w tle), więc tam odświeżamy
/// stan ręcznie przez [AuthService.authTick].
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import 'home_shell.dart';
import 'login_screen.dart';
import 'setup_screen.dart';
import 'verify_email_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _auth = AuthService();
  late final Stream<User?> _authStream = _auth.authState;

  @override
  void initState() {
    super.initState();
    // Windows: sesja sprzed restartu wczytuje się chwilę po starcie, a strumienia
    // nie używamy - więc raz odśwież po sekundzie, żeby auto-logowanie zadziałało.
    if (AuthService.firebaseReady && !AuthService.streamSafe) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) AuthService.authTick.value++;
      });
    }
  }

  Widget _screenFor(User? user) {
    if (user == null) return const LoginScreen();
    // Konto e-mail bez potwierdzonego adresu -> brama weryfikacji.
    // (Konta Google mają emailVerified = true, więc tu nie wpadają.)
    if (!user.emailVerified) {
      return VerifyEmailScreen(onVerified: () => setState(() {}));
    }
    if ((user.displayName ?? '').trim().isEmpty) {
      return SetupScreen(onDone: () => setState(() {}));
    }
    return const HomeShell();
  }

  @override
  Widget build(BuildContext context) {
    // Bez Firebase: apka działa lokalnie, bez kont.
    if (!AuthService.firebaseReady) return const HomeShell();

    // Windows/Linux: bez strumienia (crashuje) - ręczne odświeżanie po akcjach.
    if (!AuthService.streamSafe) {
      return ValueListenableBuilder<int>(
        valueListenable: AuthService.authTick,
        builder: (context, _, __) => _screenFor(_auth.currentUser),
      );
    }

    // Android/iOS/web/macOS: strumień stanu logowania. Strumień służy do reakcji
    // na logowanie/wylogowanie; właściwą decyzję podejmujemy na świeżym
    // currentUser (reload po weryfikacji e-maila nie emituje zdarzenia).
    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return _screenFor(_auth.currentUser);
      },
    );
  }
}

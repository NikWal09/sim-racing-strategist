/// Warstwa logowania (Firebase Auth + Google).
///
/// `firebaseReady` ustawiamy w main() po udanej inicjalizacji Firebase. Gdy
/// Firebase nie jest skonfigurowany, apka działa w trybie lokalnym bez kont
/// (patrz [AuthGate]).
///
/// WAŻNE (Windows): `firebase_auth` na desktopie wysyła zdarzenia auth-state /
/// id-token z wątku w tle, co wywala silnik Windows ("non-platform thread").
/// Dlatego na Windows/Linux NIE subskrybujemy strumienia [authState] — bramka
/// odświeża stan ręcznie po akcjach przez licznik [authTick]. Na mobilce
/// (Android/iOS) strumień działa i jest pełniejszy, więc tam go używamy.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static bool firebaseReady = false;

  /// Czy bezpiecznie używać strumienia authStateChanges (NIE na Windows/Linux).
  static bool get streamSafe =>
      !kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.windows ||
                  defaultTargetPlatform == TargetPlatform.linux)
          ? false
          : true;

  /// Licznik zmian logowania - WSPÓLNY dla wszystkich instancji (różne ekrany
  /// tworzą własne AuthService). Do ręcznego odświeżania UI na desktopie.
  static final ValueNotifier<int> authTick = ValueNotifier<int>(0);
  void _bump() => authTick.value++;

  FirebaseAuth get _auth => FirebaseAuth.instance;

  Stream<User?> get authState =>
      firebaseReady ? _auth.authStateChanges() : const Stream.empty();

  User? get currentUser => firebaseReady ? _auth.currentUser : null;

  /// Czy zalogowany użytkownik ma potwierdzony adres e-mail. Konta Google są
  /// weryfikowane od razu; konta e-mail/hasło dopiero po kliknięciu w link.
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  /// Czy trzeba pokazać bramę weryfikacji (jest user, ale e-mail niepotwierdzony).
  bool get needsEmailVerification {
    final u = _auth.currentUser;
    return u != null && !u.emailVerified;
  }

  /// Czy konto loguje się e-mailem+hasłem (a nie tylko przez Google). Tylko
  /// takie konta mają hasło do zmiany / re-uwierzytelnienia hasłem.
  bool get isPasswordAccount =>
      _auth.currentUser?.providerData
          .any((p) => p.providerId == 'password') ??
      false;

  Future<void> signInEmail(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
    _bump();
  }

  /// Rejestracja: tworzy konto, zapisuje nazwę i wysyła link weryfikacyjny.
  Future<void> registerEmail(
      String email, String password, String displayName) async {
    final cred = await _auth.createUserWithEmailAndPassword(
        email: email, password: password);
    final name = displayName.trim();
    if (name.isNotEmpty) {
      await cred.user?.updateDisplayName(name);
    }
    await cred.user?.sendEmailVerification();
    await cred.user?.reload();
    _bump();
  }

  /// Ponowne wysłanie linku weryfikacyjnego na e-mail.
  Future<void> sendEmailVerification() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  /// Odświeża dane konta i zwraca aktualny stan weryfikacji e-maila.
  Future<bool> reloadAndCheckVerified() async {
    await _auth.currentUser?.reload();
    _bump();
    return _auth.currentUser?.emailVerified ?? false;
  }

  /// Wysyła e-mail z linkiem do zresetowania hasła.
  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  /// Zmiana hasła. Wymaga ponownego uwierzytelnienia bieżącym hasłem.
  Future<void> changePassword(
      String currentPassword, String newPassword) async {
    final u = _auth.currentUser;
    final email = u?.email;
    if (u == null || email == null) {
      throw FirebaseAuthException(code: 'no-user');
    }
    final cred =
        EmailAuthProvider.credential(email: email, password: currentPassword);
    await u.reauthenticateWithCredential(cred);
    await u.updatePassword(newPassword);
    _bump();
  }

  /// Trwałe usunięcie konta. Wymaga ponownego uwierzytelnienia hasłem.
  Future<void> deleteAccount(String currentPassword) async {
    final u = _auth.currentUser;
    final email = u?.email;
    if (u == null || email == null) {
      throw FirebaseAuthException(code: 'no-user');
    }
    final cred =
        EmailAuthProvider.credential(email: email, password: currentPassword);
    await u.reauthenticateWithCredential(cred);
    await u.delete();
    _bump();
  }

  /// Logowanie kontem Google. Zwraca false, gdy użytkownik anulował.
  Future<bool> signInGoogle() async {
    final google = await GoogleSignIn().signIn();
    if (google == null) return false; // anulowano
    final auth = await google.authentication;
    final cred = GoogleAuthProvider.credential(
      accessToken: auth.accessToken,
      idToken: auth.idToken,
    );
    await _auth.signInWithCredential(cred);
    _bump();
    return true;
  }

  Future<void> setDisplayName(String name) async {
    await _auth.currentUser?.updateDisplayName(name);
    await _auth.currentUser?.reload();
    _bump();
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    await _auth.signOut();
    _bump();
  }
}

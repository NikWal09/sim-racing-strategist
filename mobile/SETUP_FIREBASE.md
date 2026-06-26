# Konfiguracja Firebase (konta + chmura)

Apka działa **bez** Firebase w trybie lokalnym (bez kont). Żeby włączyć logowanie
e-mail/Google i chmurę, raz skonfiguruj projekt Firebase. Kod jest już gotowy —
to jedyna część po Twojej stronie.

## 1. Projekt Firebase

1. Wejdź na https://console.firebase.google.com → **Add project** → nazwa (np.
   „gt7-engineer"). Google Analytics możesz pominąć.

## 2. FlutterFire CLI (automat)

Wymaga Node.js i Firebase CLI.

```bash
npm install -g firebase-tools
firebase login
dart pub global activate flutterfire_cli
cd mobile
flutterfire configure
```

W kreatorze wybierz swój projekt i platformy **Android** (i **iOS**, jeśli masz Maca).
To wgra `google-services.json` (Android) / `GoogleService-Info.plist` (iOS) i
wygeneruje `firebase_options.dart`. Nasz kod używa `Firebase.initializeApp()` —
zadziała, bo pliki natywne będą na miejscu.

## 3. Włącz logowanie w konsoli

Firebase Console → **Build → Authentication → Get started → Sign-in method**:
- włącz **Email/Password**,
- włącz **Google** (podaj e-mail wsparcia).

## 4. Google Sign-In na Androidzie — odcisk SHA-1

Logowanie Google wymaga odcisku podpisu aplikacji:

```bash
cd mobile/android
./gradlew signingReport        # Windows: gradlew signingReport
```

Skopiuj **SHA1** z wariantu `debug`, wklej w Firebase Console → ustawienia projektu
→ Twoja apka Android → **Add fingerprint**. Potem **pobierz ponownie**
`google-services.json` i podmień w `android/app/`.

## 5. Firestore — chmura ustawień i wspólna baza nazw torów

1. Firebase Console → **Build → Firestore Database → Create database** → wybierz
   region (np. `eur3`) → na start „tryb testowy" jest OK.
2. **Reguły bezpieczeństwa** (zakładka Rules) — wklej i opublikuj:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Każdy zalogowany czyta/zapisuje TYLKO swój dokument ustawień.
    match /users/{uid} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
    // Wspólna baza nazw torów: każdy zalogowany czyta i dopisuje.
    match /track_labels/{id} {
      allow read, write: if request.auth != null;
    }
  }
}
```

Co to daje:
- **`users/{uid}`** — indywidualne ustawienia każdego testera (połączenie, głos,
  progi inżyniera, nagrywanie). Wczytują się po zalogowaniu i zapisują przy zmianie.
- **`track_labels`** — WSPÓLNA baza: gdy ktoś nazwie tor („Nazwij tor" w
  Nagraniach), wpis trafia do chmury i widzą go wszyscy. Tak razem identyfikujecie tory.

Bez Firestore apka dalej działa (ustawienia i nazwy zostają lokalnie na urządzeniu).

## 6. Możliwe poprawki buildu Androida

Jeśli `flutter run` zgłosi błąd związany z `minSdkVersion`, ustaw w
`android/app/build.gradle` (sekcja `defaultConfig`):

```gradle
minSdkVersion 23
multiDexEnabled true
```

## 7. Uruchom

```bash
cd mobile
flutter pub get
flutter run
```

Pojawi się ekran logowania → zarejestruj konto albo zaloguj przez Google → przy
pierwszym wejściu podaj nazwę/ksywę → wchodzisz do aplikacji.

> Bez wykonania powyższego apka dalej działa, ale od razu wchodzi do środka w
> trybie lokalnym (bez ekranu logowania).

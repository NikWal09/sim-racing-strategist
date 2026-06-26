# GT7 Race Engineer — wersja mobilna (Flutter)

Apka na Androida i iPhone'a. Telefon w tej samej sieci Wi-Fi co PlayStation
odbiera telemetrię UDP z GT7, analizuje na żywo i (docelowo) mówi po polsku jak
wersja na PC. Plan etapów: zobacz `../FLUTTER_PLAN.md`.

## Stan: Etap 2 — dashboard na żywo + ujednolicony wygląd z desktopem

Wygląd i układ zakładek odwzorowują aplikację desktopową (`gt7_gui_qt.py`):
ciemny motyw, ta sama paleta kolorów, **okrągłe zegary** prędkości i RPM (z czerwoną
strefą). Aplikacja chodzi na stałe **w poziomie**; zakładki wybiera się z **bocznego
wysuwanego menu** (Drawer, ikona ≡), a Podgląd **skaluje się** do każdego ekranu
(FittedBox).

- `lib/telemetry/` — model pakietu, dekoder (Salsa20), listener UDP, wspólny
  interfejs źródła, symulator (tryb demo).
- `lib/app_state.dart` — `TelemetryController` (źródło, pakiet, status, log)
  współdzielony przez zakładki.
- `lib/ui/theme.dart` — paleta i style 1:1 z desktopu + kafelek `InfoTile`.
- `lib/ui/circular_gauge.dart` — okrągły zegar (port `CircularGauge` z Qt).
- `lib/ui/preview_tab.dart` — **Podgląd**: 2 zegary, bieg, kafelki, opony.
- `lib/ui/engineer_tab.dart` — **Inżynier**: Start/Demo/Stop, status, log.
- `lib/ui/settings_tab.dart` — **Ustawienia**: IP konsoli + format.
- `lib/ui/placeholder_tab.dart` — **Nagrania** / **Test głosów** (w przygotowaniu).
- `lib/ui/home_shell.dart` — powłoka z dolną nawigacją (5 zakładek).
- `test/` — test dekodera (realny wektor) + test dymny UI.

### Etap 3 — mowa (gotowe)

- `lib/messages/messages_pl.dart` — polskie komunikaty inżyniera (port `pl.py`,
  pełne diakrytyki) + formatowanie liczb/czasu pod TTS.
- `lib/speech/speaker.dart` — kolejka priorytetowa + anti-spam na `flutter_tts`
  (port zachowania `speaker.py`).
- `lib/ui/voice_tab.dart` — **Test głosów**: wybór głosu PL, tempo, komunikat,
  odsłuch. Zakładka działa.
- `test/messages_test.dart` — weryfikacja formatowania względem wartości z Pythona.

### Etap 4 — inżynier na żywo (gotowe)

- `lib/engineer/` — port logiki z Pythona: `delta_tracker.dart` (delta po pozycji),
  `corner_tracker.dart` (zakręty + temperatury opon), `session_state.dart`
  (paliwo/trendy), `race_engineer.dart` (orkiestracja: czasy okrążeń, paliwo,
  pozycje, opony, zakręty, delta) + `engineer_config.dart` (progi jak na desktopie).
- Wpięte w `TelemetryController`: na każdy pakiet inżynier analizuje, **mówi** po
  polsku i dopisuje do logu; **delta na żywo** pokazuje się na dashboardzie.
- Przełącznik „Głos inżyniera" w zakładce Inżynier.
- `test/engineer_test.dart` — komunikat połączenia + czas okrążenia (zgodne z
  zachowaniem analyzera w Pythonie).

### Etap 5 — Nagrania (gotowe)

- `lib/engineer/telemetry_recorder.dart` — port `recorder.py`: buforuje próbki,
  po przecięciu linii zapisuje poprawne okrążenie (fingerprint + track_key).
- `lib/engineer/recording_store.dart` — pliki JSON w katalogu dokumentów apki
  (`path_provider`): zapis, lista, wczytanie, usuwanie.
- Wpięte w `TelemetryController`: okrążenia nagrywają się automatycznie podczas
  jazdy; zapis dopisuje wpis do logu.
- `lib/ui/recordings_tab.dart` — **Nagrania**: lista okrążeń (tor, czas, auto),
  odświeżanie, usuwanie, wejście do podglądu.
- **Podgląd telemetrii jako HTML** (jak w wersji komputerowej): `viewer_html.dart`
  (port szablonu z `telemetry_viewer.py`) + `tyre_report_html.dart` (port
  `tyre_report.py`) renderowane w `html_view_screen.dart` (WebView na mobile,
  przeglądarka systemowa na desktopie). Przyciski **„Telemetria"** i **„Raport
  opon"** w zakładce Nagrania; stuknięcie okrążenia otwiera jego podgląd HTML.
  Daje porównanie wielu okrążeń, mapę toru, wykresy kanałów i analizę opon —
  identycznie jak na komputerze.
- `test/recorder_test.dart` — out-lap pominięty, mierzone okrążenie zapisane
  (zgodne z `recorder.py`).

W trybie demo nagranie pojawia się po kilku okrążeniach symulatora (~kilka minut,
bo jedno kółko to ~95 s); na realnej konsoli okrążenia są naturalne.

### Etap 6 — referencja + Ustawienia (gotowe)

- `ReferenceDelta` (w `delta_tracker.dart`) — port `reference.py`: dowolne nagrane
  okrążenie (też z innego auta) jako stała referencja; delta pozycyjna + wyniki
  per sektor. Zweryfikowane z Pythonem (te same próbki/granice sektorów).
- Wpięte w `race_engineer.dart` (DELTA REF + komunikaty „tracisz/zyskujesz w
  sektorze N") i w `TelemetryController` (ustaw/wyczyść, przeżywa restart silnika).
- Zakładka **Nagrania**: menu na okrążeniu → „Ustaw jako referencję", baner z
  aktywną referencją + „Wyczyść".
- **Podgląd**: pole **DELTA REF** pojawia się, gdy referencja jest ustawiona.
- **Ustawienia** rozbudowane: połączenie, głos (tempo), przełączniki i progi
  inżyniera, nagrywanie.
- `test/reference_test.dart` — wczytanie/metadane/czyszczenie referencji.

To domyka port wersji mobilnej do parytetu z aplikacją komputerową.

### Konta + chmura (Firebase)

Logowanie e-mail + Google, żeby udostępnić apkę znajomym — każdy ma swoje konto,
swoje ustawienia i swoją (lokalną) telemetrię, a nazwy torów są wspólne.
- `lib/auth/`, `lib/ui/login_screen.dart`, `setup_screen.dart`, `auth_gate.dart` —
  logowanie/rejestracja + pierwsza konfiguracja (ksywa) + wylogowanie.
- `main.dart` inicjuje Firebase z `firebase_options.dart` (wszystkie platformy);
  **bez konfiguracji apka działa lokalnie** (od razu wchodzi do środka).
- `lib/cloud/user_settings_service.dart` + kontroler — **indywidualne ustawienia
  w chmurze** (`users/{uid}`): wczytują się po zalogowaniu, zapisują z debounce
  przy każdej zmianie w Ustawieniach.
- `lib/engineer/track_labels.dart` — **wspólna baza nazw torów** (`track_labels`):
  jeden nazwie tor, widzą wszyscy. Offline: cache lokalny.
- Konfiguracja Firebase (projekt, logowanie, Firestore + reguły): `SETUP_FIREBASE.md`.

Platformy: **Windows i Android** działają. iOS wymaga Maca (do zrobienia później).

### Nazwy torów

Telemetria GT7 (formaty A/B/~) **nie zawiera ID toru**, więc nazwy nie da się
przypisać automatycznie z pakietu. Rozpoznajemy tor po **obrysie śladu**
(fingerprint — bounding box jest stały dla układu niezależnie od linii) i pozwalamy
raz przypisać nazwę:

- `lib/engineer/gt7_tracks.dart` — lista oficjalnych nazw torów GT7 (źródło:
  github.com/MacManley/gt7-track-visualizer).
- `lib/engineer/track_labels.dart` — zapis przypisań `fingerprint → nazwa` w
  pliku w katalogu apki, dopasowanie z tolerancją (obrys ±8%, długość ±6%).
- Zakładka **Nagrania** → menu (⋮) → **„Nazwij tor"** (wyszukiwarka po liście GT7
  lub własna nazwa). Po przypisaniu wszystkie okrążenia tego toru pokazują nazwę
  zamiast `L5000-W800-...`.

#### Android — głos i TTS

flutter_tts na Androidzie 11+ wymaga deklaracji zapytania o silnik TTS. Dodaj do
`android/app/src/main/AndroidManifest.xml` (wewnątrz `<manifest>`, obok `<application>`):

```xml
<queries>
  <intent>
    <action android:name="android.intent.action.TTS_SERVICE" />
  </intent>
</queries>
```

Na emulatorze może nie być polskiego głosu — wgraj go w
Ustawienia → System → Języki → Zamiana tekstu na mowę (lub silnik Google TTS).

## Uruchomienie

Wymaga zainstalowanego Fluttera (https://docs.flutter.dev/get-started/install).

```bash
cd mobile
flutter pub get
flutter test          # weryfikacja dekodera (bez konsoli)
flutter run           # na podlaczonym telefonie / emulatorze
```

W apce: „Tryb demo" pokazuje dashboard na symulatorze (bez konsoli). „Połącz z
PS5" — wpisz IP PlayStation, wybierz format (domyślnie B — ma kąt kierownicy).
GT7 musi mieć włączone „Wyślij dane telemetryczne" w opcjach.

Uwaga: apka używa `dart:io` (UDP), więc **nie zbuduje się na web**. Uruchamiaj na
telefonie/emulatorze Androida, na iPhonie (z Maca) lub na desktopie. `flutter test`
kompiluje cały kod (przez test dymny), więc weryfikuje, że wszystko się buduje.

## iOS — uprawnienie sieci lokalnej

Od iOS 14 pierwszy dostęp do LAN wymaga zgody. Dodaj do `ios/Runner/Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Odbiór telemetrii z PlayStation w sieci lokalnej.</string>
```

## Android — uprawnienie internetu

`android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

(UDP w sieci lokalnej mieści się w uprawnieniu INTERNET.)

## Uwaga

Projekt Flutter wymaga jeszcze wygenerowania platformowych folderów
(`flutter create .` w katalogu `mobile/`, zachowując istniejące `lib/`),
co tworzy `android/` i `ios/`. Następnie `flutter pub get`.

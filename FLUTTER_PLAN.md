# Plan apki mobilnej — GT7 Race Engineer na telefon (Flutter)

Cel: **jedna apka na Androida i iPhone'a**, działająca samodzielnie tak jak wersja
na PC — telefon w tej samej sieci Wi-Fi co PS5, odbiera telemetrię UDP, analizuje na
żywo, mówi po polsku i pokazuje dashboard. Bez serwera pośredniczącego na PC.

## 1. Dlaczego Flutter (a nie reużycie Pythona)

- Python na iOS jest praktycznie nie do utrzymania (App Store + brak tła sieciowego).
- Flutter daje **jedną bazę kodu na oba systemy**, natywną wydajność i pełny dostęp
  do gniazd UDP oraz natywnego TTS.
- Logika jest niewielka i dobrze zdefiniowana (mamy ją w Pythonie jako wzorzec),
  więc port do Darta jest wykonalny.

Koszt: przenosimy logikę z Pythona do Darta (decoder, analyzer, delta, reference,
corners, recorder). UI i mowę piszemy od zera (i tak były specyficzne dla Qt/edge-tts).

## 2. Ograniczenia techniczne (ważne)

- **UDP**: w Darcie `RawDatagramSocket` obsługuje UDP w pełni — wysyłka heartbeatu i
  odbiór pakietów działa na obu systemach. (Przeglądarka by tego nie umiała — dlatego
  apka natywna, nie PWA.)
- **Tło / ekran**: telemetria leci ~60 Hz. Apka musi działać z włączonym ekranem
  (`wakelock`), bo iOS ucina sieć w tle. Zakładamy: telefon leży obok kierownicy z
  włączonym ekranem (typowy scenariusz dla dashboardu wyścigowego).
- **TTS**: `flutter_tts` korzysta z natywnych silników (Android TTS / AVSpeech iOS).
  Polskie głosy są dostępne na obu systemach. To zastępuje edge-tts (edge-tts wymaga
  internetu i nie ma go na telefonie sensownie).
- **Sieć lokalna iOS**: od iOS 14 pierwsze użycie LAN wymaga zgody użytkownika
  („Local Network permission") — trzeba dodać wpis w `Info.plist`.

## 3. Mapowanie modułów Python -> Dart

| Python | Dart (mobile/lib/) | Uwagi |
|---|---|---|
| `telemetry/packet.py` | `telemetry/gt7_packet.dart` | model + properties (speed_kph, fuel_pct, format_laptime) |
| `telemetry/decoder.py` | `telemetry/decoder.dart` | Salsa20 z pakietu `pointycastle`; te same offsety bajtów |
| `telemetry/listener.py` | `telemetry/listener.dart` | `RawDatagramSocket` + heartbeat co N pakietów |
| `engineer/analyzer.py` | `engineer/analyzer.dart` | rdzeń decyzji o komunikatach |
| `engineer/delta.py` | `engineer/delta.dart` | delta pozycyjna do najlepszego okrążenia |
| `engineer/reference.py` | `engineer/reference.dart` | referencja z pliku + sektory |
| `engineer/corners.py` | `engineer/corners.dart` | wykrywanie zakrętów / gorących opon |
| `engineer/recorder.py` | `engineer/recorder.dart` | zapis okrążeń do JSON (katalog dokumentów apki) |
| `engineer/messages/pl.py` | `messages/pl.dart` | polskie komunikaty |
| `speech/speaker.py` | `speech/speaker.dart` | kolejka + priorytety, backend = flutter_tts |
| `config.py` / `config.yaml` | `config/config.dart` + ekran ustawień | konfiguracja w UI zamiast YAML |
| `tools/telemetry_viewer.py` | ekran „Telemetria" (CustomPainter) | mapa toru + wykresy natywnie na canvasie |

## 4. Etapy (kamienie milowe)

**Etap 1 — Fundament telemetrii (TERAZ).**
Port `gt7_packet.dart`, `decoder.dart`, `listener.dart`. Weryfikacja: odebrać i
odszyfrować realny pakiet z PS5 (magic == G7S0), wyświetlić surowe pola (prędkość,
bieg, RPM, okrążenie) na prostym ekranie debug. To odblokowuje wszystko inne.

**Etap 2 — Dashboard na żywo.**
Ekran z prędkością, biegiem, RPM (pasek + rev limiter), paliwem, czasami okrążeń,
oponami. `CustomPainter` na zegary. Sterowanie połączeniem (IP PS5, format A/B/~).

**Etap 3 — Mowa (inżynier).**
Port `speaker.dart` (kolejka + priorytety + min_gap) na `flutter_tts`, polskie
komunikaty. Pierwsze komunikaty: czas okrążenia, paliwo, gorące opony.

**Etap 4 — Analyzer + delta.**
Port `analyzer.dart`, `delta.dart`, `corners.dart`. Delta na prostej, strategia
paliwowa, gorące zakręty — pełna logika inżyniera jak na PC.

**Etap 5 — Nagrywanie + podgląd telemetrii.**
Port `recorder.dart` (zapis okrążeń do katalogu dokumentów apki). Ekran podglądu:
mapa toru kolorowana prędkością + wykresy kanałów (CustomPainter), porównanie
okrążeń. Odpowiednik `telemetry_viewer.py`, ale natywnie.

**Etap 6 — Referencja + sektory, ustawienia, dopieszczenie.**
Port `reference.dart` (wybór nagranego okrążenia jako referencji + delta per sektor),
ekran ustawień (odpowiednik config.yaml), ikony, build release (APK / IPA).

## 5. Zależności (pubspec)

- `pointycastle` — Salsa20 (deszyfrowanie pakietu).
- `flutter_tts` — natywny TTS (polskie głosy).
- `wakelock_plus` — ekran nie gaśnie podczas jazdy.
- `path_provider` — katalog na nagrania.
- (UDP i `RawDatagramSocket` są w `dart:io` — bez dodatkowej zależności.)

## 6. Stan / co dalej

- Repo: apka mobilna mieszka w podkatalogu `mobile/` tego repozytorium.
- Sandbox nie ma Fluttera, więc kod Dart powstaje z Pythonem jako wzorcem; kompilacja
  i testy odpalają się u użytkownika (`flutter run`).
- Pierwszy krok do weryfikacji: Etap 1 na realnym PS5 — jeśli magic się zgadza i pola
  mają sens, port dekodera jest poprawny.

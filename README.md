# GT7 Race Engineer

Głosowy inżynier wyścigowy dla **Gran Turismo 7** — odbiera telemetrię gry przez
UDP, analizuje przebieg wyścigu i mówi do kierowcy w stylu CrewChiefa (paliwo,
czasy okrążeń, pozycja, temperatura opon). Działa na PC; gra zostaje na konsoli
PlayStation, więc nadaje się też do grania przez **PS Remote Play**.

## Jak to działa

GT7 udostępnia telemetrię w czasie rzeczywistym: po wysłaniu jednego bajtu `A`
na port UDP **33739** konsoli, GT7 zaczyna nadawać zaszyfrowane (Salsa20) pakiety
na port **33740**. Asystent je odszyfrowuje, parsuje i na tej podstawie generuje
komunikaty głosowe (offline TTS, silnik systemowy).

```
[ PS5/PS4: GT7 ]  --UDP 33740-->  [ PC: GT7 Race Engineer ]  --głos-->  kierowca
       ^------------ heartbeat 'A' na 33739 -------------------|
```

Przy Remote Play gra nadal działa na konsoli — w konfiguracji podajesz **IP
konsoli**, nie PC.

## Wymagania

- Python 3.10+
- Windows zalecany (TTS przez SAPI5 daje polskie głosy out-of-the-box; na innych
  systemach TTS też działa, jeśli masz zainstalowany silnik mowy)
- PC i konsola w **tej samej sieci LAN**

Instalacja zależności:

```bash
pip install -r requirements.txt
```

## Konfiguracja

1. Sprawdź IP konsoli: na PS wejdź w **Ustawienia → Sieć → Stan połączenia →
   Adres IP** (np. `192.168.1.50`).
2. Otwórz `config.yaml` i ustaw `telemetry.playstation_ip` na to IP.
3. (Opcjonalnie) wybierz głos — patrz niżej.

Najważniejsze opcje w `config.yaml`:

| Sekcja | Opcja | Znaczenie |
|---|---|---|
| `telemetry` | `playstation_ip` | IP konsoli z GT7 |
| `telemetry` | `packet_format` | który format telemetrii zamawiać: `A` / `B` / `~` (patrz niżej) |
| `engineer` | `fuel_warning_laps` / `fuel_critical_laps` | progi ostrzeżeń o paliwie (w okrążeniach) |
| `engineer` | `tyre_temp_warning` | próg ostrzeżenia o przegrzanych oponach (°C) |
| `engineer` | `announce_lap_times` / `announce_best_lap` / `announce_position_changes` | co czytać |
| `engineer` | `announce_fuel_strategy` / `fuel_target_margin_laps` | strategia paliwowa: czy starczy do mety, ile oszczędzać, ile dotankować |
| `engineer` | `announce_tyre_sections` / `tyre_sections` / `tyre_section_temp_warning` | nauka sekcji toru, gdzie opony się przegrzewają |
| `engineer` | `announce_delta` / `delta_min_seconds` | delta do najlepszego okrążenia, czytana tylko na prostej |
| `speech` | `language` | język komunikatów: `pl` (polski) lub `en` (angielski) |
| `speech` | `rate` / `volume` / `voice_substring` | tempo, głośność, wybór głosu |
| `speech` | `engine` | silnik głosu: `sapi` (offline) lub `edge` (neuronowy, online) |
| `speech` | `edge_voice` | głos dla `engine: edge`, np. `pl-PL-MarekNeural` (pusty = domyślny) |
| `speech` | `min_gap_seconds` | minimalny odstęp między komunikatami |
| `debug` | `print_telemetry` / `log_events` | diagnostyka na konsoli |

### Język komunikatów (`speech.language`)

Inżynier mówi po **polsku** (`pl`, domyślnie) albo **angielsku** (`en`). Każdy
komunikat ma kilka wariantów sformułowania losowanych w trakcie jazdy, więc głos
brzmi mniej robotycznie. Polskie teksty używają pełnych znaków diakrytycznych
(ą, ć, ę, ł, ń, ó, ś, ź, ż), żeby wymowa była naturalna. Po ustawieniu
`language: "en"` wybierz też angielski głos TTS przez `voice_substring` (np.
`Zira`, `David`) lub `edge_voice` (np. `en-US-AriaNeural`).

### Analizy w trakcie wyścigu

- **Strategia paliwowa.** Po kilku okrążeniach asystent zna zużycie i liczy, czy
  paliwa starczy do mety. Jeśli tak — od czasu do czasu potwierdza zapas. Jeśli
  nie — mówi, ile oszczędzać na okrążenie, do którego okrążenia starczy obecnym
  tempem i ile procent zbiornika dotankować na pit stopie. Zapas bezpieczeństwa
  ustawia `fuel_target_margin_laps`.
- **Sekcje opon (auto-uczenie toru).** GT7 nie podaje nazw zakrętów, więc asystent
  dzieli okrążenie na `tyre_sections` równych sekcji wg pokonanego dystansu i uczy
  się, w której sekcji opony osiągają najwyższą temperaturę (ryzyko przegrzania i
  szybszego zużycia). Po pierwszym pełnym okrążeniu zaczyna raportować np. „opony
  najmocniej grzeją się w sekcji 7 z 12, prawa przednia". Działa na dowolnym torze,
  bez konfiguracji. Próg zgłaszania ustawia `tyre_section_temp_warning`.
- **Delta do najlepszego okrążenia.** GT7 nie nadaje gotowej delty, ale w każdym
  pakiecie podaje **pozycję auta w świecie** (x, y, z) — to wystarcza. Asystent
  zapamiętuje najszybsze okrążenie jako referencyjny ślad: listę próbek
  (pozycja + czas od startu). Na bieżącym kółku, dla aktualnej pozycji, znajduje
  najbliższy punkt na śladzie referencyjnym (z rzutem na odcinek dla gładkości) i
  porównuje czasy — podaje, ile **zyskujesz albo tracisz** względem swojego rekordu
  w tym samym fizycznym miejscu toru (np. „0 przecinek 3 sekundy do przodu").
  Porównanie po pozycji nie dryfuje przez okrążenie (w odróżnieniu od całkowania
  prędkości), więc delta nie skacze. Działa na dowolnym torze, bez map. Delta jest czytana **tylko na prostej** (duży gaz, wysoka prędkość, mały
  kąt kierownicy gdy dostępny w formacie `B`/`~`) i najwyżej raz na prostą, żeby nie
  rozpraszać kierowcy w zakrętach. Najlepsza referencja buduje się po pierwszym
  pełnym, czystym okrążeniu. Próg ciszy ustawia `delta_min_seconds`.

### Formaty telemetrii (`telemetry.packet_format`)

GT7 nadaje trzy różne formaty pakietów — wybierasz je bajtem heartbeatu, a
asystent robi to za Ciebie na podstawie tej opcji:

| Format | Rozmiar | Co dodaje |
|---|---|---|
| `A` (domyślny) | 296 B | paliwo, czasy okrążeń, opony, pozycja — wszystko, czego używa inżynier |
| `B` | 316 B | + ruch nadwozia: kąt kierownicy (rad), sygnał FFB, sway / heave / surge |
| `~` | 344 B | jak `B` + **surowy, niefiltrowany gaz i hamulec** (widać działanie TCS/ABS) oraz odzysk energii |

Do obecnych komunikatów głosowych (paliwo, czasy, opony, pozycja) w zupełności
wystarcza `A`. Formaty `B`/`~` przydają się, gdy chcesz logować dodatkową fizykę
albo rozbudować inżyniera np. o wykrywanie blokowania kół (`~`: surowy hamulec
kontra obroty kół). Dodatkowe pola pojawią się w logach przy
`debug.print_telemetry: true` (linie `RUCH` i `SUROWE`).

Uwaga: konsola pamięta pierwszy zamówiony format aż heartbeat wygaśnie. Po zmianie
`packet_format` wyjdź na chwilę z trybu jazdy w GT7, zanim wrócisz na tor.

Źródła formatów (inżynieria wsteczna społeczności): [Nenkai/PDTools #14](https://github.com/Nenkai/PDTools/issues/14),
[GTPlanet — Overview of GT7 Telemetry Software](https://www.gtplanet.net/forum/threads/overview-of-gt7-telemetry-software.418011/).

## Uruchomienie

### Interfejs graficzny (GUI)

Są dwie wersje GUI — obie mają te same cztery zakładki i sterują tym samym
silnikiem (telemetria, inżynier, TTS).

**Wersja ładna (PySide6 / Qt)** — nowoczesna apka desktopowa z ciemnym motywem,
okrągłymi zegarami prędkości i obrotów, paskiem delty i kolorowanymi
temperaturami opon. Wymaga jednej dodatkowej instalacji:

```bash
pip install PySide6
python gt7_gui_qt.py
```

**Wersja bez zależności (Tkinter)** — wbudowana w Pythona, zero instalacji,
prostsza wizualnie. Dobra jako zapas, gdy nie chcesz instalować Qt:

```bash
python gt7_gui.py
```

Obie wersje mają cztery zakładki:

- **Inżynier** — przyciski Start/Stop, status połączenia i log zdarzeń na żywo.
- **Podgląd** — telemetria na żywo: prędkość, bieg, obroty, paliwo, okrążenie,
  pozycja, czasy okrążeń, temperatury opon i delta do najlepszego okrążenia
  (zielona = szybciej, czerwona = wolniej).
- **Ustawienia** — edycja wszystkich opcji z `config.yaml` przez formularz;
  „Zapisz ustawienia" zapisuje plik, zachowując komentarze. Zmiany wchodzą w
  życie po kolejnym Starcie.
- **Test głosów** — odsłuchanie dowolnego komunikatu w wybranym języku (pl/en)
  i silniku (sapi/edge), bez uruchamiania telemetrii.

### Tryb konsolowy

```bash
python main.py
```

Albo z nadpisaniem IP bez edycji configu:

```bash
python main.py --ip 192.168.1.50
```

Wejdź w GT7 do trybu jazdy (wyścig / time trial). Gdy telemetria popłynie,
usłyszysz „Telemetria połączona. Inżynier na łączach." i dalej komunikaty w trakcie jazdy.

Zatrzymanie: `Ctrl+C`.

### Wybór głosu TTS

Wypisz dostępne głosy:

```bash
python main.py --list-voices
```

Skopiuj fragment nazwy interesującego Cię głosu (np. `Paulina`, `Zosia`) do
`speech.voice_substring` w `config.yaml`. Polski głos da poprawną wymowę
komunikatów.

### Głosy neuronowe (edge-tts)

Głosy systemowe SAPI (`engine: sapi`) działają offline, ale brzmią dość
syntetycznie i jest ich mało. Dla znacznie lepszej jakości i dużego wyboru głosów
ustaw `engine: "edge"` — używa darmowych **neuronowych głosów Microsoft** (edge-tts).
Wymaga internetu i kilku pakietów:

```bash
pip install edge-tts sounddevice miniaudio numpy
```

Następnie w `config.yaml`:

```yaml
speech:
  engine: "edge"
  edge_voice: "pl-PL-MarekNeural"   # albo pl-PL-ZofiaNeural, en-US-AriaNeural...
```

Pusty `edge_voice` = głos domyślny dla języka (pl → Marek, en → Aria). Pełną listę
głosów (jest ich mnóstwo, wiele języków) wypiszesz testerem:

```bash
python tools/voice_demo.py --list-edge pl    # tylko polskie
python tools/voice_demo.py --list-edge en    # tylko angielskie
python tools/voice_demo.py --list-edge       # wszystkie
```

Routing na wirtualny kabel (`speech.output_device`) działa tak samo jak dla SAPI,
więc głos neuronowy też trafi do Discorda i na PS5.

### Testowanie głosów i komunikatów

Żeby odsłuchać, jak brzmią poszczególne voice line (i porównać głosy/języki) bez
uruchamiania telemetrii, użyj interaktywnego testera:

```bash
python tools/voice_demo.py
```

Wybierasz język (pl/en), silnik (sapi/edge), ewentualnie konkretny głos, a potem
kategorię komunikatu (paliwo, opony, czasy okrążeń, pozycje…). Tester odtwarza
kilka **losowych wariantów** danego komunikatu, więc słychać całą pulę sformułowań.

## Słuchanie inżyniera na konsoli przez Discord

Telemetria leci **bezpośrednio z PS5 przez sieć LAN** — Remote Play nie jest do
niczego potrzebny. Możesz grać normalnie na konsoli (TV + pad), a asystent na PC
i tak odbiera dane. Problem jest tylko jeden: gdy grasz na konsoli ze słuchawkami,
nie słyszysz głosu z PC. Rozwiązanie — przepuść głos inżyniera przez kanał głosowy
Discorda, do którego dołącza też PS5.

Schemat: **TTS na PC → wirtualny kabel audio → mikrofon Discorda → kanał głosowy →
PS5 (w tym samym kanale) → Twoje słuchawki.**

Krok po kroku:

1. Zainstaluj wirtualny kabel audio — **VB-Audio Virtual Cable**
   (darmowy, [vb-audio.com/Cable](https://vb-audio.com/Cable/)). Pojawią się
   urządzenia `CABLE Input` (wyjście) i `CABLE Output` (wejście).
2. Skieruj głos inżyniera na kabel. Wypisz urządzenia:

   ```bash
   python main.py --list-outputs
   ```

   Skopiuj fragment nazwy kabla (np. `CABLE`) do `speech.output_device`
   w `config.yaml`. Reszta dźwięku PC zostaje na zwykłych głośnikach.
3. W **Discordzie na PC**: *Ustawienia → Głos i wideo → Urządzenie wejściowe* ustaw
   na **CABLE Output**. (Warto wyłączyć redukcję szumów/echa, bo to syntetyczny głos.)
4. Na **PS5** połącz konto Discord (*Ustawienia → Połączone usługi → Discord*),
   dołącz do tego samego kanału głosowego i przenieś rozmowę na konsolę. Inżyniera
   usłyszysz w słuchawkach podpiętych do PS5.

Test: odpal `python tools/simulator.py` w jednym oknie i
`python main.py --ip 127.0.0.1` w drugim — w kanale Discorda powinny iść komunikaty.

## Test bez konsoli (symulator)

Możesz sprawdzić cały tor sygnału bez PlayStation. W jednym terminalu uruchom
symulator telemetrii, w drugim asystenta wskazując na localhost:

```bash
# Terminal 1 — udaje konsolę i nadaje wyścig (paliwo maleje, okrążenia rosną)
python tools/simulator.py

# Terminal 2 — asystent łączy się z symulatorem
python main.py --ip 127.0.0.1
```

Usłyszysz komunikaty o oponie, paliwie i pozycji generowane z syntetycznego wyścigu.

## Testy

```bash
python tests/test_decoder.py
```

Weryfikują: round-trip szyfrowania/parsowania pakietu, odrzucanie błędnych
pakietów, formatowanie komunikatów po polsku oraz eskalację ostrzeżeń o paliwie
i throttling powtarzających się komunikatów.

## Struktura projektu

```
gt7_engineer/
  config.py              # wczytywanie config.yaml
  telemetry/
    decoder.py           # Salsa20 + parsowanie pakietu GT7 (offsety)
    packet.py            # GT7Packet (dataclass z polami telemetrii)
    listener.py          # odbiór UDP + heartbeat
    encoder.py           # budowa/szyfrowanie pakietów (testy + symulator)
  engineer/
    analyzer.py          # logika inżyniera -> komunikaty (Announcement)
    state.py             # stan sesji (paliwo, okrążenia, pozycja)
    tyres.py             # auto-uczenie sekcji toru pod kątem temperatury opon
    delta.py             # delta do najlepszego okrążenia (czytana na prostej)
    messages/            # komunikaty wielojęzyczne (warianty losowane)
      base.py            #   wspólny interfejs Messages
      pl.py              #   polski + formatowanie liczb/czasu pod TTS
      en.py              #   angielski
    messages_pl.py       # zgodność wsteczna -> przekierowanie na messages.pl
  speech/
    speaker.py           # kolejka TTS z priorytetami i anti-spamem (SAPI)
    edge_backend.py      # neuronowe głosy edge-tts (online) + routing audio
main.py                  # spięcie całości (tryb konsolowy)
gt7_gui_qt.py            # ładne GUI (PySide6/Qt): zegary, ciemny motyw, 4 zakładki
gt7_gui.py               # GUI zapasowe (Tkinter, bez zależności): te same 4 zakładki
tools/simulator.py       # symulator telemetrii do testów
tools/voice_demo.py      # interaktywny tester głosów i komunikatów
tests/test_decoder.py    # testy weryfikacyjne
config.yaml              # konfiguracja
```

## Rozwiązywanie problemów

- **Cisza / brak telemetrii** — sprawdź, czy IP konsoli jest poprawne i czy PC i
  PlayStation są w tej samej sieci. GT7 musi być w trybie jazdy (nie w menu).
  Upewnij się, że firewall nie blokuje portu UDP 33740 przychodzącego.
- **Słychać angielski / zła wymowa** — ustaw polski głos przez `voice_substring`
  (patrz „Wybór głosu"). Na Windows możesz doinstalować głos w *Ustawienia →
  Czas i język → Mowa*.
- **Komunikaty się nakładają/powtarzają** — zwiększ `speech.min_gap_seconds`.
- **Chcę widzieć surowe dane** — ustaw `debug.print_telemetry: true`.

## Uwagi techniczne

Format pakietu i schemat szyfrowania pochodzą z publicznej inżynierii wstecznej
interfejsu telemetrii GT7 (pakiet „A", 296 bajtów). Projekt korzysta wyłącznie z
oficjalnie nadawanego przez grę strumienia UDP — nie modyfikuje gry ani konsoli.

## Pomysły na rozbudowę

- Delta do najlepszego okrążenia w czasie rzeczywistym
- Wykrywanie żółtych/czerwonych flag i kolizji
- Dashboard HUD na drugim ekranie
- Sterowanie głosowe („ile mam paliwa?")
- Profile komunikatów per tor/auto

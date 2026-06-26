# Kontekst projektu — GT7 Race Engineer (Sim Racing Strategist)

Dokument przekazania (handoff) dla nowego czatu. Opisuje czym jest projekt, jak
jest zbudowany, jakie są zasady pracy i co zostało ostatnio zrobione.

---

## 1. O co chodzi w projekcie

Budujemy **głosowego inżyniera wyścigowego** w stylu CrewChief dla **Gran Turismo 7**,
napisanego w Pythonie. Aplikacja słucha telemetrii UDP z konsoli/gry, analizuje jazdę
w czasie rzeczywistym i **mówi do kierowcy po polsku** (np. komunikaty o paliwie,
oponach, czasach okrążeń, delcie do najlepszego okrążenia).

Katalog roboczy: `C:\Users\carsb\Documents\claude\Projects\Sim_Racing_Strategist`
Repozytorium: `https://github.com/NikWal09/sim-racing-strategist.git` (branch `main`).

## 2. Zasady pracy (WAŻNE — bezwzględnie przestrzegać)

- **Język polski wszędzie**: wszystkie komentarze w kodzie, komunikaty głosowe i
  dokumentacja muszą być po polsku.
- **Odpowiedzi zwięzłe i konkretne** — bez lania wody, bez zbędnych wyjaśnień.
- **Git push należy do użytkownika.** Środowisko (sandbox) nie ma poświadczeń i
  nie może wypchnąć zmian na GitHub. Nigdy nie udawać, że push się odbył —
  użytkownik robi `git push` sam.
- **Uwaga na nieświeży mount sandboksa**: w tej sesji bash/cp/py_compile/pytest
  potrafiły czytać STARE lub wyzerowane (NUL) wersje plików edytowanych narzędziem
  Edit. Narzędzie **Read jest źródłem prawdy**. Katalog `outputs` (scratchpad)
  propaguje się do basha natychmiast — można go używać do weryfikacji logiki.

## 3. Jak działa telemetria GT7

- GT7 wysyła pakiety UDP szyfrowane **Salsa20**. Formaty: A (296 B), B (316 B),
  ~ (344 B). Brak jawnej flagi pit-stopu.
- Dekoder rozpakowuje pakiet do dataclass **`GT7Packet`**. Kluczowe pola:
  - `position` (x, y, z), `velocity`, `speed_mps`, `speed_kph` (property = mps*3.6)
  - `rpm`, `gear` (0 = luz / N, 15 = wsteczny)
  - `throttle` / `brake` (0–255), `wheel_rotation_rad` (skręt kierownicy, format B/~)
  - `current_fuel`, `fuel_capacity`, `fuel_pct`, `is_electric` (capacity == 100)
  - `current_lap`, `total_laps`, `last_lap_ms`, `best_lap_ms`
  - `tyre_temp` (FL, FR, RL, RR), `car_code`
  - `on_track`, `paused`, `loading`
  - statyczna metoda `format_laptime(ms)` → `"M:SS.mmm"`

## 4. Struktura kodu

```
gt7_engineer/
  config.py            # dataclassy konfiguracji + Config.load(yaml)
  telemetry/
    decoder.py         # deszyfrowanie Salsa20 + parsowanie pakietu
    encoder.py         # (do symulatora/testów)
    listener.py        # nasłuch UDP
    packet.py          # dataclass GT7Packet
  engineer/
    state.py           # stan przejazdu
    analyzer.py        # analiza okrążeń (wzorzec segmentacji okrążeń)
    corners.py         # detekcja zakrętów
    delta.py           # delta do najlepszego okrążenia
    tyres.py           # logika opon
    recorder.py        # NOWY moduł: nagrywanie telemetrii per okrążenie
    messages/          # komunikaty (base.py, pl.py, en.py)
    messages_pl.py     # polskie komunikaty głosowe
  speech/
    speaker.py         # warstwa mowy
    edge_backend.py    # backend TTS (Edge)
    sound.py
main.py                # uruchomienie CLI (pętla odbioru pakietów)
gt7_gui_qt.py          # GŁÓWNY runtime: GUI PySide6/Qt (EngineerWorker QThread)
gt7_gui.py             # starsze GUI
kalkulator.py
config.yaml            # konfiguracja użytkownika
tools/
  simulator.py         # symulator pakietów do testów
  diagnose.py
  voice_demo.py
  telemetry_viewer.py  # NOWY: generator samodzielnej strony HTML do podglądu nagrań
tests/
  test_decoder.py
  test_recorder.py     # NOWY: testy nagrywania
recordings/            # nagrania telemetrii (ignorowane w gicie)
```

Zarówno `main.py` (CLI) jak i `gt7_gui_qt.py` (GUI, główny runtime) w pętli odbioru
wołają `engineer.update(packet)`.

## 5. Ostatnio dodana funkcja — system nagrywania telemetrii (styl Garage 61)

Cel (cytat użytkownika): „podczas jazdy zapisuje ci się auto którym jedziesz tor
oraz wszystkie dane typu gaz hamulec ilość skrętu kierownicy pozycja by zobaczyć
nitkę na torze itp ... odtworzyć na aplikacji albo na stronie internetowej taką
telemetrię."

Trzy zatwierdzone decyzje projektowe:
1. **Strona HTML** — podgląd/odtwarzanie przez samodzielny plik HTML (mapa toru +
   wykresy gaz/hamulec/kierownica/prędkość).
2. **Automatycznie każde okrążenie** — nagrywanie automatyczne, jeden plik na
   ukończone okrążenie; zapisuje auto + tor + wszystkie kanały.
3. **Auto-grupowanie po śladzie** — liczony „fingerprint" toru i automatyczne
   grupowanie okrążeń z tego samego toru do porównań.

### 5a. `gt7_engineer/engineer/recorder.py` (rdzeń funkcji)

- `CHANNELS = ["t","x","y","z","speed_kph","throttle","brake","steering","gear","rpm"]`
- Klasa **`TelemetryRecorder`**, metoda `update(p: GT7Packet) -> str | None`
  (zwraca ścieżkę zapisanego pliku albo None).
- Segmentacja okrążeń (wzorowana na `analyzer.py`):
  - ukończenie okrążenia przy wzroście `current_lap`,
  - powrót do boksu wykrywany po skoku paliwa (`current_fuel > last + 0.05`) przy
    `speed_kph <= 5.0` → unieważnia bufor (`_invalidate("pit")`),
  - cofnięcie `current_lap` → odrzucenie bufora,
  - flaga `clean` — bufor zaczął się dokładnie na linii start/meta.
- `_sample` próbkuje z `sample_hz` (domyślnie 20 Hz), zapis `throttle/255`,
  `brake/255`, `wheel_rotation_rad`.
- `_is_saveable`: wymaga `clean`, `last_lap_ms > 0`, ≥2 próbek,
  `last_lap_ms >= min_lap_seconds*1000`.
- `_fingerprint(samples)` → `{length_m, width_m, height_m}` (płaszczyzna x-z).
- `_track_key(fp)` → `f"L{round(len/50)*50}-W{round(w/20)*20}-H{round(h/20)*20}"`.
- `_save_lap` zapisuje JSON `{session_id, car_code, lap_number, lap_ms, lap_time,
  recorded_at, track_key, fingerprint, sample_hz, channels, samples}`,
  nazwa pliku `{session_id}_{track_key}_lap{NNN}_{ms}ms.json`.

### 5b. Konfiguracja

`config.py` — dodano dataclass `RecordingConfig(enabled=True, output_dir="recordings",
sample_hz=20.0, min_lap_seconds=10.0)`, pole `recording` w `Config` oraz wczytanie w
`Config.load`. `config.yaml` ma sekcję `recording:` z polskimi komentarzami.

### 5c. Integracja runtime

- `gt7_gui_qt.py`: import `TelemetryRecorder`, instancja z
  `base_dir=os.path.dirname(os.path.abspath(__file__))`, po pętli komunikatów
  `saved = recorder.update(packet)` i emit `[NAGRYWANIE] Zapisano okrazenie: ...`.
- `main.py`: analogicznie, log przy `cfg.debug.log_events`.
- `.gitignore`: dodano `recordings/`.

### 5d. Viewer — `tools/telemetry_viewer.py`

- `load_laps(dir)` — wczytuje `*.json` (pomija pliki na „_"), sortuje po
  (track_key, lap_ms).
- `build_html(laps)` — podmienia `/*__DATA__*/` w `_TEMPLATE` na `json.dumps(laps)`.
- CLI: `--recordings` (domyślnie `recordings`), `--out`
  (domyślnie `<recordings>/telemetria.html`).
- `_TEMPLATE` to samodzielny HTML/JS (vanilla canvas, bez CDN, działa offline przez
  `file://`). Grupowanie torów **tolerancyjne** (klastrowanie, nie dokładny klucz):
  rel. długość < 0.03, szer./wys. < 0.07. Mapa toru kolorowana prędkością
  (hsl 220→0), wykresy kanałów względem ułamka dystansu, porównanie wielu okrążeń.
  - **Uwaga**: grupowanie świadomie tolerancyjne, bo twarde binowanie `track_key`
    pęka na granicach kwantyzacji (okrążenie o długości dokładnie na granicy 50 m
    przeskakuje między `L1200`/`L1250`).

### 5e. Testy — `tests/test_recorder.py`

Sterowalny `Clock`, builder `pkt(...)`, generator `_loop_points` (okrąg = zamknięta
pętla). Testy: out-lap niezapisany → potem mierzone okrążenie zapisane; determinizm
i rozróżnialność fingerprintu; unieważnienie przy powrocie do boksu; odrzucenie zbyt
krótkiego okrążenia; recorder wyłączony = nic nie robi; viewer buduje HTML.

Uruchomienie: `python tests\test_recorder.py` albo `python -m pytest tests/`.
W projekcie **nie ma** `conftest.py`/`pytest.ini` — pliki testów same dodają
bootstrap `sys.path.insert(0, <root>)` na górze (jak `test_decoder.py`).

## 5f. Zakładka „Nagrania" w GUI (2026-06-11)

`gt7_gui_qt.py` ma piątą zakładkę **Nagrania** spinającą recorder z viewerem:
- tabela nagranych okrążeń (tor / okr. / czas / auto / data / plik), sortowalna,
  zaznaczanie wielu wierszy; dane z `tools.telemetry_viewer.load_laps`,
- przycisk „Generuj i otwórz podgląd HTML" → `build_html` → zapis
  `recordings/telemetria.html` → otwarcie w przeglądarce (`QDesktopServices`),
- „Usuń zaznaczone" z potwierdzeniem, „Odśwież",
- auto-odświeżanie tabeli po zapisie okrążenia (hook w `_append_log` na
  prefiks `[NAGRYWANIE]`),
- katalog nagrań z `cfg.recording.output_dir` (względny = względem projektu).

## 5g. Nazwy aut GT7 (2026-06-11)

- `gt7_engineer/data/` — nowy pakiet: `gt7_cars.csv` (575 aut, kolumny code,name,
  źródło: baza ddm999/gt7info — ID z telemetrii + producent + model) oraz
  `car_name(code) -> str` (cache w pamięci, fallback `"Auto <kod>"`).
- Recorder zapisuje pole `car_name` w JSON-ie nagrania; `load_laps` w viewerze
  dokłada nazwę starszym nagraniom bez tego pola. GUI (tabela Nagrań) i viewer
  HTML pokazują nazwę zamiast kodu (np. 3334 → "Audi R18 '16").

## 5h. Okrążenie referencyjne (2026-06-11)

- `gt7_engineer/engineer/reference.py` — `ReferenceDelta(DeltaTracker)`:
  referencja wczytywana z PLIKU nagrania (`load(path)` → `ReferenceInfo`),
  nigdy nie nadpisywana najszybszym kółkiem; ślad przepróbkowany do ≥5 m
  (`RESAMPLE_M`); `reset()` ZACHOWUJE ref (kasuje tylko `clear()`), więc
  **zmiana auta nie usuwa referencji** — scenariusz „porównaj 2 pojazdy na
  tym samym torze" działa wprost (delta jest pozycyjna).
- Sektory: ślad dzielony na `ref_sectors` (domyślnie 3) równych czasowo;
  przekroczenie granicy → `pop_sector_result()` = (nr, zmiana delty w sektorze);
  ostatni sektor domykany w `on_lap_complete`. Komunikaty `ref_sector_loss/gain`
  w base/pl/en („tracisz pół sekundy w sektorze 2").
- `RaceEngineer`: pole `ref_delta`, metody `set_reference(path)` /
  `clear_reference()`, lustrzane wywołania start_lap/update/on_lap_complete
  obok zwykłej delty, `_check_ref_sectors` (próg `ref_sector_min_seconds`).
- Config: `announce_ref_sectors`, `ref_sectors`, `ref_sector_min_seconds`
  (EngineerConfig + config.yaml + SETTINGS_SCHEMA w GUI).
- GUI: w Nagraniach przyciski „Ustaw jako referencje" (1 zaznaczone nagranie,
  walidacja od razu) / „Wyczysc referencje" + etykieta; zmiana w locie przez
  `EngineerWorker.set_reference` (lista `_ref_changes` zdejmowana w pętli —
  bezpieczne pod GIL); w Podglądzie sekcja DELTA REF (widoczna gdy ustawiona).

## 5i. Analiza opon (2026-06-11)

- Recorder: `CHANNELS` rozszerzone NA KOŃCU o `tyre_fl/fr/rl/rr` — starsze
  nagrania ich nie mają, odbiorcy szukają kanału po nazwie.
- `tools/tyre_report.py` — `build_report_html(laps)`: offline detekcja zakrętów
  ze śladu (heurystyka jak CornerTracker: yaw ≥14°/s wejście, <7°/s wyjście),
  per tor: tabela okrążeń (śr./max per opona), wykres trendu SVG, tabela
  zakrętów (śr./max szczyt, dominująca opona, trend 1. vs 2. połowa sesji).
  Stare nagrania bez kanałów opon pomijane z adnotacją. CLI jak viewer.
  GUI: przycisk „Raport opon" → `recordings/raport_opon.html`.
- Testy: `tests/test_reference.py` (9 testów: resampling, delta ≈0 przy tym
  samym tempie, sektory przy wolniejszym, przeżycie reset/clear, walidacja
  pliku, car_name, kanały opon, raport HTML, pomijanie starych nagrań).

## 5j. Viewer: analiza fragmentu toru, styl Garage 61 (2026-06-11)

Przebudowa JS w `tools/telemetry_viewer.py` (Python API bez zmian):
- **Osobne wykresy**: Prędkość, Gaz [%], Hamulec [%], Bieg, Obroty [RPM],
  Kierownica — zamiast wspólnego „Gaz / Hamulec".
- **Fragment toru**: globalny zakres `view = {a, b}` (ułamek dystansu okrążenia);
  przeciągnięcie myszką po dowolnym wykresie (`attachSelect`, półprzezroczysta
  nakładka podczas drag) → `setView` → wszystkie wykresy przybliżają zakres
  (clip na krawędzi, oś X mapowana przez `(f - a)/(b - a)`).
- **Pasek widoku** (`.viewbar`): „Cale okrazenie" + przyciski S1/S2/S3 (tercje);
  aktywny przycisk podświetlony; `setTrack` resetuje zakres.
- **Mapa**: przy zawężonym widoku cały tor przygaszony (#3a4150), wybrany
  fragment w kolorze (prędkość/kolor okrążenia); skala kolorów prędkości
  liczona tylko z fragmentu.
- **Czas fragmentu** per zaznaczone okrążenie (`segTime` z kanału t, format
  `fmtTime` m:ss.mmm) w pasku widoku.
- Rejestr `CHARTS` + `drawAllCharts` (resize/overlay przerysowują wszystko).
- Testy: harness node z atrapą DOM (Proxy-canvas) na realnych nagraniach —
  15/15 PASS (sektory, drag, suma czasów sektorów ≈ czas okrążenia, formaty).

## 5k. Viewer: delta + kursor; raport opon per auto (2026-06-11)

Viewer (`tools/telemetry_viewer.py`, JS w _TEMPLATE):
- **Wykres delty** (`cDelta`, widoczny przy ≥2 zaznaczonych okrążeniach):
  referencja = najszybsze z zaznaczonych (`fastestSelected`); dla każdego
  okrążenia `l._delta[j] = t(j) - tAtFrac(ref, frakcja_dystansu)`; oś
  symetryczna ±dmax, linia zero; referencja rysowana jako 0.
- **Kursor zsynchronizowany** (jak G61): najechanie na dowolny wykres →
  `cursorF` (ułamek dystansu) → pionowa linia na WSZYSTKICH wykresach,
  plakietki z wartością każdego okrążenia (interpolacja `valueAt` po
  dystansie, format per wykres przez `opts.cursorFmt`: km/h, %, bieg, rpm,
  kierownica w stopniach L/P, delta ±s), dystans w metrach na dole oraz
  znacznik pozycji auta na mapie (`posAtFrac`). Przerysowanie przez rAF
  (`scheduleRedraw`); drag (zaznaczanie fragmentu) nadal działa —
  mousedown zeruje kursor, mouseleave czyści.
- Helpery: `locAt` (binary search po _dist), `valueAt`, `tAtFrac`, `posAtFrac`.

Raport opon (`tools/tyre_report.py`):
- W obrębie toru okrążenia grupowane PO AUCIE: każde auto ma własną sekcję
  (tabela okrążeń bez kolumny Auto, własny wykres SVG, własna tabela zakrętów —
  numeracja zakrętów nie miesza się między autami).
- Przy >1 aucie na torze: tabela „Porównanie aut — które najmocniej przegrzewa
  opony" (śr./max szczytu okrążenia, dominująca opona), posortowana malejąco,
  najgorętsze auto podświetlone + werdykt w nocie.
- Testy: pytest 25/26 (znany stary FAIL), test syntetyczny 2 aut (Mazda
  cieplejsza → 1. miejsce, 2 wykresy SVG), harness node 12/12 PASS
  (delta ref=0, delta na mecie ≈ różnica czasów, kursor, interpolacja).

## 5l. Mniej gadania o paliwie + fix średniej po pit + lifting GUI (2026-06-12)

Logika paliwa (`analyzer.py`, feedback użytkownika po wyścigu):
- **BUG naprawiony**: po pit stopie średnia spalania nagle spadała — okrążenie
  z tankowaniem wnosiło do historii NIEPEŁNĄ próbkę (zużycie liczone tylko od
  pitu do linii). Flaga `_fuel_lap_invalid` (ustawiana przy: tankowaniu,
  wjeździe z menu, resecie licznika okrążeń) pomija taką próbkę.
- **Limit komunikatów**: `fuel_max_messages_per_lap` (domyślnie 1) — kandydaci
  zbierani razem i sortowani po Priority (IntEnum, mniejsze = ważniejsze,
  sort stabilny), emitowane tylko top-N. 0 = paliwo wyciszone.
- **Filtry**: `fuel_runs_out` tylko gdy `last_full_lap < total_laps` (bez
  „starczy do okr. 15" w 15-okrążeniowym wyścigu); `fuel_ok_to_finish` za
  flagą `announce_fuel_ok_to_finish` (domyślnie False — gdy dobrze, milczy).
- **Diagnostyka**: `pop_fuel_debug()` → linie `[PALIWO]` (zużycie, okno,
  średnia, pominięte próbki) emitowane TYLKO do logu GUI/CLI (nie do głosu).
- Config/yaml/SETTINGS_SCHEMA rozszerzone; testy `tests/test_fuel.py`
  (7 testów); w `test_decoder.py` dwa testy strategii zaktualizowane do
  nowych domyślnych (enough → flaga włączona; save → limit 3).

Recorder/viewer: nowy kanał `fuel_pct` (na końcu CHANNELS); w viewerze
warunkowy wykres „Paliwo [%] (diagnostyka spalania)" (`selHas('fuel_pct')`,
oś Y dociśnięta do zakresu — widać zużycie w kółku i skok po tankowaniu).

GUI lifting (subtelny): nowy QSS (zakładki z akcentem dolnym, gradientowe
przyciski/kafelki, stylowana tabela + scrollbary, checkboxy), `CircularGauge`
z podziałką (9 kresek) i opcjonalną czerwoną strefą `redline_frac` (RPM 0.88;
wartość czerwienieje w strefie), okno 940x660, tabela nagrań z naprzemiennymi
wierszami.

## 6. Stan na teraz (2026-06-11)

- Cały kod funkcji nagrywania (recorder, config, config.yaml, viewer, integracja
  GUI/CLI, .gitignore) jest **gotowy i zweryfikowany**.
- Sesja 2026-06-11 (cd.): zakładka Nagrania (5a–5f), nazwy aut (5g), okrążenie
  referencyjne (5h), analiza opon (5i). Testy: 25/26 PASS (pytest, kopia w
  outputs/verify — mount bywał nieświeży, prefiks bajt-w-bajt zgodny z realnymi
  plikami); jedyny FAIL to znany, wcześniejszy `test_message_helpers`.
- Uwaga dla main.py (CLI): nie ma jeszcze obsługi referencji (tylko GUI ją
  ustawia); ewentualne `--reference <plik>` to drobny przyszły dodatek.
- Logika recordera: 12/12 inline-checków PASS przeciw żywemu modułowi.
- JS viewera: 5/5 PASS w harnessie node z atrapą DOM.
- Ostatnia naprawa: do `tests/test_recorder.py` dodano brakujący bootstrap
  `sys.path.insert`, więc `python tests\test_recorder.py` już działa.
- **Do zrobienia przez użytkownika**: `git push` na GitHub (sandbox nie pushuje).
- Znana, **niezwiązana** z tą funkcją usterka: `test_decoder.py::test_message_helpers`
  (`okrazenie` vs `okrążenie` — oczekiwanie polskiego diakrytyku). Nie ruszane.

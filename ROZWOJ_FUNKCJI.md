# GT7 Race Engineer — propozycje rozwoju aplikacji

Dokument zbiera funkcje, których aplikacja jeszcze **nie posiada**, a które w narzędziu typu
„inżynier wyścigowy" są praktycznie obowiązkowe. Punktem startowym jest **kalkulator stintu
paliwo + opony** (sekcja 1, rozpisana szczegółowo). Pozostałe pomysły są opisane skrótowo jako
backlog z oznaczeniem Free/Pro i szacunkiem złożoności.

Wszystkie komentarze, komunikaty głosowe i teksty UI pozostają **po polsku (z diakrytykami)**.

---

## Co już mamy (żeby nie dublować)

- Głosowy inżynier na żywo (`race_engineer.dart`) — w tym **reaktywna logika paliwa**: średnie
  zużycie z okna okrążeń (`fuelAvgWindow`), `lapsLeft`, ostrzeżenia `fuelWarning`/`fuelCritical`,
  oraz `_fuelStrategy` (ile dolać %, oszczędzanie na okrążenie, „starczy do mety").
- Nagrywanie telemetrii okrążeń + porównanie + **DELTA REF** (referencja z własnego lub cudzego lapa).
- Raport opon i podgląd telemetrii (HTML), edytor dashboardu (warianty, skórki, presety).
- Konta (rejestracja, weryfikacja e-mail, ustawienia, zmiana hasła), i18n PL/EN, motywy, jednostki
  metryczne/imperialne, udostępnianie i import nagrań.

**Wniosek:** paliwo jest dziś liczone **reaktywnie i tylko głosem podczas sesji**. Brakuje
**interaktywnego planera stintu** (z ręcznymi wejściami i podglądem liczb) oraz **strony opon**.

---

## Priorytety (kolejność wdrażania)

1. **Kalkulator stintu paliwo + opony** — najsilniejszy argument za Pro, rozwija to, co już liczymy.
2. **Czasy sektorów + teoretyczny najlepszy okrążenie** — fundament pod coaching i historię.
3. **Auto-wykrywanie konsoli w sieci LAN** — najmocniej obniża próg wejścia dla nowych użytkowników.

---

## 1. Kalkulator stintu — paliwo + opony  *(start tutaj)*

### Cel

Dać kierowcy **jeden ekran**, który odpowiada na pytania: „Czy dojadę do mety?", „Ile dolać na
pit stopie?", „Kiedy wjechać do boksu?", „Na ile okrążeń wystarczą opony?". Dwa tryby:

- **Auto (z sesji)** — dane brane na żywo z telemetrii (paliwo mierzone, nie szacowane).
- **Ręczny (planowanie)** — użytkownik wpisuje: długość wyścigu, paliwo na okrążenie, pojemność
  zbiornika, tempo degradacji opon — i widzi wynik przed startem.

### Co już istnieje i co reużywamy

| Element | Gdzie | Status |
|---|---|---|
| Średnie zużycie paliwa / okno | `engineer_config.dart` (`fuelAvgWindow`), `race_engineer.dart` | reuse |
| `lapsLeft`, refuel %, „starczy do mety" | `race_engineer.dart` `_fuelStrategy` | **wyciągnąć do czystej klasy** |
| Pojemność i poziom paliwa | `gt7_packet.dart` (`fuelCapacity`, `currentFuel`, `fuelPct`) | reuse |
| Temperatury i promień opon | `gt7_packet.dart` (`tyreTemp[4]`, `tyreRadius[4]`) | reuse (patrz uwaga o oponach) |
| Komunikaty głosowe paliwa | `messages_pl.dart` (`M.fuel*`) | rozszerzyć o stint/box |

### Krok 1 — wydzielić logikę paliwa do czystej klasy (refaktor)

Dziś matematyka paliwa siedzi wewnątrz `RaceEngineer`. Przenieść rdzeń obliczeń do osobnej,
bezstanowej klasy, żeby używał jej zarówno żywy inżynier, jak i nowy ekran kalkulatora.

```dart
// lib/engineer/stint_calculator.dart

/// Wejście do kalkulatora stintu (paliwo). Wartości pochodzą z sesji lub od użytkownika.
class FuelInput {
  final double tankL;          // pojemność zbiornika (z fuelCapacity lub ręcznie)
  final double currentL;       // aktualne paliwo (currentFuel) lub na starcie stintu
  final double perLapL;        // średnie zużycie na okrążenie (z fuelAvgWindow)
  final int lapsRemaining;     // ile okrążeń do końca wyścigu
  const FuelInput({
    required this.tankL, required this.currentL,
    required this.perLapL, required this.lapsRemaining,
  });
}

/// Wynik kalkulacji paliwa.
class FuelPlan {
  final double lapsLeftOnFuel;   // ile okrążeń przejedziemy na obecnym paliwie
  final double deficitL;         // brakujące paliwo do mety (0 jeśli starczy)
  final double refuelL;          // ile dolać, żeby dojechać (+margines)
  final double savePerLapL;      // ile oszczędzać/okrążenie, by dojechać bez pit stopu
  final bool finishesWithoutPit; // czy dojedzie bez tankowania
  const FuelPlan(this.lapsLeftOnFuel, this.deficitL, this.refuelL,
      this.savePerLapL, this.finishesWithoutPit);
}

class StintCalculator {
  /// Margines bezpieczeństwa w okrążeniach (np. 0.5 okrążenia rezerwy).
  static FuelPlan fuel(FuelInput i, {double marginLaps = 0.5}) {
    final lapsLeftOnFuel = i.perLapL > 0 ? i.currentL / i.perLapL : 0.0;
    final neededL = (i.lapsRemaining + marginLaps) * i.perLapL;
    final deficitL = (neededL - i.currentL).clamp(0.0, double.infinity);
    final refuelL = deficitL > 0 ? (deficitL).clamp(0.0, i.tankL) : 0.0;
    final finishes = deficitL <= 0;
    // ile oszczędzać/okrążenie, by dociągnąć bez tankowania
    final savePerLapL = (!finishes && i.lapsRemaining > 0)
        ? (neededL - i.currentL) / i.lapsRemaining
        : 0.0;
    return FuelPlan(lapsLeftOnFuel, deficitL, refuelL, savePerLapL, finishes);
  }
}
```

> Następnie `RaceEngineer._fuelStrategy` woła `StintCalculator.fuel(...)` zamiast liczyć inline —
> jedno źródło prawdy, zero rozjazdu między głosem a ekranem.

### Krok 2 — opony (uwaga o ograniczeniu GT7)

GT7 **nie udostępnia bezpośrednio zużycia opon w %** w pakiecie UDP. Mamy tylko `tyreTemp[4]` i
`tyreRadius[4]`. Dlatego strona opon jest **szacunkowa**, w przeciwieństwie do paliwa (mierzonego
dokładnie). Dwa praktyczne podejścia, oba do wdrożenia:

1. **Model liczbą okrążeń + tempo degradacji** — użytkownik (lub preset opony) podaje „na ile
   okrążeń starcza komplet" i krzywą spadku; liczymy `oponaLeft = startLaps - okrążeniaNaOponie`.
2. **Sygnał z telemetrii** — trend `tyreRadius` (lekko maleje z zużyciem) oraz utrzymujące się
   wysokie `tyreTemp` jako wskaźnik nadmiernego zużycia/przegrzania. Traktować jako alarm, nie
   dokładny licznik.

```dart
/// Szacunkowy stan opon (GT7 nie daje wprost zużycia %).
class TyreInput {
  final int lapsOnSet;       // ile okrążeń na obecnym komplecie
  final int estLifeLaps;     // szacowana żywotność (preset/ustawienie użytkownika)
  final List<double> tempC;  // FL, FR, RL, RR
  const TyreInput({required this.lapsOnSet, required this.estLifeLaps, required this.tempC});
}

class TyrePlan {
  final double lifeLeftFrac;  // 0..1 pozostała "żywotność"
  final int lapsLeftEst;      // szacowane pozostałe okrążenia
  final bool overheating;     // któraś opona poza oknem temperatur
  const TyrePlan(this.lifeLeftFrac, this.lapsLeftEst, this.overheating);
}
```

### Krok 3 — komunikaty głosowe (rozszerzyć `messages_pl.dart`)

Dodać warianty zgodne ze stylem istniejących `M.fuel*`, np.:

- „Boks to okrążenie — dolewamy {n} litrów." (`Priority.high`, klucz `box`)
- „Opona przednia lewa zużyta, zostały {n} okrążenia." (`Priority.normal`)
- „Plan: jeden pit stop, okno {a}–{b} okrążenie." (`Priority.low`)

Każdy przez istniejący mechanizm `Announcement` + kolejkę/`minGap`, więc bez nowej infrastruktury.

### Krok 4 — UI

- **Nowa zakładka „Stint"** (albo karta w zakładce inżyniera) z dwoma trybami (Auto / Ręczny).
- Pola wejściowe (ręczny tryb), a w trybie auto te same liczby wypełniane z sesji na żywo.
- Duże, czytelne wyniki: „Paliwo: starczy / brakuje X l", „Dolej: Y l", „Oszczędzaj: Z l/okr",
  „Opony: ~N okrążeń", pasek żywotności.
- Opcjonalnie: **widżet dashboardu** „Plan stintu" (reużywa `StintCalculator`).

### Krok 5 — persystencja baseline (opcjonalnie, Pro)

Zapisywać średnie zużycie i żywotność opon **per auto + tor** (analogicznie do `RecordingStore`,
JSON w katalogu dokumentów), żeby tryb ręczny podpowiadał realne wartości z historii.

### Podział Free / Pro

- **Free:** podstawowy kalkulator paliwa (tryb ręczny + auto), proste „starczy / nie starczy / dolej".
- **Pro:** strona opon, planer pit stopów, zapis baseline per auto+tor, komunikaty „box this lap".

### Checklista wdrożenia (sekcja 1)

- [ ] `lib/engineer/stint_calculator.dart` — `FuelInput`/`FuelPlan`/`StintCalculator.fuel`.
- [ ] Refaktor `RaceEngineer._fuelStrategy` → woła `StintCalculator`.
- [ ] `TyreInput`/`TyrePlan` + prosty model degradacji.
- [ ] Nowe komunikaty w `messages_pl.dart` (box, opony, plan).
- [ ] Ekran/zakładka „Stint" (tryb Auto + Ręczny) + klucze i18n (PL/EN).
- [ ] (Pro) baseline per auto+tor w osobnym magazynie JSON.
- [ ] Testy logiki: weryfikacja wzorów na kilku scenariuszach (starcza/brakuje/granica).

---

## 2. Backlog — pozostałe funkcje (skrót)

> Format: **cel** · *dane* · Free/Pro · złożoność (S/M/L).

### Wydajność i coaching

- **Czasy sektorów + teoretyczny best.** Split na 3 sektory, „optimal lap" z najlepszych sektorów,
  oznaczanie zielony/fioletowy. · *pozycja x/z + czas z telemetrii* · Free (podstawa) / Pro (historia) · **M**
- **Analiza „gdzie tracisz czas" vs referencja.** Zakręt po zakręcie: punkt hamowania, dodanie gazu,
  prędkość minimalna względem lapa referencyjnego. · *istniejące nagrania + DELTA REF* · Pro · **L**
- **Mapa toru z kolorem delty.** Minimapa linii toru pokolorowana zyskiem/stratą czasu. · *x/z + delta* · Pro · **M**

### Dane i historia

- **Historia czasów + wskaźnik powtarzalności.** Trend okrążeń między sesjami, personal best
  per tor+auto, odchylenie standardowe jako „consistency". · *nagrania* · Free (podstawa) / Pro (pełna) · **M**
- **Garaż / notatki setupu.** Zapis ustawień per tor+auto (ciśnienia, przełożenia, zawieszenie) +
  notatki tekstowe. · *wpisy użytkownika* · Free · **S**
- **Backup nagrań w chmurze + sync między urządzeniami.** Telemetria lokalnie, opcjonalny backup. · *Firebase/Storage* · Pro · **L**

### UX i połączenie

- **Auto-wykrywanie konsoli w LAN.** Skan sieci zamiast ręcznego IP + kreator połączenia. · *UDP broadcast* · Free · **M**
- **Praca w tle / przy zgaszonym ekranie.** Inżynier mówi dalej po zminimalizowaniu apki
  (foreground service / powiadomienie). · *Android service* · Free · **M**

### Głos i alerty

- **Konfigurowalne alerty głosowe.** Progi temperatur opon/paliwa/degradacji, suwak „gadatliwości",
  wybór głosu. · *istniejący `EngineerConfig` + TTS* · Free (podstawa) / Pro (pełna personalizacja) · **S/M**
- **Świadomość pogody/nawierzchni.** Ostrzeżenie o deszczu i sugestia zmiany opon — **jeśli** pakiet
  GT7 to udostępnia (do weryfikacji w dekoderze). · *telemetria* · Pro · **M**

---

## Sugerowana mapa drogowa

1. **Sekcja 1** — kalkulator stintu (paliwo najpierw, potem opony). Refaktor logiki paliwa do
   `StintCalculator` daje natychmiastową wartość i porządkuje obecny kod.
2. **Sektory + teoretyczny best** — odblokowuje coaching i sensowną historię.
3. **Auto-discovery LAN + praca w tle** — komfort dla każdego użytkownika, niski koszt, duży efekt.
4. Dalej wg potrzeb: analiza strat / mapa delty / garaż setupów / backup w chmurze.

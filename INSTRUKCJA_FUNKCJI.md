# GT7 Race Engineer — instrukcja obsługi nowych funkcji

Praktyczny przewodnik po funkcjach dodanych ostatnio: automatyczne wykrywanie
konsoli, kalkulator paliwa (stint), strategia opon (pomiar tempa + ranking) oraz
udostępnianie i porównywanie nagrań.

Zakładki wybierasz z bocznego menu (ikona ☰ w rogu).

---

## 1. Połączenie z konsolą — „Znajdź konsolę"

**Po co:** zamiast ręcznie wpisywać adres IP PlayStation, aplikacja sama go znajdzie w sieci.

**Zanim zaczniesz — warunki konieczne:**
- Telefon i PlayStation w **tej samej sieci Wi-Fi**.
- **GT7 uruchomione i „na torze"** (jazda albo powtórka) — w menu gry konsola nie wysyła telemetrii i nic się nie znajdzie.

**Kroki:**
1. Wejdź w zakładkę **Inżynier**.
2. Naciśnij **„Znajdź konsolę"** (obok „Start (PS5)"). Pojawi się kręciołek — trwa skanowanie sieci (~1–3 s).
3. Po znalezieniu aplikacja zapisze adres IP konsoli i od razu się połączy. Status zmieni się na „Nasłuch… / Odbieram dane".
4. Adres jest **zapamiętany** — przy następnym razie najpierw próbowany jest zapisany, więc kolejne łączenie jest błyskawiczne.

**Jeśli nie znajdzie** („Nie znaleziono konsoli. Uruchom GT7 i wjedź na tor."):
- Upewnij się, że jedziesz w GT7 (nie jesteś w menu/pauzie).
- Sprawdź, że telefon jest na Wi-Fi (nie na danych komórkowych).
- Niektóre routery mają „izolację klientów" (AP isolation), która blokuje połączenia między urządzeniami — wtedy użyj **ręcznego wpisania IP** (pole w ustawieniach) jako rozwiązania zastępczego.
- Na iPhone przy pierwszym skanie pojawi się systemowe pytanie o dostęp do sieci lokalnej — trzeba zezwolić.

---

## 2. Kalkulator stintu — paliwo

**Po co:** odpowiada na pytania „czy dojadę do mety?", „ile dolać na pit stopie?", „ile oszczędzać na okrążenie?".

Wejdź w zakładkę **Stint** → sekcja **Paliwo**. Masz dwa tryby (przełącznik u góry):

### Tryb „Z sesji" (na żywo)
Działa, gdy jesteś połączony z GT7 i przejechałeś co najmniej 1–2 okrążenia (apka musi zmierzyć zużycie).
1. Połącz się z konsolą i jedź.
2. Wartości (paliwo, zużycie/okrążenie, okrążenia do mety) wypełniają się **automatycznie** z telemetrii.
3. Wynik aktualizuje się na bieżąco.

Jeśli widzisz „Brak danych z sesji" — albo nie jedziesz, albo auto nie ma paliwa (elektryczne), albo za mało okrążeń. Wtedy użyj trybu ręcznego.

### Tryb „Ręcznie" (planowanie)
Do liczenia przed wyścigiem.
1. Wpisz: **Pojemność zbiornika** (l), **Aktualne paliwo** (l), **Zużycie / okrążenie** (l), **Okrążenia do mety**, **Margines** (zapas bezpieczeństwa w okrążeniach, domyślnie 0.5).
2. Wynik pojawia się od razu pod spodem.

### Jak czytać wynik
- **Zielona karta „Starczy do mety"** + **Zapas** (ile okrążeń paliwa w zapasie).
- **Czerwona karta „Brakuje paliwa"**:
  - **Dolej na pit stopie** — ile litrów (i % zbiornika) dolać, żeby dojechać.
  - **Oszczędzaj / okrążenie** — ile mniej palić na okrążenie, żeby dociągnąć **bez** pit stopu (jeśli się da).
- **Na obecnym paliwie** — na ile okrążeń starczy to, co masz teraz.

> Wskazówka: liczby kropki/przecinka są akceptowane (np. `3.0` lub `3,0`).

---

## 3. Strategia opon

Wejdź w zakładkę **Stint** → sekcja **Strategia opon**. Składa się z dwóch części: **pomiaru tempa** (uczenie z jazdy) i **rankingu strategii** (porównanie wariantów).

### 3a. Pomiar tempa (na żywo)
Aplikacja sama uczy się, jakie masz tempo i jak szybko spadają opony na danej mieszance.
1. Połącz się z GT7.
2. W karcie **„Pomiar tempa"** wybierz **Mieszankę**, na której właśnie jedziesz.
3. Naciśnij **„Nowe opony"** w momencie założenia świeżego kompletu — to zeruje licznik wieku opon.
4. Jedź. Pod spodem pojawi się **Pomiar**: tempo na świeżej oponie, degradacja (s na okrążenie) i liczba zebranych okrążeń. Im więcej okrążeń, tym dokładniej.

> Uwaga: GT7 nie podaje zużycia opon ani nazwy mieszanki, więc mieszankę wskazujesz Ty. Tempo i degradację apka mierzy z czasów okrążeń; **żywotność** (ile mieszanka wytrzyma) ustawiasz/potwierdzasz sam.

### 3b. Ranking strategii
Tu porównujesz, co będzie szybsze: szybsza-ale-krótka mieszanka (więcej pit stopów) czy wolniejsza-ale-długa (mniej stopów).
1. Wpisz **Długość wyścigu (okr.)** — przycisk **„Z sesji"** wstawia liczbę okrążeń z aktualnego wyścigu.
2. Wpisz **Stratę na pit stopie (s)** — ile czasu tracisz na jeden zjazd (alejka serwisowa + zmiana opon). Typowo ~18–25 s.
3. (Opcjonalnie) włącz **„Wymóg 2 mieszanek"**, jeśli regulamin wyścigu zmusza do użycia dwóch.
4. W **„Dostępne mieszanki"** zaznacz te, które masz do dyspozycji, i dla każdej ustaw:
   - **Tempo (s)** — czas okrążenia na świeżej oponie,
   - **Degr. (s/okr.)** — przyrost czasu z wiekiem opony,
   - **Życie (okr.)** — ile okrążeń wytrzyma komplet.
   - Jeśli masz pomiar tej mieszanki, naciśnij **„Użyj pomiaru"** — pola wypełnią się automatycznie.
5. Pod spodem, w **„Najlepsze strategie"**, dostajesz ranking (od najszybszej):
   - liczba pit stopów (lub „bez pit stopu"),
   - plan (np. `RS 8 + RM 12` = pierwszy stint RS na 8 okrążeń, drugi RM na 12),
   - łączny czas wyścigu,
   - strata do najlepszej opcji (np. `+3.9 s`). Najlepsza jest podświetlona na zielono.

**Przykład:** wyścig 20 okrążeń, strata na pit 22 s, dostępne RS/RM/RH →
- `1 pit stop — RS 8 + RM 12 — najlepsza`
- `1 pit stop — RM 10 + RM 10 — +3.9 s`
- `bez pit stopu — RH 20 — +6.5 s`

---

## 4. Nagrania — udostępnianie i porównywanie

Wejdź w zakładkę **Nagrania**.

### Udostępnienie swojego okrążenia
1. Przy wybranym nagraniu naciśnij **⋮ → „Udostępnij"**.
2. Otworzy się systemowy arkusz udostępniania — wyślij plik (Gmail, Messenger, Dysk itd.). W pliku zapisana jest Twoja nazwa jako autora.

> Na emulatorze lista może pokazywać tylko „Udostępnianie w pobliżu" — to normalne, bo emulator nie ma zainstalowanych komunikatorów. Na prawdziwym telefonie zobaczysz pełną listę.

### Import okrążenia od kolegi
1. Naciśnij **„Importuj"** (ikona pobierania w pasku Nagrań).
2. Wskaż plik `.json`, który dostałeś.
3. Nagranie pojawi się na liście z plakietką **„· import od X"**.

### Porównanie telemetrii i referencja (DELTA REF)
1. Zaznacz dwa okrążenia (swoje + cudze albo dwa swoje) i otwórz **Telemetrię** — wykresy nałożą się na siebie.
2. Aby jechać „na żywo" względem cudzego/własnego najlepszego okrążenia: przy wybranym nagraniu **⋮ → „Ustaw jako referencję"**. Podczas jazdy inżynier będzie podawał deltę (DELTA REF) do tego okrążenia.

> Porównanie grupuje okrążenia po kształcie toru, więc działa najlepiej dla nagrań z tego samego toru.

---

## Najczęstsze pytania

- **Czy do testowania muszę być w tej samej sieci?** Do telemetrii na żywo (i wykrywania konsoli) — tak, telefon i PS5 w tej samej sieci Wi-Fi. Konta i głos działają przez internet.
- **Czemu strategia pokazuje „Brak wykonalnej strategii"?** Łączna żywotność wybranych mieszanek nie pokrywa dystansu, albo wyścig jest dłuższy niż maksymalna liczba stintów. Zwiększ „Życie" mieszanki lub dodaj więcej mieszanek.
- **Skąd wziąć realne tempo i żywotność opon?** Najlepiej zmierzyć z jazdy (sekcja „Pomiar tempa" → „Użyj pomiaru"). Wartości domyślne to tylko punkt startowy.

# Serwer głosu — GT7 Race Engineer

Wspólny serwer dla dwóch funkcji aplikacji mobilnej:

1. **Głos jak na PC** (`/tts`) — synteza neuronowym głosem Microsoftu (edge-tts).
   Aplikacja wysyła tekst, dostaje plik MP3 i odtwarza go u siebie.
2. **Bot Discord** (`/discord/say`) — bot wchodzi na kanał głosowy i wypowiada
   komunikaty inżyniera, tak jak na komputerze.

Wszystko w jednym procesie Pythona.

---

## Wymagania

- **Python 3.10+**
- **ffmpeg** w PATH (potrzebny botowi Discord do odtwarzania dźwięku)
  - Windows: pobierz z https://www.gyan.dev/ffmpeg/builds/ i dodaj folder `bin` do PATH
  - Linux: `sudo apt install ffmpeg`
  - macOS: `brew install ffmpeg`

## Instalacja

```bash
cd server
python -m venv .venv
# Windows:
.venv\Scripts\activate
# Linux/macOS:
source .venv/bin/activate

pip install -r requirements.txt
```

## Konfiguracja

Skopiuj `.env.example` do `.env` i uzupełnij. Minimalnie do testu samego głosu
wystarczy `DEFAULT_VOICE` i (zalecane) `API_KEY`.

```
DEFAULT_VOICE=pl-PL-MarekNeural
API_KEY=jakis-losowy-ciag
```

## Uruchomienie

```bash
uvicorn app:app --host 0.0.0.0 --port 8080
```

`--host 0.0.0.0` sprawia, że serwer jest widoczny w sieci lokalnej (telefon na tym
samym WiFi go znajdzie pod adresem IP komputera, np. `http://192.168.1.50:8080`).

## Szybki test głosu

```bash
curl -X POST http://localhost:8080/tts ^
  -H "Content-Type: application/json" ^
  -H "X-API-Key: jakis-losowy-ciag" ^
  -d "{\"text\": \"Test inżyniera. Hamuj na zakręcie trzy.\"}" ^
  --output test.mp3
```

Odtwórz `test.mp3` — powinieneś usłyszeć neuronowy głos „Marek".

---

## Bot Discord (krok po kroku)

1. Wejdź na https://discord.com/developers/applications → **New Application**.
2. Zakładka **Bot** → **Reset Token** → skopiuj token do `DISCORD_TOKEN` w `.env`.
3. W sekcji **Privileged Gateway Intents** nic specjalnego nie jest wymagane do
   samego mówienia (wystarczają domyślne uprawnienia).
4. Zakładka **OAuth2 → URL Generator**: zaznacz **bot**, a w uprawnieniach
   **Connect** i **Speak**. Skopiuj wygenerowany link, otwórz w przeglądarce
   i dodaj bota na swój serwer.
5. W Discordzie włącz **Ustawienia → Zaawansowane → Tryb dewelopera**.
6. Kliknij ppm na **serwer** → *Kopiuj ID serwera* → `DISCORD_GUILD_ID`.
7. Kliknij ppm na **kanał głosowy** → *Kopiuj ID kanału* → `DISCORD_VOICE_CHANNEL_ID`.
8. Uruchom serwer ponownie. W logach zobaczysz `[Discord] Połączono z kanałem: ...`.

Test wypowiedzi na kanale:

```bash
curl -X POST http://localhost:8080/discord/say ^
  -H "Content-Type: application/json" ^
  -H "X-API-Key: jakis-losowy-ciag" ^
  -d "{\"text\": \"Cześć, tu inżynier.\"}"
```

Bot powinien odezwać się na kanale (musisz być na nim, żeby usłyszeć).

---

## Dostępność dla znajomych

- **Bot Discord** łączy się z Discordem „wychodząco", więc do samego gadania na
  kanale **nie trzeba** otwierać portów — wystarczy, że serwer gdzieś działa
  (Twój komputer albo tani VPS) i jest włączony, gdy gracie.
- **Aplikacja** łączy się z serwerem po HTTP. Telefon musi mieć do niego dostęp:
  - ten sam WiFi co serwer → użyj lokalnego IP,
  - przez internet → potrzebny publiczny adres (VPS albo przekierowanie portu /
    tunel typu Cloudflare Tunnel / ngrok). Wtedy koniecznie ustaw `API_KEY`.

## Dostępne głosy

Pełna lista (po instalacji edge-tts):

```bash
edge-tts --list-voices | findstr pl-PL    # Windows
edge-tts --list-voices | grep pl-PL       # Linux/macOS
```

Polskie: `pl-PL-MarekNeural`, `pl-PL-ZofiaNeural`. Angielskie m.in.
`en-US-AriaNeural`, `en-GB-RyanNeural`.

## Endpointy

| Metoda | Ścieżka         | Body                          | Zwraca            |
|--------|-----------------|-------------------------------|-------------------|
| GET    | `/`             | —                             | status JSON       |
| POST   | `/tts`          | `{text, voice?, rate?}`       | MP3 (audio/mpeg)  |
| POST   | `/discord/say`  | `{text, voice?, rate?}`       | JSON `{ok}`       |

`rate` to tempo, np. `"+0%"`, `"-10%"`, `"+20%"`. Nagłówek `X-API-Key` wymagany,
gdy ustawiono `API_KEY`.

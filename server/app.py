"""Serwer głosu GT7 Race Engineer — Edge-TTS + bot Discord.

Dwie funkcje w jednym procesie:

1. /tts  — synteza neuronowym głosem Microsoftu (edge-tts), zwraca MP3.
           Aplikacja mobilna pobiera plik i odtwarza go u siebie (głos jak na PC).
2. /discord/say — kolejkuje tekst, który BOT Discord wypowiada na kanale głosowym
           (tak jak na komputerze inżynier szedł do kanału przez kabel audio).

Wszystkie komentarze i komunikaty po polsku. Konfiguracja przez zmienne środowiskowe
(plik .env — patrz .env.example).

Uruchomienie:
    pip install -r requirements.txt
    uvicorn app:app --host 0.0.0.0 --port 8080
"""

from __future__ import annotations

import asyncio
import os
import tempfile

import edge_tts
from fastapi import Body, FastAPI, Header, HTTPException
from fastapi.responses import JSONResponse, Response

try:
    from dotenv import load_dotenv
    load_dotenv()
except Exception:  # noqa: BLE001
    pass

# --- Konfiguracja (zmienne środowiskowe / .env) ---
DISCORD_TOKEN = os.environ.get("DISCORD_TOKEN", "").strip()
GUILD_ID = int(os.environ.get("DISCORD_GUILD_ID", "0") or 0)
VOICE_CHANNEL_ID = int(os.environ.get("DISCORD_VOICE_CHANNEL_ID", "0") or 0)
API_KEY = os.environ.get("API_KEY", "").strip()
DEFAULT_VOICE = os.environ.get("DEFAULT_VOICE", "pl-PL-MarekNeural").strip()

app = FastAPI(title="GT7 Race Engineer — serwer głosu")


# --- Wspólna synteza Edge-TTS ---
async def synthesize(text: str, voice: str, rate: str) -> bytes:
    """Zwraca MP3 (bytes) dla podanego tekstu i głosu. rate np. '+0%', '-10%'."""
    communicate = edge_tts.Communicate(text, voice, rate=rate)
    buf = bytearray()
    async for chunk in communicate.stream():
        if chunk["type"] == "audio":
            buf.extend(chunk["data"])
    return bytes(buf)


def _check_key(x_api_key: str) -> None:
    """Prosta ochrona — gdy ustawiono API_KEY, żądania muszą podać ten klucz."""
    if API_KEY and x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Zły klucz API.")


@app.get("/")
async def health() -> JSONResponse:
    """Healthcheck + stan bota."""
    return JSONResponse(
        {
            "ok": True,
            "discord": {
                "skonfigurowany": bool(DISCORD_TOKEN),
                "polaczony": _voice_client is not None
                and _voice_client.is_connected(),
            },
            "domyslny_glos": DEFAULT_VOICE,
        }
    )


@app.post("/tts")
async def tts(
    payload: dict = Body(...),
    x_api_key: str = Header(default=""),
) -> Response:
    """Synteza tekstu -> MP3. Body: {text, voice?, rate?}."""
    _check_key(x_api_key)
    text = (payload.get("text") or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="Brak tekstu.")
    voice = (payload.get("voice") or DEFAULT_VOICE).strip()
    rate = (payload.get("rate") or "+0%").strip()
    try:
        audio = await synthesize(text, voice, rate)
    except Exception as e:  # noqa: BLE001
        raise HTTPException(status_code=502, detail=f"Błąd syntezy: {e}")
    return Response(content=audio, media_type="audio/mpeg")


# =====================================================================
#  Bot Discord
# =====================================================================
import discord  # noqa: E402

_intents = discord.Intents.default()
_bot = discord.Client(intents=_intents)
_voice_client: "discord.VoiceClient | None" = None
_speak_queue: "asyncio.Queue[tuple[str, str, str]]" = asyncio.Queue()


@_bot.event
async def on_ready() -> None:
    """Po zalogowaniu bot dołącza na skonfigurowany kanał głosowy i startuje
    pętlę wypowiedzi."""
    global _voice_client
    print(f"[Discord] Zalogowano jako {_bot.user}")
    if VOICE_CHANNEL_ID:
        ch = _bot.get_channel(VOICE_CHANNEL_ID)
        if isinstance(ch, discord.VoiceChannel):
            try:
                _voice_client = await ch.connect()
                print(f"[Discord] Połączono z kanałem: {ch.name}")
            except Exception as e:  # noqa: BLE001
                print(f"[Discord] Nie udało się dołączyć: {e}")
        else:
            print("[Discord] DISCORD_VOICE_CHANNEL_ID nie wskazuje kanału głosowego.")
    _bot.loop.create_task(_speak_worker())


async def _speak_worker() -> None:
    """Po kolei wypowiada teksty z kolejki na kanale głosowym (Edge-TTS + ffmpeg)."""
    while True:
        text, voice, rate = await _speak_queue.get()
        try:
            if not (_voice_client and _voice_client.is_connected()):
                continue
            audio = await synthesize(text, voice, rate)
            path = tempfile.mktemp(suffix=".mp3")
            with open(path, "wb") as f:
                f.write(audio)
            # Poczekaj, aż skończy się poprzednia wypowiedź.
            while _voice_client.is_playing():
                await asyncio.sleep(0.1)
            source = discord.FFmpegPCMAudio(path)
            _voice_client.play(source)
        except Exception as e:  # noqa: BLE001
            print(f"[Discord] Błąd wypowiedzi: {e}")
        finally:
            _speak_queue.task_done()


@app.post("/discord/say")
async def discord_say(
    payload: dict = Body(...),
    x_api_key: str = Header(default=""),
) -> JSONResponse:
    """Kolejkuje tekst do wypowiedzenia przez bota na kanale. Body: {text, voice?, rate?}."""
    _check_key(x_api_key)
    text = (payload.get("text") or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="Brak tekstu.")
    if not DISCORD_TOKEN:
        raise HTTPException(status_code=503, detail="Bot Discord nie jest skonfigurowany.")
    voice = (payload.get("voice") or DEFAULT_VOICE).strip()
    rate = (payload.get("rate") or "+0%").strip()
    await _speak_queue.put((text, voice, rate))
    return JSONResponse({"ok": True, "w_kolejce": _speak_queue.qsize()})


@app.on_event("startup")
async def _startup() -> None:
    """Startuje bota Discord w tle (gdy podano token)."""
    if DISCORD_TOKEN:
        asyncio.create_task(_bot.start(DISCORD_TOKEN))
        print("[Discord] Bot uruchamiany w tle...")
    else:
        print("[Discord] Brak DISCORD_TOKEN — działa tylko /tts.")

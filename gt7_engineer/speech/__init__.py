"""Warstwa glosowa: kolejkowanie i odtwarzanie komunikatow inzyniera (TTS)."""

from .speaker import Speaker, Priority
from .sound import radio_beep

__all__ = ["Speaker", "Priority", "radio_beep"]

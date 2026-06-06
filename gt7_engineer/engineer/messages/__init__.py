"""Wybor zestawu komunikatow inzyniera wg jezyka."""

from __future__ import annotations

from .base import Messages
from .en import EnglishMessages
from .pl import PolishMessages

_REGISTRY = {
    "pl": PolishMessages,
    "en": EnglishMessages,
}


def load(language: str) -> Messages:
    """Zwraca instancje komunikatow dla danego jezyka (domyslnie polski)."""
    code = (language or "pl").strip().lower()[:2]
    cls = _REGISTRY.get(code, PolishMessages)
    return cls()


__all__ = ["Messages", "PolishMessages", "EnglishMessages", "load"]

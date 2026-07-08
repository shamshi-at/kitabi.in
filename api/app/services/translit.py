"""Romanization for cross-script search — "Kayary" must find "കയർ".

Every catalog title/name gets a stored lowercase Latin form
(`title_translit` / `name_translit`), and search romanizes the query the same
way, so the existing pg_trgm fuzzy matching works across scripts in both
directions (Latin query ↔ Indic title, Indic query ↔ Latin title).

Two stages, both pure-Python (CLAUDE.md rule 8 — no service, no bill):

1. Indic scripts go through `indic_transliteration` (ITRANS target), which
   keeps the vowels — sound-alike romanization ("കയർ" → "kayar"). A generic
   char-map like anyascii alone drops Indic inherent vowels ("kyr"), which
   trigram-matches nothing a human would type.
2. `anyascii` then flattens whatever remains (chillus the scheme map missed,
   accents, any non-Indic script — Cyrillic, CJK, Arabic…) to plain ASCII.

Trigram similarity absorbs the leftover spelling drift ("chemmin" vs the
typed "chemmeen"), the same way it already absorbs typos.
"""

import re

from anyascii import anyascii
from indic_transliteration import detect, sanscript
from indic_transliteration.sanscript import SCHEMES

_WHITESPACE = re.compile(r"\s+")


def _indic_scheme(text: str) -> str | None:
    """The sanscript scheme name when [text] is in a Brahmic (Indic) script —
    None for Latin/other, which `detect` reports as a *roman* scheme guess."""
    try:
        name = detect.detect(text)
    except Exception:  # noqa: BLE001 — detection must never break a write/search
        return None
    scheme = SCHEMES.get(name)
    if scheme is None or getattr(scheme, "is_roman", True):
        return None
    return name


def transliterate(text: str | None) -> str | None:
    """Lowercase ASCII romanization of [text], or None when there's nothing
    left (empty input). Latin input just lowercases, so storing and querying
    through this one function keeps both sides comparable."""
    if text is None:
        return None
    value = text.strip()
    if not value:
        return None
    scheme = _indic_scheme(value)
    if scheme is not None:
        try:
            value = sanscript.transliterate(value, scheme, sanscript.ITRANS)
        except Exception:  # noqa: BLE001 — fall back to the plain char map
            pass
    value = anyascii(value)
    value = _WHITESPACE.sub(" ", value).strip().lower()
    return value or None

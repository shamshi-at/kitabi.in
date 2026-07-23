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

# ITRANS spells the two Indic nasals with a tilde — ~N for ങ, ~n for ഞ — and a
# tilde is something no reader ever types, so it has to go before the value
# becomes a search key. The doubled forms are collapsed first because the
# geminates are what actually occur in Malayalam (the -ങ്ങൾ plural, ഞ്ഞ), and
# collapsing them lands on the spelling people really use: മാങ്ങാട് →
# "mangat" not "mangngat", കൊഴിഞ്ഞു → "kozhinju" not "kozhinjnju".
_ITRANS_NASALS = [("~N~N", "ng"), ("~n~n", "nj"), ("~N", "ng"), ("~n", "nj")]

# ITRANS marks the long vowels ീ/ൂ with an uppercase I/U, which lowercasing
# then flattens to a bare "i"/"u" — but nobody types Malayalam that way. The
# Manglish convention doubles them: ചെമ്മീൻ is typed "chemmeen", not
# "chemmin"; അപൂർണ്ണൻ is "apoornnan", not "apurnnan". Storing the single
# letter cost real matches — "Apoornn" scored 0.27 against "apurnnan" and
# found nothing, where it scores 0.88 against "apoornnan" (owner report,
# 23 Jul 2026). Uppercase I/U are long vowels only in ITRANS; the uppercase
# retroflex consonants (T/D/N/S/L) are deliberately left alone.
_ITRANS_LONG_VOWELS = [("I", "ee"), ("U", "oo")]


# Tamil writes one letter per place of articulation — ப covers pa/ba, ச covers
# sa/cha/ja — and the plain `tamil` scheme resolves each to its *Sanskrit*
# voiced-aspirate value, so "பொன்னியின் செல்வன்" romanized to "bhonniyin
# jhelvan" and no reader could ever have found it. The superscripted variant
# resolves them to the unvoiced Tamil readings ("ponniyin chelvan").
_SCHEME_OVERRIDES = {"tamil": "tamil_superscripted"}


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
    return _SCHEME_OVERRIDES.get(name, name)


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
        # Nasals first: their ITRANS spelling (~N) contains an uppercase letter
        # the long-vowel pass must not see.
        for itrans, plain in _ITRANS_NASALS + _ITRANS_LONG_VOWELS:
            value = value.replace(itrans, plain)
    value = anyascii(value)
    value = _WHITESPACE.sub(" ", value).strip().lower()
    return value or None

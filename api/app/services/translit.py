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

That gives ONE romanization, but readers type many, and trigram similarity
does not always absorb the difference — "Apoornn" scored 0.27 against a stored
"apurnnan" and found nothing (owner report, 23 Jul 2026). So each of those
columns has a second twin, `*_fold`: see `fold` below, which collapses the
spelling choices Indic-language typists make interchangeably. Search matches on
title/name, translit AND fold, so a query wins on whichever agrees.
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


# --- The fold -------------------------------------------------------------
#
# `transliterate` gives ONE romanization, but readers type many. The same book
# arrives as "chemmeen"/"chemmin", "thirukkural"/"tirukural", "gitanjali"/
# "geetanjali" — and no single stored spelling can equal all of them. The fold
# collapses every spelling that Indic-language typists use interchangeably down
# to one skeleton, and because the *query* is folded the same way, the two
# sides meet regardless of which spelling either used.
#
# What it deliberately throws away, all of it drift we measured on real titles:
#   - long vs short vowels      aa/ee/oo -> a/i/u   (geetanjali = gitanjali)
#   - aspiration                th/kh/gh/bh -> t/k/g/b  (thirukkural = tirukkural)
#   - the sibilant series       ch/sh/s -> s        (chelvan = selvan, Tamil ச)
#   - doubled consonants        nn/mm/kk -> n/m/k   (chemmeen = chemeen)
#   - v/w, and a nasal before a consonant (anusvara reads as m or n by ear)
#
# Order matters: multi-character rules run before the doubling collapse, or
# "chh" would become "ch" and then miss the sibilant rule.
_FOLD_RULES = [
    ("ksh", "x"),
    ("aa", "a"),
    ("ee", "i"),
    ("oo", "u"),
    ("ii", "i"),
    ("uu", "u"),
    ("kh", "k"),
    ("gh", "g"),
    ("jh", "j"),
    ("dh", "d"),
    ("th", "t"),
    ("ph", "p"),
    ("bh", "b"),
    ("ch", "s"),
    ("sh", "s"),
    ("zh", "z"),
    ("w", "v"),
]
_NON_WORD = re.compile(r"[^a-z0-9 ]")
_NASAL_BEFORE_CONSONANT = re.compile(r"m(?=[^aeiou ]|$)")
_DOUBLED = re.compile(r"(.)\1+")


def fold(text: str | None) -> str | None:
    """The spelling-insensitive search skeleton for [text] — see above.

    Lossy by design, and safe to be: across the seeded catalog only one pair of
    distinct titles folded together, and they were the same word spelled two
    ways. Always apply it to the query as well as the stored value; a fold
    compared against an unfolded string is meaningless.
    """
    romanized = transliterate(text)
    if romanized is None:
        return None
    value = _NON_WORD.sub(" ", romanized.lower())
    for a, b in _FOLD_RULES:
        value = value.replace(a, b)
    value = _NASAL_BEFORE_CONSONANT.sub("n", value)
    value = _DOUBLED.sub(r"\1", value)
    value = _WHITESPACE.sub(" ", value).strip()
    return value or None


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

"""Shared streaming helpers for the OpenLibrary bulk dumps.

Every dump is a gzipped TSV. The entity dumps (works/editions/authors) carry
five columns — type, key, revision, last_modified, full JSON record — and the
ratings/reading-log dumps are plain small-column TSVs. Everything here streams
line-by-line and tolerates a *truncated* file (a ranged-download prefix), so
`sample_stats.py` can size the data from a 32 MB slice.
"""

from __future__ import annotations

import gzip
import json
import re
from collections.abc import Iterator

# MARC language code (OL's /languages/<code>) -> the English name Kitabi stores
# in `works.language` / `editions.language` (the app renders names, not codes).
LANG_NAMES = {
    "eng": "English",
    "mal": "Malayalam",
    "tam": "Tamil",
    "tel": "Telugu",
    "kan": "Kannada",
    "hin": "Hindi",
    "ben": "Bengali",
    "mar": "Marathi",
    "guj": "Gujarati",
    "pan": "Punjabi",
    "ori": "Odia",
    "asm": "Assamese",
    "urd": "Urdu",
    "san": "Sanskrit",
    "fre": "French",
    "ger": "German",
    "spa": "Spanish",
    "ita": "Italian",
    "por": "Portuguese",
    "rus": "Russian",
    "jpn": "Japanese",
    "chi": "Chinese",
    "ara": "Arabic",
    "dut": "Dutch",
    "pol": "Polish",
    "swe": "Swedish",
    "tur": "Turkish",
    "kor": "Korean",
    "per": "Persian",
    "heb": "Hebrew",
    "lat": "Latin",
}

# The wedge languages (CLAUDE.md: `.in`, Malayalam roots) — Tier 1 keeps every
# work with an edition in one of these.
INDIC_LANG_CODES = {
    "mal", "tam", "tel", "kan", "hin", "ben", "mar",
    "guj", "pan", "ori", "asm", "urd", "san",
}

_YEAR = re.compile(r"\b(1[0-9]{3}|20[0-2][0-9])\b")


def iter_dump(path: str) -> Iterator[tuple[str, str, dict]]:
    """Yield (type, key, record) from an entity dump; stop quietly at a
    truncation instead of raising, so prefix samples work."""
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as f:
        try:
            for line in f:
                parts = line.rstrip("\n").split("\t", 4)
                if len(parts) != 5:
                    continue
                typ, key, _rev, _ts, raw = parts
                try:
                    obj = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                if isinstance(obj, dict):
                    obj.setdefault("key", key)
                    yield typ, key, obj
        except (EOFError, OSError):
            return


def iter_tsv(path: str) -> Iterator[list[str]]:
    """Yield raw column lists from a plain TSV dump (ratings / reading log)."""
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as f:
        try:
            for line in f:
                yield line.rstrip("\n").split("\t")
        except (EOFError, OSError):
            return


def ol_text(value) -> str | None:
    """OL rich-text fields are either a plain string or {'type':…, 'value':…}."""
    if isinstance(value, dict):
        value = value.get("value")
    if isinstance(value, str):
        value = value.strip()
        return value or None
    return None


def edition_lang_codes(edition: dict) -> list[str]:
    """MARC codes from an edition's `languages` list (['/languages/mal'] → ['mal'])."""
    codes = []
    for entry in edition.get("languages") or []:
        key = entry.get("key") if isinstance(entry, dict) else None
        if isinstance(key, str) and key.startswith("/languages/"):
            codes.append(key.rsplit("/", 1)[-1])
    return codes


def edition_work_keys(edition: dict) -> list[str]:
    """The /works/… keys an edition belongs to (almost always exactly one)."""
    keys = []
    for entry in edition.get("works") or []:
        key = entry.get("key") if isinstance(entry, dict) else None
        if isinstance(key, str) and key.startswith("/works/"):
            keys.append(key)
    return keys


def work_author_keys(work: dict) -> list[str]:
    """The /authors/… keys on a work. OL wraps these three different ways
    ({'author': {'key':…}}, {'author': '/authors/…'}, {'key':…}) — accept all."""
    keys = []
    for entry in work.get("authors") or []:
        if not isinstance(entry, dict):
            continue
        author = entry.get("author", entry)
        if isinstance(author, dict):
            key = author.get("key")
        else:
            key = author if isinstance(author, str) else None
        if isinstance(key, str) and key.startswith("/authors/"):
            keys.append(key)
    return keys


def first_year(*candidates) -> int | None:
    """First plausible 4-digit year found in any candidate string."""
    for c in candidates:
        if not isinstance(c, str):
            continue
        m = _YEAR.search(c)
        if m:
            return int(m.group(0))
    return None


def isbn_of(edition: dict) -> str | None:
    """Preferred ISBN of an edition — first ISBN-13, else first ISBN-10."""
    for field in ("isbn_13", "isbn_10"):
        for raw in edition.get(field) or []:
            if isinstance(raw, str):
                isbn = raw.replace("-", "").replace(" ", "").strip()
                if isbn:
                    return isbn
    return None


def cover_url_of(record: dict, kind: str = "b") -> str | None:
    """covers.openlibrary.org URL from a record's `covers`/`photos` id list."""
    field = "photos" if kind == "a" else "covers"
    for cid in record.get(field) or []:
        if isinstance(cid, int) and cid > 0:
            return f"https://covers.openlibrary.org/{kind}/id/{cid}-L.jpg"
    return None

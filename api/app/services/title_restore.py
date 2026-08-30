"""Restoring a readable title to a work the Library of Congress romanized.

The catalogue's Indic-language records came from US research-library MARC,
which transcribes every non-Latin title in ALA-LC romanization. That leaves
three different states, and they need three different answers:

  1. A native title, romanized.       `Ardhi rate azadi`  (Freedom at Midnight,
     Gujarati) is આઝાદી અડધી રાતે — the edition has a real Gujarati title and
     the romanization is a cataloguing artefact. Answer: the native script.
  2. An English title, transliterated TWICE. `3 misṭeka ôpha māya lāipha` is
     Chetan Bhagat's *The 3 Mistakes of My Life*: the Gujarati edition printed
     the English title in Gujarati letters, and a cataloguer romanized that
     back out. `ôpha` is "of" — Indic scripts have no /f/, so it arrives as
     *ph*. The result is neither language, and converting it to Gujarati
     script would only produce Gujarati letters spelling English words.
     Answer: the English title as published.
  3. Already right.                   `The Secret` on a Gujarati work, or a
     title already in native script. Answer: leave it alone.

Telling these apart is a per-book judgement — it needs to know that Bhagat
writes in English and that Collins & Lapierre's book has a Gujarati title —
so a model proposes and a human confirms, the shape 08_genre_classify uses.
This module is the pure half: the prompt, and a parser that refuses anything
it cannot verify.

**The script check is the load-bearing guard.** A `native` answer must
actually contain characters of that language's script, and an `english`
answer must contain none. That is mechanical, and it catches precisely the
failure that sank the naive sanscript conversion (measured 31 Aug 2026):
output that *looks* converted while carrying Devanagari vowels inside
Gujarati, or raw Latin left in Gurmukhi. A model that romanizes instead of
converting, or reaches for the wrong script, is rejected here rather than
reviewed by eye.
"""

from __future__ import annotations

import json
import re

# Where each language's script lives. Assamese and Bengali share a block, as do
# Hindi/Marathi/Sanskrit — the point of the check is "is this the right script
# at all", not which of two languages that share one.
SCRIPT_RANGES: dict[str, tuple[int, int]] = {
    "Malayalam": (0x0D00, 0x0D7F),
    "Tamil": (0x0B80, 0x0BFF),
    "Telugu": (0x0C00, 0x0C7F),
    "Kannada": (0x0C80, 0x0CFF),
    "Hindi": (0x0900, 0x097F),
    "Marathi": (0x0900, 0x097F),
    "Sanskrit": (0x0900, 0x097F),
    "Bengali": (0x0980, 0x09FF),
    "Assamese": (0x0980, 0x09FF),
    "Gujarati": (0x0A80, 0x0AFF),
    "Punjabi": (0x0A00, 0x0A7F),
    "Odia": (0x0B00, 0x0B7F),
    "Urdu": (0x0600, 0x06FF),
}

NATIVE = "native"
ENGLISH = "english"
UNCHANGED = "unchanged"
UNKNOWN = "unknown"
KINDS = (NATIVE, ENGLISH, UNCHANGED, UNKNOWN)

CONFIDENCES = ("high", "medium", "low", "unknown")

# Any Brahmic or Perso-Arabic character at all — an `english` answer must have
# none, whatever the work's own language happens to be.
_ANY_INDIC = re.compile(r"[؀-ۿऀ-෿]")

_PROMPT_HEAD = """\
Each row below is a book in our catalogue. Its title was transcribed by a US
research library in ALA-LC romanization, so it may not be the title anyone
actually reads. For each row, give the title as it is really printed.

Decide between exactly these answers:

- "native": the edition has a real title in its own language, and what you see
  is only a romanization of it. Return that title IN ITS OWN SCRIPT.
  Example: "Ardhi rate azadi" (Gujarati, Collins & Lapierre) -> "આઝાદી અડધી રાતે".

- "english": the work was written in English and this edition merely
  transliterated the English title into its script, which was then romanized
  back out. Return the ORIGINAL ENGLISH TITLE as published.
  Example: "3 misṭeka ôpha māya lāipha" (Gujarati, Chetan Bhagat) ->
  "The 3 Mistakes of My Life". The giveaway is that the words decode as
  English: Indic scripts have no /f/, so "of" arrives as "ôpha".

- "unchanged": the title is already right — already in its own script, or
  already the correct English title.

- "unknown": you do not know this book. Say so.

Rules, all of them load-bearing:
- A "native" title MUST be written in that language's own script. Never return
  a romanization for "native" — that is the thing we are trying to remove.
- An "english" title must contain no non-Latin characters.
- NEVER invent or guess a title. If you cannot identify the book with
  confidence, answer "unknown". These become public pages: an honest blank is
  worth more than a plausible wrong title.
- Do not translate. A native title is what the book is CALLED, not a rendering
  of the romanized words.
- Keep the author's own title. Do not add a subtitle, series name or edition note.

Reply with ONLY a JSON array, one object per row:
[{"id": "<id>", "kind": "native|english|unchanged|unknown",
  "title": "<the title, or null for unchanged/unknown>",
  "confidence": "high|medium|low"}]

Rows:
"""


def restoration_prompt(works: list[dict]) -> str:
    """One batch's user message. Everything that helps identify the book goes
    in — an ISBN or a publisher often settles which edition this is, and the
    description is frequently the only English in the record."""
    lines = [_PROMPT_HEAD]
    for w in works:
        parts = [f'id={w["id"]}', f'title={w["title"]!r}']
        for key in ("subtitle", "authors", "language", "year", "isbn", "publisher"):
            if w.get(key):
                parts.append(f"{key}={w[key]!r}")
        if w.get("description"):
            parts.append(f'description={w["description"][:220]!r}')
        lines.append("- " + ", ".join(parts))
    return "\n".join(lines)


def in_script(text: str, language: str | None) -> bool:
    """Whether [text] carries any character of [language]'s own script."""
    span = SCRIPT_RANGES.get(language or "")
    if span is None:
        return False
    return any(span[0] <= ord(c) <= span[1] for c in text)


def parse_restoration(raw: str, expected: dict[str, str | None]) -> tuple[list[dict], list[str]]:
    """Read one model reply into per-work rows, eagerly and defensively.

    `expected` maps work id -> language, because validating a `native` answer
    needs to know which script it should be in. Element-by-element on purpose
    (CLAUDE.md, 21 Jul 2026): a shape surprise fails HERE, at the boundary, as
    a noted problem — never later inside an apply loop.

    Returns (rows, problems). A row that fails validation is downgraded to
    `unknown` and noted, never silently dropped and never repaired: a title we
    had to fix up is a title nobody verified.
    """
    rows: list[dict] = []
    problems: list[str] = []

    match = re.search(r"\[.*\]", raw, re.S)
    if not match:
        return [], [f"no JSON array in reply ({raw[:80]!r}…)"]
    try:
        data = json.loads(match.group(0))
    except json.JSONDecodeError as exc:
        return [], [f"unparseable JSON: {exc}"]
    if not isinstance(data, list):
        return [], ["reply JSON is not a list"]

    seen: set[str] = set()
    for item in data:
        if not isinstance(item, dict):
            problems.append(f"non-object element: {item!r}")
            continue
        work_id = str(item.get("id", ""))
        if work_id not in expected:
            problems.append(f"unexpected id {work_id!r}")
            continue
        if work_id in seen:
            problems.append(f"duplicate id {work_id!r}")
            continue
        seen.add(work_id)

        kind = item.get("kind")
        title = item.get("title")
        title = " ".join(title.split()) if isinstance(title, str) else None
        confidence = item.get("confidence")
        if confidence not in CONFIDENCES:
            confidence = "low"

        if kind not in KINDS:
            problems.append(f"{work_id}: unknown kind {kind!r}")
            kind = UNKNOWN
        elif kind in (NATIVE, ENGLISH) and not title:
            problems.append(f"{work_id}: kind {kind} with no title")
            kind = UNKNOWN
        elif kind == NATIVE and not in_script(title, expected[work_id]):
            # The guard the whole module exists for: a "native" answer that is
            # not in the language's script is a romanization or the wrong
            # script, which is exactly what we are removing.
            problems.append(
                f"{work_id}: 'native' title {title!r} is not in "
                f"{expected[work_id]} script — rejected"
            )
            kind = UNKNOWN
        elif kind == ENGLISH and _ANY_INDIC.search(title or ""):
            problems.append(f"{work_id}: 'english' title {title!r} carries non-Latin script")
            kind = UNKNOWN

        if kind in (UNCHANGED, UNKNOWN):
            title = None
        if kind == UNKNOWN:
            confidence = UNKNOWN

        rows.append({"id": work_id, "kind": kind, "title": title, "confidence": confidence})

    missing = set(expected) - seen
    if missing:
        problems.append(f"{len(missing)} row(s) absent from the reply")
    return rows, problems

"""Cover-photo extraction — prefill the add-book form from photographs.

The rescue path for books the catalog and OpenLibrary have never heard of
(disproportionately regional-language books, which is exactly Kitabi's
audience): the user has already photographed the front/back covers on the
add-book form (uploaded to the public `covers` bucket before save), so we hand
those URLs to a vision model and get back structured fields — title, authors,
publisher, the back-cover blurb — for the form to prefill. The user edits from
there; nothing is saved without them.

**Two calls, not one.** The identity fields (title, authors, publisher, ISBN,
…) are a few dozen output tokens; the back-cover blurb is up to 150 words, and
in Malayalam that tokenizes to well over a thousand — so in a single call the
title the reader is staring at waits behind a paragraph they have not asked for
yet. `extract_identity` and `extract_blurb` are separate requests so the form
can fill the identity fields in a second or two and let the description land
behind them (`part` on the endpoint picks one; no `part` runs both
concurrently and merges, which is what an older app build gets).

The blurb call reads the back cover when there is one and falls back to the
front when there isn't. It would be cheaper to skip it altogether on a
front-only photo set — a blurb lives on the back — but "cheaper" is not what
the split is for, and a reader who photographed one side of a book that does
carry text on it would silently stop getting a description they get today.

Dormant unless an Anthropic API key is configured, same gate as
recommendations (CLAUDE.md rule 8: no mandatory external bill). The LLM call
is isolated behind an injectable client so parsing and prompt-building are
unit-testable without a key.
"""

import asyncio
import json
from typing import Any

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.models import Author, Series
from app.schemas.catalog import WORK_FORMS
from app.services import catalog_service
from app.services import isbn as isbn_util
from app.services.anthropic_client import ANTHROPIC_URL, headers, reply_text

# Shared by both prompts: what the images are, and the rule that stopped a
# smaller model inventing a plausible Malayalam title (ced7bd6, 8 Jul 2026).
_PREAMBLE = (
    "You read photographs of a physical book's front and/or back cover. The "
    "book may be in any language or script (Malayalam, Hindi, Tamil, English, "
    "...) — transcribe titles and names in their printed script, do not "
    "transliterate. "
)
_NO_GUESSING = (
    "CRITICAL: transcribe ONLY text that is actually printed and legible in the "
    "image. Do NOT guess, translate, or invent a plausible-sounding title or "
    "name — if a field is not clearly readable, return null for it. It is far "
    "better to return null than a made-up value. "
)

_IDENTITY_SYSTEM = (
    _PREAMBLE + "Extract catalog fields. "
    "`series_number` is the book's position if the cover shows one (e.g. "
    "'Book 3'). `language` is the language the book itself is written in, as "
    "an English word (e.g. 'Malayalam'). `form` is the literary form of the "
    "book when the cover makes it clear (a Malayalam cover saying നോവൽ means "
    "'Novel', ചെറുകഥകൾ means 'Short stories', കവിതകൾ means 'Poetry'), and it "
    f"must be EXACTLY one of: {', '.join(WORK_FORMS)} — or null when unsure. "
    "`isbn` is the ISBN printed next to the back-cover barcode — the 13-digit "
    "form when the cover shows one, or the 10-digit form on older printings "
    "that show only that. Digits only (no hyphens/spaces; a trailing X is part "
    "of a 10-digit ISBN, keep it), and ONLY if you can read every character "
    "clearly; otherwise null (never guess a digit). "
    + _NO_GUESSING
    + "Do NOT transcribe the back-cover blurb — it is not wanted here. "
    "Respond with ONLY a JSON object exactly like: "
    '{"title": null, "authors": [], "publisher": null, "series_name": null, '
    '"series_number": null, "language": null, "form": null, "isbn": null}'
)

_BLURB_SYSTEM = (
    _PREAMBLE + "Transcribe the back-cover blurb/synopsis into `description`: "
    "faithfully, in its printed script, but without review quotes, price, or "
    "barcode text; keep it under 150 words. Null when the cover carries no "
    "blurb. " + _NO_GUESSING + 'Respond with ONLY a JSON object exactly like: {"description": null}'
)

# The identity fields are a short JSON object; the blurb is up to 150 words of
# Malayalam, which tokenizes several times worse than the same words in
# English. Sized separately so the fast call is not given room to ramble.
_IDENTITY_MAX_TOKENS = 512
_BLURB_MAX_TOKENS = 2048


def valid_isbn13(raw: str | None) -> str | None:
    """Return the canonical ISBN-13 if [raw] is a checksum-valid ISBN, else None.

    Photo OCR of a printed code is error-prone, so the checksum is the gate: a
    single misread digit fails it and we drop the value rather than prefill the
    wrong book (the barcode Scan stays the exact path).

    A checksum-valid ISBN-10 is accepted and converted, because the back of a
    pre-2007 printing — which is most of what a reader photographs in a
    second-hand shop — prints only the 10-digit form. Rejecting those was
    dropping a field we could read perfectly well.

    The 978/979 gate stays: a 13-digit code that isn't in the Bookland range is
    some other product's EAN, and OCR of a cover can easily land on one.
    """
    cleaned = isbn_util.clean(raw)
    if cleaned is None:
        return None
    if len(cleaned) == 13 and not cleaned.startswith(("978", "979")):
        return None
    return isbn_util.to_isbn13(cleaned)


def _extract_object(text: str) -> dict[str, Any]:
    """Pull the first JSON object out of the model's reply (which may wrap it
    in prose despite instructions). Empty dict when there isn't one."""
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1:
        return {}
    try:
        parsed = json.loads(text[start : end + 1])
    except json.JSONDecodeError:
        return {}
    return parsed if isinstance(parsed, dict) else {}


def _str_field(raw: dict[str, Any], key: str) -> str | None:
    value = raw.get(key)
    if isinstance(value, str) and value.strip():
        return value.strip()
    return None


def _clean(raw: dict[str, Any]) -> dict[str, Any]:
    """Normalise the model's object into the response shape — strings trimmed,
    authors always a list of non-empty strings, series_number an int or None.
    Unknown keys are dropped; missing ones come back as None/[].

    Covers every field either call can produce, so it stays the one place the
    response shape is defined; each call keeps only the keys it asked for."""
    authors_raw = raw.get("authors")
    authors = [
        a.strip()
        for a in (authors_raw if isinstance(authors_raw, list) else [])
        if isinstance(a, str) and a.strip()
    ]

    number = raw.get("series_number")
    if isinstance(number, str) and number.strip().isdigit():
        number = int(number.strip())
    if not isinstance(number, int) or isinstance(number, bool):
        number = None

    form = _str_field(raw, "form")
    return {
        "title": _str_field(raw, "title"),
        "authors": authors,
        "publisher": _str_field(raw, "publisher"),
        "description": _str_field(raw, "description"),
        "series_name": _str_field(raw, "series_name"),
        "series_number": number,
        "language": _str_field(raw, "language"),
        # Only the closed vocabulary passes — a creative model answer drops.
        "form": form if form in WORK_FORMS else None,
        # Only surfaces a checksum-valid ISBN-13; a misread digit drops it.
        "isbn": valid_isbn13(raw.get("isbn")),
    }


# The keys each call owns. Splitting one prompt into two means each reply is
# authoritative for its own half and silent about the other — merging on these
# sets keeps a model that volunteers an unasked-for field from half-filling it.
IDENTITY_FIELDS = (
    "title",
    "authors",
    "publisher",
    "series_name",
    "series_number",
    "language",
    "form",
    "isbn",
)
BLURB_FIELDS = ("description",)


def allowed_image_url(settings: Settings, url: str) -> bool:
    """Only images we host (the public covers bucket) may be sent for
    extraction — the endpoint must not become a free proxy for analysing
    arbitrary images with our key."""
    prefix = f"{settings.supabase_url}/storage/v1/object/public/covers/"
    return bool(settings.supabase_url) and url.startswith(prefix)


async def _ask(
    settings: Settings,
    *,
    system: str,
    instruction: str,
    urls: list[str],
    max_tokens: int,
    client: httpx.AsyncClient,
) -> dict[str, Any]:
    """One vision request: images in, the reply's JSON object out (empty when
    the model returned no text — refusal, truncation). Raises httpx errors
    upward; the router turns them into a structured 502."""
    content: list[dict[str, Any]] = [
        {"type": "image", "source": {"type": "url", "url": url}} for url in urls
    ]
    content.append({"type": "text", "text": instruction})

    resp = await client.post(
        ANTHROPIC_URL,
        headers=headers(settings),
        json={
            "model": settings.extraction_model,
            "max_tokens": max_tokens,
            # Transcription, not reasoning — and `max_tokens` caps thinking
            # and prose *together*, so an adaptive-thinking model (the
            # default on Sonnet 5+) can spend the whole budget deliberating
            # and return a reply with no text block in it at all. Off keeps
            # the budget for the JSON and the call inside our timeout.
            "thinking": {"type": "disabled"},
            "system": system,
            "messages": [{"role": "user", "content": content}],
        },
    )
    resp.raise_for_status()
    # No text block (refusal, truncation) → "" → no fields, not a 500.
    return _extract_object(reply_text(resp.json()))


async def extract_identity(
    settings: Settings,
    *,
    front_url: str | None,
    back_url: str | None,
    client: httpx.AsyncClient | None = None,
) -> dict[str, Any]:
    """The fast half: title, authors, publisher, series, language, form, ISBN.
    Both photos go in — the title is on the front, the ISBN on the back."""
    urls = [u for u in (front_url, back_url) if u]
    owns_client = client is None
    client = client or httpx.AsyncClient(timeout=45.0)
    try:
        raw = await _ask(
            settings,
            system=_IDENTITY_SYSTEM,
            instruction=(
                "Extract the catalog fields from these cover photographs "
                "(front first, then back, when both are present)."
            ),
            urls=urls,
            max_tokens=_IDENTITY_MAX_TOKENS,
            client=client,
        )
    finally:
        if owns_client:
            await client.aclose()
    cleaned = _clean(raw)
    return {k: cleaned[k] for k in IDENTITY_FIELDS}


async def extract_blurb(
    settings: Settings,
    *,
    back_url: str | None,
    front_url: str | None = None,
    client: httpx.AsyncClient | None = None,
) -> dict[str, Any]:
    """The slow half: the blurb. One photo goes in — the back cover, which is
    the side that carries one, falling back to the front when that is all the
    reader took. Sending a single side is what keeps the split from doubling
    the input bill: only the back is read twice, and the front only when it is
    the only photo there is."""
    url = back_url or front_url
    if not url:
        return {"description": None}

    owns_client = client is None
    client = client or httpx.AsyncClient(timeout=45.0)
    try:
        raw = await _ask(
            settings,
            system=_BLURB_SYSTEM,
            instruction="Transcribe the blurb from this cover photograph.",
            urls=[url],
            max_tokens=_BLURB_MAX_TOKENS,
            client=client,
        )
    finally:
        if owns_client:
            await client.aclose()
    cleaned = _clean(raw)
    return {k: cleaned[k] for k in BLURB_FIELDS}


async def extract_from_covers(
    settings: Settings,
    *,
    front_url: str | None,
    back_url: str | None,
    client: httpx.AsyncClient | None = None,
) -> dict[str, Any]:
    """Both halves at once, merged — what a caller that didn't ask for a
    specific `part` gets (an app build older than the split). Concurrent, so
    this costs the slower of the two rather than their sum, and one client
    means one connection pool for both."""
    owns_client = client is None
    client = client or httpx.AsyncClient(timeout=45.0)
    try:
        identity, blurb = await asyncio.gather(
            extract_identity(settings, front_url=front_url, back_url=back_url, client=client),
            extract_blurb(settings, back_url=back_url, front_url=front_url, client=client),
        )
    finally:
        if owns_client:
            await client.aclose()
    return {**identity, **blurb}


async def canonicalise(db: AsyncSession, fields: dict[str, Any]) -> dict[str, Any]:
    """Rewrite every name the covers gave us as the catalogue spells it.

    A title, a house, an author read off a photograph is a *name*, and names
    are how duplicate rows get made. The catalogue has one answer for "who is
    this" — a live row of that name, or, when an admin has already folded two
    rows together, the survivor of that merge — and the form should show it, so
    that the reader shelving a Malayalam printing of DC Books is offered
    DC Books rather than this cover's spelling of it (owner request,
    4 Sep 2026). Nothing is decided here: every field stays editable, and a
    name the catalogue has never seen comes back exactly as it was read.

    The publisher additionally carries its id, because the form has a slot for
    one and an id survives a later rename of the row; authors and the series
    travel as names, which the save path resolves through the same lookup.
    """
    out = dict(fields)
    name = out.get("publisher")
    if name:
        known = await catalog_service.publisher_by_name(db, name)
        if known is not None:
            out["publisher"] = known.name
            out["publisher_id"] = known.id
    authors = out.get("authors")
    if authors:
        out["authors"] = [await catalog_service.canonical_name(db, Author, a) for a in authors]
    series_name = out.get("series_name")
    if series_name:
        out["series_name"] = await catalog_service.canonical_name(db, Series, series_name)
    return out

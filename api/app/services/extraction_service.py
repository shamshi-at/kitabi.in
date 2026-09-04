"""Cover-photo extraction — prefill the add-book form from photographs.

The rescue path for books the catalog and OpenLibrary have never heard of
(disproportionately regional-language books, which is exactly Kitabi's
audience): the user has already photographed the front/back covers on the
add-book form (uploaded to the public `covers` bucket before save), so we hand
those URLs to a small vision model and get back structured fields — title,
authors, publisher, the back-cover blurb — for the form to prefill. The user
edits from there; nothing is saved without them.

Dormant unless an Anthropic API key is configured, same gate as
recommendations (CLAUDE.md rule 8: no mandatory external bill). The LLM call
is isolated in `extract_from_covers` with an injectable client so parsing and
prompt-building are unit-testable without a key.
"""

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

_SYSTEM = (
    "You read photographs of a physical book's front and/or back cover and "
    "extract catalog fields. The book may be in any language or script "
    "(Malayalam, Hindi, Tamil, English, ...) — transcribe titles and names in "
    "their printed script, do not transliterate. For `description`, use the "
    "back-cover blurb/synopsis if present, transcribed faithfully but without "
    "review quotes, price, or barcode text; keep it under 150 words. "
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
    "CRITICAL: transcribe ONLY text that is actually printed and legible in the "
    "image. Do NOT guess, translate, or invent a plausible-sounding title or "
    "name — if a field is not clearly readable, return null for it. It is far "
    "better to return null than a made-up value. "
    "Respond with ONLY a JSON object exactly like: "
    '{"title": null, "authors": [], "publisher": null, "description": null, '
    '"series_name": null, "series_number": null, "language": null, "form": null, '
    '"isbn": null}'
)


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


def _clean(raw: dict[str, Any]) -> dict[str, Any]:
    """Normalise the model's object into the response shape — strings trimmed,
    authors always a list of non-empty strings, series_number an int or None.
    Unknown keys are dropped; missing ones come back as None/[]."""

    def _str(key: str) -> str | None:
        value = raw.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
        return None

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

    form = _str("form")
    return {
        "title": _str("title"),
        "authors": authors,
        "publisher": _str("publisher"),
        "description": _str("description"),
        "series_name": _str("series_name"),
        "series_number": number,
        "language": _str("language"),
        # Only the closed vocabulary passes — a creative model answer drops.
        "form": form if form in WORK_FORMS else None,
        # Only surfaces a checksum-valid ISBN-13; a misread digit drops it.
        "isbn": valid_isbn13(raw.get("isbn")),
    }


def allowed_image_url(settings: Settings, url: str) -> bool:
    """Only images we host (the public covers bucket) may be sent for
    extraction — the endpoint must not become a free proxy for analysing
    arbitrary images with our key."""
    prefix = f"{settings.supabase_url}/storage/v1/object/public/covers/"
    return bool(settings.supabase_url) and url.startswith(prefix)


async def extract_from_covers(
    settings: Settings,
    *,
    front_url: str | None,
    back_url: str | None,
    client: httpx.AsyncClient | None = None,
) -> dict[str, Any]:
    """The one external call: send the cover photo URL(s) to the vision model
    and return the cleaned field dict. Raises httpx errors upward — the router
    turns them into a structured 502."""
    content: list[dict[str, Any]] = [
        {"type": "image", "source": {"type": "url", "url": url}}
        for url in (front_url, back_url)
        if url
    ]
    content.append(
        {
            "type": "text",
            "text": (
                "Extract the catalog fields from these cover photographs "
                "(front first, then back, when both are present)."
            ),
        }
    )

    owns_client = client is None
    client = client or httpx.AsyncClient(timeout=45.0)
    try:
        resp = await client.post(
            ANTHROPIC_URL,
            headers=headers(settings),
            json={
                "model": settings.extraction_model,
                "max_tokens": 2048,
                # Transcription, not reasoning — and `max_tokens` caps thinking
                # and prose *together*, so an adaptive-thinking model (the
                # default on Sonnet 5+) can spend the whole budget deliberating
                # and return a reply with no text block in it at all. Off keeps
                # the budget for the JSON and the call inside our 45s timeout.
                "thinking": {"type": "disabled"},
                "system": _SYSTEM,
                "messages": [{"role": "user", "content": content}],
            },
        )
        resp.raise_for_status()
        # No text block (refusal, truncation) → "" → no fields, not a 500.
        return _clean(_extract_object(reply_text(resp.json())))
    finally:
        if owns_client:
            await client.aclose()


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

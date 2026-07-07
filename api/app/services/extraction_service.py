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

from app.core.config import Settings

_ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"

_SYSTEM = (
    "You read photographs of a physical book's front and/or back cover and "
    "extract catalog fields. The book may be in any language or script "
    "(Malayalam, Hindi, Tamil, English, ...) — transcribe titles and names in "
    "their printed script, do not transliterate. For `description`, use the "
    "back-cover blurb/synopsis if present, transcribed faithfully but without "
    "review quotes, price, or barcode text; keep it under 150 words. "
    "`series_number` is the book's position if the cover shows one (e.g. "
    "'Book 3'). `language` is the language the book itself is written in, as "
    "an English word (e.g. 'Malayalam'). Use null for anything not visible — "
    "never guess or invent. Respond with ONLY a JSON object exactly like: "
    '{"title": null, "authors": [], "publisher": null, "description": null, '
    '"series_name": null, "series_number": null, "language": null}'
)


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

    return {
        "title": _str("title"),
        "authors": authors,
        "publisher": _str("publisher"),
        "description": _str("description"),
        "series_name": _str("series_name"),
        "series_number": number,
        "language": _str("language"),
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
            _ANTHROPIC_URL,
            headers={
                "x-api-key": settings.anthropic_api_key,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            json={
                "model": settings.extraction_model,
                "max_tokens": 1024,
                "system": _SYSTEM,
                "messages": [{"role": "user", "content": content}],
            },
        )
        resp.raise_for_status()
        text = resp.json()["content"][0]["text"]
        return _clean(_extract_object(text))
    finally:
        if owns_client:
            await client.aclose()

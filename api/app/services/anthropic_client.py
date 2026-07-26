"""Shared plumbing for the two Anthropic calls (recommendations, cover
extraction): the endpoint, the headers, and one careful reader for the reply.

`reply_text` exists because `resp.json()["content"][0]["text"]` is a lie the
API is under no obligation to keep true. A message's `content` is a *list of
typed blocks* and only some of them carry text: a model that thinks emits a
`thinking` block first (`{"type", "thinking", "signature"}` — no `text` key at
all), and a request the safety classifiers decline comes back HTTP 200 with
`stop_reason: "refusal"` and an empty list. Indexing block 0 blindly turns
either case into a 500 (it did, on `/catalog/cover-extract`, 26 Jul 2026 —
`KeyError: 'text'`). Walk the blocks, take the first one that is actually
text, and let the caller degrade gracefully when there is none.
"""

import logging
from typing import Any

from app.core.config import Settings

logger = logging.getLogger(__name__)

ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"
ANTHROPIC_VERSION = "2023-06-01"


def headers(settings: Settings) -> dict[str, str]:
    return {
        "x-api-key": settings.anthropic_api_key,
        "anthropic-version": ANTHROPIC_VERSION,
        "content-type": "application/json",
    }


def reply_text(payload: Any) -> str:
    """The first text block of a /v1/messages reply, or "" when there is none
    (thinking-only reply, refusal, truncation before any prose). Never raises:
    callers already treat an unparseable reply as "no fields found"."""
    payload = payload if isinstance(payload, dict) else {}
    blocks = payload.get("content")
    blocks = blocks if isinstance(blocks, list) else []
    for block in blocks:
        if isinstance(block, dict) and block.get("type") == "text":
            text = block.get("text")
            if isinstance(text, str):
                return text
    logger.warning(
        "anthropic reply carried no text block (stop_reason=%s, blocks=%s)",
        payload.get("stop_reason"),
        [b.get("type") for b in blocks if isinstance(b, dict)],
    )
    return ""

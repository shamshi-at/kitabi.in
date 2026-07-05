"""LLM-reasoned recommendations — the opt-in "quiet delight" (feature-map.md).

Dormant unless an Anthropic API key is configured (CLAUDE.md rule 8: no
mandatory external bill). Every pick carries a plain-words "why" sourced from
the reader's own ratings — never ads, never a feed. The LLM call is isolated in
`_generate_picks` so the rest is unit-testable without a key.
"""

import json
import uuid
from typing import Any

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import Settings, get_settings
from app.models import Edition, LibraryEntry, Rating, Work

_ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"

_SYSTEM = (
    "You are Kitabi's book recommender. Given a reader's rated books and a list "
    "of candidate books, choose the ones they are most likely to love. For each "
    "pick, write one warm, plain-language sentence explaining why, referencing "
    "their actual ratings or reading patterns — never marketing language. "
    'Respond with ONLY a JSON array like [{"work_id": "<id>", "why": "<sentence>"}], '
    "using work_id values from the candidates. Pick at most {limit}; fewer is fine."
)


def _author_names(work: Work) -> str:
    return ", ".join(a.name for a in work.authors) or "Unknown"


async def _rated_works(
    db: AsyncSession, user_id: uuid.UUID, limit: int = 30
) -> list[tuple[Work, int]]:
    stmt = (
        select(Work, Rating.value)
        .join(Rating, Rating.work_id == Work.id)
        .where(Rating.user_id == user_id, Rating.deleted_at.is_(None))
        .options(selectinload(Work.authors))
        .order_by(Rating.value.desc())
        .limit(limit)
    )
    return [(w, v) for w, v in (await db.execute(stmt)).all()]


async def _owned_work_ids(db: AsyncSession, user_id: uuid.UUID) -> set[uuid.UUID]:
    stmt = (
        select(Edition.work_id)
        .join(LibraryEntry, LibraryEntry.edition_id == Edition.id)
        .where(LibraryEntry.user_id == user_id, LibraryEntry.deleted_at.is_(None))
    )
    return {row for (row,) in (await db.execute(stmt)).all()}


async def _candidate_works(
    db: AsyncSession, exclude: set[uuid.UUID], limit: int = 40
) -> list[Work]:
    stmt = (
        select(Work)
        .options(selectinload(Work.authors), selectinload(Work.editions))
        .where(Work.deleted_at.is_(None))
        .order_by(Work.aggregate_rating.desc().nulls_last(), Work.created_at.desc())
        .limit(limit + len(exclude))
    )
    works = list((await db.execute(stmt)).scalars().all())
    return [w for w in works if w.id not in exclude][:limit]


def _build_prompt(rated: list[tuple[Work, int]], candidates: list[Work]) -> str:
    liked = "\n".join(f"- {w.title} by {_author_names(w)} — rated {v}/5" for w, v in rated)
    options = "\n".join(f"- {w.id}: {w.title} by {_author_names(w)}" for w in candidates)
    return f"Books the reader rated:\n{liked}\n\nCandidates:\n{options}"


def _extract_json(text: str) -> list[dict[str, Any]]:
    start = text.find("[")
    end = text.rfind("]")
    if start == -1 or end == -1:
        return []
    try:
        parsed = json.loads(text[start : end + 1])
    except json.JSONDecodeError:
        return []
    return parsed if isinstance(parsed, list) else []


async def _generate_picks(
    settings: Settings,
    rated: list[tuple[Work, int]],
    candidates: list[Work],
    limit: int,
    client: httpx.AsyncClient | None = None,
) -> list[dict[str, Any]]:
    """The one external call. Split out so callers can inject a fake client."""
    owns_client = client is None
    client = client or httpx.AsyncClient(timeout=30.0)
    try:
        resp = await client.post(
            _ANTHROPIC_URL,
            headers={
                "x-api-key": settings.anthropic_api_key,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            json={
                "model": settings.recs_model,
                "max_tokens": 1024,
                "system": _SYSTEM.format(limit=limit),
                "messages": [{"role": "user", "content": _build_prompt(rated, candidates)}],
            },
        )
        resp.raise_for_status()
        text = resp.json()["content"][0]["text"]
        return _extract_json(text)
    finally:
        if owns_client:
            await client.aclose()


async def recommend(
    db: AsyncSession,
    user_id: uuid.UUID,
    *,
    limit: int = 5,
    client: httpx.AsyncClient | None = None,
) -> list[tuple[Work, str]]:
    """Returns [(work, why)]. Empty when disabled, cold-start (no ratings), or
    when there are no candidates — the caller reports `enabled` separately."""
    settings = get_settings()
    if not settings.recommendations_enabled:
        return []

    rated = await _rated_works(db, user_id)
    if not rated:
        return []  # reasoned from ratings only — nothing to reason from yet

    exclude = {w.id for w, _ in rated} | await _owned_work_ids(db, user_id)
    candidates = await _candidate_works(db, exclude)
    if not candidates:
        return []

    picks = await _generate_picks(settings, rated, candidates, limit, client=client)
    by_id = {str(w.id): w for w in candidates}
    result: list[tuple[Work, str]] = []
    for pick in picks:
        work = by_id.get(str(pick.get("work_id")))
        why = pick.get("why")
        if work is not None and isinstance(why, str) and why.strip():
            result.append((work, why.strip()))
    return result[:limit]

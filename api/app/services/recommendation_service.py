"""LLM-reasoned recommendations — the opt-in "quiet delight" (feature-map.md).

Dormant unless an Anthropic API key is configured (CLAUDE.md rule 8: no
mandatory external bill). Every pick carries a plain-words "why" sourced from
the reader's own ratings — never ads, never a feed. The LLM call is isolated in
`_generate_picks` so the rest is unit-testable without a key.
"""

import hashlib
import json
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import Settings, get_settings
from app.models import FEATURE_RECOMMENDATIONS, Edition, LibraryEntry, Rating, RecCache, Work
from app.services import llm_quota
from app.services.anthropic_client import ANTHROPIC_URL, headers, reply_text

_SYSTEM = (
    "You are Kitabi's book recommender. Given a reader's rated books and a list "
    "of candidate books, choose the ones they are most likely to love. For each "
    "pick, write one warm, plain-language sentence explaining why, referencing "
    "their actual ratings or reading patterns — never marketing language. "
    # Braces in the JSON example are doubled so str.format() emits them
    # literally and only substitutes {limit} — a single brace here makes
    # .format() read the example as a field and raise KeyError at call time
    # (never caught by tests, which only exercise the disabled path).
    'Respond with ONLY a JSON array like [{{"work_id": "<id>", "why": "<sentence>"}}], '
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
            ANTHROPIC_URL,
            headers=headers(settings),
            json={
                "model": settings.recs_model,
                "max_tokens": 1024,
                "system": _SYSTEM.format(limit=limit),
                "messages": [{"role": "user", "content": _build_prompt(rated, candidates)}],
            },
        )
        resp.raise_for_status()
        # No text block (thinking-only reply, refusal) → "" → no picks, not a 500.
        return _extract_json(reply_text(resp.json()))
    finally:
        if owns_client:
            await client.aclose()


def _fingerprint(
    rated: list[tuple[Work, int]],
    owned: set[uuid.UUID],
    limit: int,
    model: str,
) -> str:
    """Hash of exactly what feeds the prompt. Sorted, so ordering artifacts of
    the queries can't fake a change; includes the model so a model bump
    refreshes everyone rather than serving picks reasoned by its predecessor."""
    payload = json.dumps(
        {
            "rated": sorted((str(w.id), v) for w, v in rated),
            "owned": sorted(str(w) for w in owned),
            "limit": limit,
            "model": model,
        },
        separators=(",", ":"),
    )
    return hashlib.sha256(payload.encode()).hexdigest()


async def _hydrate_cached(
    db: AsyncSession, picks: list[dict[str, Any]], limit: int
) -> list[tuple[Work, str]]:
    """Cached picks back into live rows, in pick order. The cache stores work
    ids, never work data, so a book deleted or edited since generation is
    dropped or shown current — a vanished pick just shortens the list."""
    ids: list[uuid.UUID] = []
    for pick in picks:
        try:
            ids.append(uuid.UUID(str(pick.get("work_id"))))
        except ValueError:
            continue
    if not ids:
        return []
    stmt = (
        select(Work)
        .options(selectinload(Work.authors), selectinload(Work.editions))
        .where(Work.id.in_(ids), Work.deleted_at.is_(None))
    )
    by_id = {w.id: w for w in (await db.execute(stmt)).scalars().all()}
    result: list[tuple[Work, str]] = []
    for pick in picks:
        work = by_id.get(uuid.UUID(str(pick["work_id"]))) if pick.get("work_id") else None
        why = pick.get("why")
        if work is not None and isinstance(why, str) and why.strip():
            result.append((work, why.strip()))
    return result[:limit]


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

    owned = await _owned_work_ids(db, user_id)

    # The picks are a pure function of what feeds the prompt, and none of it
    # changes between two visits to the screen — so an unchanged fingerprint
    # within the TTL is served from the cache: zero spend, zero quota, and the
    # check sits BEFORE `consume` on purpose, so a reader who is over quota
    # still sees their standing picks instead of an error (owner request,
    # 2 Sep 2026). Only a changed shelf or an aged cache pays for regeneration.
    fingerprint = _fingerprint(rated, owned, limit, settings.recs_model)
    cached = await db.get(RecCache, user_id)
    if (
        cached is not None
        and cached.fingerprint == fingerprint
        and datetime.now(UTC) - cached.generated_at < timedelta(days=settings.recs_cache_ttl_days)
    ):
        hydrated = await _hydrate_cached(db, cached.picks, limit)
        # Every cached pick vanished (deleted/merged away) → nothing worth
        # serving; fall through and regenerate rather than showing a blank.
        if hydrated:
            return hydrated

    exclude = {w.id for w, _ in rated} | owned
    candidates = await _candidate_works(db, exclude)
    if not candidates:
        return []

    # Metered here rather than in the router because this is the exact line the
    # spend happens on: every `return []` above is a free no-op, and a reader
    # with no ratings yet would otherwise burn their daily quota re-opening a
    # screen that never calls Anthropic at all. Raises 429/503 (llm_quota).
    await llm_quota.consume(db, user_id, FEATURE_RECOMMENDATIONS, settings=settings)

    picks = await _generate_picks(settings, rated, candidates, limit, client=client)
    by_id = {str(w.id): w for w in candidates}
    result: list[tuple[Work, str]] = []
    for pick in picks:
        work = by_id.get(str(pick.get("work_id")))
        why = pick.get("why")
        if work is not None and isinstance(why, str) and why.strip():
            result.append((work, why.strip()))
    result = result[:limit]

    # Only a non-empty answer is worth pinning for the TTL: caching an empty
    # one would freeze "nothing for you" for a week when the next attempt
    # might do better (a flaky reply, a refusal). The retry costs quota — the
    # quota is the backstop, and that is its job.
    if result:
        stored = [{"work_id": str(w.id), "why": why} for w, why in result]
        if cached is None:
            db.add(
                RecCache(
                    user_id=user_id,
                    fingerprint=fingerprint,
                    picks=stored,
                    generated_at=datetime.now(UTC),
                )
            )
        else:
            cached.fingerprint = fingerprint
            cached.picks = stored
            cached.generated_at = datetime.now(UTC)
        await db.commit()
    return result

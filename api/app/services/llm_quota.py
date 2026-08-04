"""Daily spend limits for the endpoints that call Anthropic.

`GET /recommendations` and `POST /catalog/cover-extract` are the only two
endpoints in the API where one request costs money. Both require auth, but auth
here means "any Google account", so before this existed the ceiling on the bill
was the caller's patience — a script with a handful of free accounts could run
it up without touching anything else.

Two limits, deliberately different in kind:

* a **per-reader daily quota**, so one account can't be the whole problem, and
* a **global daily circuit breaker**, which is the number that actually bounds
  the bill when the problem is fifty accounts instead of one.

Postgres, not Redis (CLAUDE.md rule 8). One narrow table and a SUM over a
single day's rows costs far less than a service that adds a bill.

# SCALE: the global check is `SUM(count) WHERE day = today`, index-served over
# at most (readers × features) rows per day. If that ever gets hot, keep a
# running total in a one-row table rather than reaching for Redis.

**Quota is consumed before the call, and is not refunded if the call fails.**
That is the fail-closed choice on purpose: a refund path means a caller who can
reliably make the upstream fail gets unlimited free attempts, and a request that
fails *after* generation has already cost money anyway.
"""

import uuid
from datetime import UTC, date, datetime

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.models import FEATURE_COVER_EXTRACT, FEATURE_RECOMMENDATIONS, LLM_FEATURES, LlmUsage

# The unique constraint the upsert conflicts on. Named explicitly (rather than
# inferred from columns) so a migration that renames it fails loudly here
# instead of silently degrading the upsert into a plain insert.
_CONFLICT = "uq_llm_usage_user_feature_day"


def utc_day() -> date:
    """Today in UTC — the quota's reset boundary (CLAUDE.md rule 5)."""
    return datetime.now(UTC).date()


def _seconds_until_reset(now: datetime | None = None) -> int:
    """Seconds until the next UTC midnight, for the `Retry-After` header."""
    now = now or datetime.now(UTC)
    tomorrow = datetime.combine(now.date(), datetime.min.time(), tzinfo=UTC)
    return max(1, int((tomorrow.timestamp() + 86_400) - now.timestamp()))


def quota_for(settings: Settings, feature: str) -> int:
    """The per-reader daily cap for a feature. 0 means "no limit"."""
    if feature == FEATURE_RECOMMENDATIONS:
        return settings.llm_daily_quota_recommendations
    if feature == FEATURE_COVER_EXTRACT:
        return settings.llm_daily_quota_cover_extract
    raise ValueError(f"unknown LLM feature: {feature}")


async def global_total(db: AsyncSession, day: date) -> int:
    """Paid calls across every reader and feature on `day`."""
    total = await db.scalar(
        select(func.coalesce(func.sum(LlmUsage.count), 0)).where(LlmUsage.day == day)
    )
    return int(total or 0)


async def consume(
    db: AsyncSession,
    user_id: uuid.UUID,
    feature: str,
    *,
    settings: Settings | None = None,
    day: date | None = None,
) -> int:
    """Record one paid call and enforce both limits. Returns the reader's new
    count for the day.

    Raises `HTTPException` — 503 when the global breaker is open, 429 (with
    `Retry-After`) when this reader is over their own quota. Raising HTTP from
    a service matches the existing convention (see `sitemap_service`), and the
    structured `{"code", "message"}` detail is CLAUDE.md's error contract.
    """
    if feature not in LLM_FEATURES:
        raise ValueError(f"unknown LLM feature: {feature}")
    settings = settings or get_settings()
    day = day or utc_day()

    # Global ceiling first — it's the cheaper rejection, and a reader shouldn't
    # spend their own quota on a request the breaker was going to refuse.
    #
    # This one is check-then-act, so concurrent requests can overshoot the cap
    # by the number in flight. That is fine and intentional: it's a ceiling with
    # slack, not an exact budget, and locking a global counter would serialize
    # every paid call in the API.
    if settings.llm_daily_global_cap > 0:
        if await global_total(db, day) >= settings.llm_daily_global_cap:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail={
                    # Deliberately vague to the caller: "we're at our budget for
                    # today" is not something an attacker needs confirmed.
                    "code": "llm_unavailable",
                    "message": "This isn't available right now — please try again later.",
                },
                headers={"Retry-After": str(_seconds_until_reset())},
            )

    # …then the per-reader counter, atomically. INSERT … ON CONFLICT DO UPDATE
    # increments and reads back the new value in ONE statement, so two
    # concurrent requests can never both read "one under the cap" and both
    # proceed. A read-then-write would be exactly that race.
    used = await db.scalar(
        pg_insert(LlmUsage)
        .values(id=uuid.uuid4(), user_id=user_id, feature=feature, day=day, count=1)
        .on_conflict_do_update(
            constraint=_CONFLICT,
            set_={"count": LlmUsage.__table__.c.count + 1, "updated_at": func.now()},
        )
        .returning(LlmUsage.count)
    )
    # Commit the reservation immediately: it has to survive whatever the paid
    # call does next, including the request failing. `get_db` rolls back an
    # uncommitted session, which would hand back a free retry.
    await db.commit()

    cap = quota_for(settings, feature)
    if cap > 0 and int(used) > cap:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail={
                "code": "quota_exceeded",
                "message": "You've reached today's limit for this. It resets at midnight UTC.",
            },
            headers={"Retry-After": str(_seconds_until_reset())},
        )
    return int(used)

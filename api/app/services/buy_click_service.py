"""Recording buy-link clicks (`models/buy_click.py`).

Two doors, one table:

- `record_app` — a signed-in reader's batch from the app's outbox. Idempotent
  on the device-generated id.
- `record_web` — one anonymous click from the website. This is the **one
  write the public web makes** (owner decision, 5 Oct 2026; CLAUDE.md says the
  public web is strictly read-only, and this is the named exception). It is
  kept narrow on purpose: it can only append a row that says "somebody opened
  shop X for edition Y just now", for an edition and a shop that really
  exist, and no more than a bounded number of them.

Neither ever raises to its caller for a row it will not store. Telemetry that
can fail a request, or make an outbox retry a batch that can never succeed, is
telemetry that will one day break the thing it was watching.
"""

from __future__ import annotations

import time
import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import SURFACE_APP, SURFACE_WEB, BuyClick, Edition, Work
from app.services import buy_links

MAX_EVENTS_PER_BATCH = 200

#: The app's clock is the reader's phone. A click "from" next year or from
#: before the feature existed is a wrong clock, and it would land in the wrong
#: week of every report — so it is stamped with the time it arrived instead.
MAX_FUTURE_SKEW = timedelta(minutes=10)
MAX_AGE = timedelta(days=90)

#: Ceilings on the anonymous door, per process. A reference site's buy button
#: is clicked a few times an hour; these are far above honest traffic and far
#: below what would matter to the database. Past them a click is dropped, not
#: refused — the visitor is on their way to the shop either way.
#: SCALE: in-process, so each API instance counts separately and a deploy
#: resets them. Fine for one instance; move to Postgres if there are several.
WEB_PER_MINUTE = 60
WEB_PER_DAY = 5000

_web_window: dict[str, list[float]] = {"minute": [], "day": []}


def _web_allowed(now: float | None = None) -> bool:
    """Whether the anonymous door may take one more click right now."""
    now = time.monotonic() if now is None else now
    minute = _web_window["minute"] = [t for t in _web_window["minute"] if now - t < 60]
    day = _web_window["day"] = [t for t in _web_window["day"] if now - t < 86400]
    if len(minute) >= WEB_PER_MINUTE or len(day) >= WEB_PER_DAY:
        return False
    minute.append(now)
    day.append(now)
    return True


def reset_web_limits() -> None:
    """For tests: the counters are module state."""
    _web_window["minute"] = []
    _web_window["day"] = []


def _when(occurred_at: datetime, now: datetime) -> datetime:
    """The device's time for the click, unless its clock is plainly wrong."""
    if occurred_at.tzinfo is None:
        occurred_at = occurred_at.replace(tzinfo=UTC)
    if occurred_at > now + MAX_FUTURE_SKEW or occurred_at < now - MAX_AGE:
        return now
    return occurred_at


async def _works_of(db: AsyncSession, edition_ids: set[uuid.UUID]) -> dict[uuid.UUID, uuid.UUID]:
    """edition → work, for editions and works that are both still live. A
    click on a book that has since been removed is not worth a row that every
    report would then have to explain."""
    if not edition_ids:
        return {}
    rows = await db.execute(
        select(Edition.id, Edition.work_id)
        .join(Work, Work.id == Edition.work_id)
        .where(
            Edition.id.in_(edition_ids),
            Edition.deleted_at.is_(None),
            Work.deleted_at.is_(None),
        )
    )
    return {edition_id: work_id for edition_id, work_id in rows.all()}


async def record_app(db: AsyncSession, user_id: uuid.UUID, events: list) -> int:
    """Append a signed-in reader's clicks. Returns how many were stored-or-
    already-there; unknown shops, unknown editions and anything past the batch
    cap are dropped silently."""
    events = events[:MAX_EVENTS_PER_BATCH]
    if not events:
        return 0
    works = await _works_of(db, {e.edition_id for e in events})
    now = datetime.now(UTC)
    rows = []
    for e in events:
        key = buy_links.retailer_key(e.retailer)
        work_id = works.get(e.edition_id)
        if key is None or work_id is None:
            continue
        rows.append(
            {
                "id": e.id,
                "user_id": user_id,
                "work_id": work_id,
                "edition_id": e.edition_id,
                "retailer": key,
                "surface": SURFACE_APP,
                "affiliate": bool(e.affiliate),
                "occurred_at": _when(e.occurred_at, now),
            }
        )
    if not rows:
        return 0
    await db.execute(pg_insert(BuyClick).values(rows).on_conflict_do_nothing(index_elements=["id"]))
    await db.commit()
    return len(rows)


async def record_web(
    db: AsyncSession, edition_id: uuid.UUID, retailer: object, *, affiliate: bool = False
) -> bool:
    """Append one anonymous website click. True when a row was written."""
    key = buy_links.retailer_key(retailer)
    if key is None:
        return False
    work_id = (await _works_of(db, {edition_id})).get(edition_id)
    if work_id is None:
        return False
    # Counted only once the click is known to be real, so junk cannot use up
    # the allowance honest clicks need.
    if not _web_allowed():
        return False
    db.add(
        BuyClick(
            user_id=None,
            work_id=work_id,
            edition_id=edition_id,
            retailer=key,
            surface=SURFACE_WEB,
            affiliate=affiliate,
            occurred_at=datetime.now(UTC),
        )
    )
    await db.commit()
    return True

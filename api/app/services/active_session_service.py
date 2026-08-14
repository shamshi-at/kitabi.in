"""The live reading sitting: read, start/refresh, clear — plus the push that
tells the reader's *other* installs about it.

The push is what makes this "live" at all. The sync engine drains on a
15-minute workmanager cadence, which is fine for a finished sitting and useless
for a running clock, so start/stop fans out a data message to every device
token on the account. The originating install ignores its own event by
comparing `device_id`; that is cheaper and more robust than trying to exclude
one token, since a device can hold several over its life.

Every push is best-effort and must never fail the request: a reader whose timer
would not start because another phone was unreachable is a worse bug than a
second device that finds out a few seconds late (it re-reads on foreground).
"""

import uuid

from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.active_reading_session import ActiveReadingSession
from app.schemas.reading import ActiveSessionIn

#: Data-message keys. Kept as constants because the app matches on them and a
#: typo here is a silent no-op on the other device.
EVENT_STARTED = "reading_started"
EVENT_STOPPED = "reading_stopped"


async def get(db: AsyncSession, user_id: uuid.UUID) -> ActiveReadingSession | None:
    return await db.get(ActiveReadingSession, user_id)


async def start(
    db: AsyncSession, user_id: uuid.UUID, payload: ActiveSessionIn
) -> ActiveReadingSession:
    """Upsert the account's live sitting.

    Idempotent on purpose: the app re-sends this on foreground and after a
    check-in answer, so it doubles as "refresh what the other devices know".
    """
    values = {
        "user_id": user_id,
        "session_id": payload.session_id,
        "library_entry_id": payload.library_entry_id,
        "started_at": payload.started_at,
        "page_start": payload.page_start,
        "confirmed_at": payload.confirmed_at,
        "device_id": payload.device_id,
    }
    stmt = (
        pg_insert(ActiveReadingSession)
        .values(**values)
        .on_conflict_do_update(
            index_elements=[ActiveReadingSession.user_id],
            set_={k: v for k, v in values.items() if k != "user_id"},
        )
        .returning(ActiveReadingSession)
    )
    row = (await db.execute(stmt)).scalar_one()
    await db.commit()
    return row


async def clear(db: AsyncSession, user_id: uuid.UUID) -> ActiveReadingSession | None:
    """End the live sitting, returning what was running (or None).

    The finished `reading_sessions` row is written by whichever device stopped
    it and travels the normal sync path — this only takes down the live one.
    """
    row = await db.get(ActiveReadingSession, user_id)
    if row is None:
        return None
    await db.execute(delete(ActiveReadingSession).where(ActiveReadingSession.user_id == user_id))
    await db.commit()
    return row


async def stale_before(db: AsyncSession, cutoff) -> list[ActiveReadingSession]:
    """Live sittings older than [cutoff] — the sweeper's input.

    A device that is uninstalled, wiped or simply never comes back would
    otherwise leave a timer running on the account forever, and every other
    device would keep showing it. The app's own safety net stops a sitting at
    start + 90 minutes; this is the server-side mirror of that promise.
    """
    result = await db.execute(
        select(ActiveReadingSession).where(ActiveReadingSession.started_at < cutoff)
    )
    return list(result.scalars().all())

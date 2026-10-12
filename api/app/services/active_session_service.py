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
from datetime import datetime, timedelta

from sqlalchemy import delete, func, select
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


#: How long after a sitting's last sign of life the server gives up on it.
#: The app stops a sitting itself at check-in delay + grace after the start or
#: the last "still reading" — at most 240 + 30 minutes. A row still here a day
#: past that belongs to a device that will never send its DELETE (uninstalled,
#: wiped, never opened again), so taking it down cannot cut a live sitting
#: short. Generous on purpose: an app that predates the overdue-stop rule reads
#: an empty server as "stopped elsewhere" and drops its sitting unlogged, so
#: the sweep must only ever reach sittings that device has long since stopped.
STALE_AFTER = timedelta(hours=24)


def _last_alive():
    """The later of `started_at` and `confirmed_at` — the same base the app's
    `readingSessionDeadline` counts from (a "still reading" moves it)."""
    return func.greatest(
        ActiveReadingSession.started_at,
        func.coalesce(ActiveReadingSession.confirmed_at, ActiveReadingSession.started_at),
    )


async def stale_before(db: AsyncSession, cutoff: datetime) -> list[ActiveReadingSession]:
    """Live sittings whose last sign of life is older than [cutoff].

    A device that is uninstalled, wiped or simply never comes back would
    otherwise leave a timer running on the account forever, and every other
    device would keep showing it. The app's own safety net stops a sitting at
    its deadline; this is the server-side mirror of that promise.
    """
    result = await db.execute(select(ActiveReadingSession).where(_last_alive() < cutoff))
    return list(result.scalars().all())


async def sweep_stale(db: AsyncSession, now: datetime) -> list[ActiveReadingSession]:
    """Take down every live sitting abandoned for longer than [STALE_AFTER],
    returning what was removed so the caller can tell the reader's devices.

    The delete re-checks the cutoff rather than deleting by user id alone: a
    device that refreshes or restarts its sitting between the read and the
    delete has just proven it is alive, and must keep it.
    """
    cutoff = now - STALE_AFTER
    rows = await stale_before(db, cutoff)
    if not rows:
        return []
    deleted = (
        await db.execute(
            delete(ActiveReadingSession)
            .where(
                ActiveReadingSession.user_id.in_([r.user_id for r in rows]),
                _last_alive() < cutoff,
            )
            .returning(ActiveReadingSession.user_id)
        )
    ).scalars()
    gone = set(deleted)
    await db.commit()
    return [r for r in rows if r.user_id in gone]

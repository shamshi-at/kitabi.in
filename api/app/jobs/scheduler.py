"""APScheduler setup.

Runs inside the single API process: every job must take a Postgres advisory
lock so a second replica can never double-run (pattern from rupee-diary).
Jobs to come: Supabase keep-warm ping, lending-due reminders.
"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

scheduler = AsyncIOScheduler(timezone="UTC")

# Stable lock ids per job family (int64 namespace for pg_try_advisory_lock).
LOCK_KEEP_WARM = 1001
LOCK_LENDING_REMINDER = 1002


@asynccontextmanager
async def advisory_lock(session: AsyncSession, lock_id: int) -> AsyncIterator[bool]:
    """Try to take a session-scoped advisory lock; yields False if another
    instance holds it (job should skip silently)."""
    if session.bind and session.bind.dialect.name != "postgresql":
        yield True
        return
    acquired = (
        await session.execute(text("SELECT pg_try_advisory_lock(:id)"), {"id": lock_id})
    ).scalar_one()
    try:
        yield bool(acquired)
    finally:
        if acquired:
            await session.execute(text("SELECT pg_advisory_unlock(:id)"), {"id": lock_id})


def start() -> None:
    from app.jobs.keep_warm import keep_warm

    # Every 6 hours — comfortably under Supabase's 7-day idle-pause threshold.
    scheduler.add_job(keep_warm, "interval", hours=6, id="keep_warm", replace_existing=True)
    scheduler.start()


def shutdown() -> None:
    if scheduler.running:
        scheduler.shutdown(wait=False)

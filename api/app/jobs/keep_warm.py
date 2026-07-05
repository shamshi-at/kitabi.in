"""Supabase keep-warm — the free tier pauses a project after 7 days idle
(CLAUDE.md lesson). A tiny periodic query keeps it awake. Guarded by an advisory
lock so a second replica never double-runs."""

import logging

from sqlalchemy import text

from app.core.db import SessionLocal
from app.jobs.scheduler import LOCK_KEEP_WARM, advisory_lock

logger = logging.getLogger(__name__)


async def keep_warm() -> None:
    async with SessionLocal() as session:
        async with advisory_lock(session, LOCK_KEEP_WARM) as acquired:
            if not acquired:
                return
            await session.execute(text("SELECT 1"))
    logger.debug("keep-warm ping ok")

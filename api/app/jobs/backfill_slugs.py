"""Fill in missing public URL slugs.

`slug_service.ensure_slug` runs on every creation path that goes through
`catalog_service`, but the catalog also grows by routes that don't: the ETL bulk
loads (`etl/04_load.sql`) write rows with plain SQL, and any future importer
will be written by someone who has never read slug_service. A row without a slug
isn't broken — it stays reachable by UUID — but it can't have a clean public URL,
and it silently won't.

So rather than trusting every writer to remember, this sweeps up afterwards. It
is idempotent, bounded per run, and cheap to no-op: once the catalog is filled
the query matches nothing and the job costs one indexed lookup.

Runs hourly (not daily) so a fresh import becomes publicly linkable within the
hour rather than the next day.
"""

import logging

from app.core.db import SessionLocal
from app.jobs.scheduler import LOCK_BACKFILL_SLUGS, advisory_lock
from app.services import slug_service

logger = logging.getLogger(__name__)


async def backfill_slugs() -> None:
    async with SessionLocal() as session:
        async with advisory_lock(session, LOCK_BACKFILL_SLUGS) as acquired:
            if not acquired:
                return  # another replica is doing it
            filled = await slug_service.backfill_missing(session)
            if filled:
                logger.info("backfill_slugs: assigned %s slug(s)", filled)

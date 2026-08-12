"""Fill the cross-script search columns on Series rows that predate them.

Migration 000043 added `name_translit` / `name_fold` but left them NULL: doing
it in SQL would need a copy of the transliteration tables inside the migration,
and a migration that imports application code is welded to a moving target
(000038, 000041). The ORM hooks fill them on the next write — but a series row
nobody edits is never written again, and until then a Malayalam series name
cannot be found by a Latin query at all.

So this sweeps up, the same shape as backfill_slugs: idempotent, bounded, and a
single indexed no-op once the catalogue is clean. Touching the row is the whole
trick — `models/translit_hooks` computes both columns on update.
"""

import logging

from sqlalchemy import or_, select

from app.core.db import SessionLocal
from app.jobs.scheduler import LOCK_BACKFILL_SERIES, advisory_lock
from app.models import Series
from app.services.translit import fold, transliterate

logger = logging.getLogger(__name__)


async def backfill_series_search(*, limit: int = 500) -> int:
    """Returns how many rows were filled."""
    async with SessionLocal() as db:
        async with advisory_lock(db, LOCK_BACKFILL_SERIES) as acquired:
            if not acquired:
                return 0  # another replica is doing it
            rows = (
                (
                    await db.execute(
                        select(Series)
                        .where(
                            Series.deleted_at.is_(None),
                            or_(Series.name_translit.is_(None), Series.name_fold.is_(None)),
                        )
                        .limit(limit)
                    )
                )
                .scalars()
                .all()
            )
            filled = 0
            for row in rows:
                # Assigned explicitly as well as via the hook: a name that
                # romanizes to nothing would otherwise leave both columns NULL
                # and be re-selected on every run, forever.
                row.name_translit = transliterate(row.name) or ""
                row.name_fold = fold(row.name) or ""
                filled += 1
            if filled:
                await db.commit()
                logger.info("backfill_series_search: filled %s series row(s)", filled)
            return filled

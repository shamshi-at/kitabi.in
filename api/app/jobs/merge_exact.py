"""Fold exact-name duplicate authors and publishers together.

Owner decision: an identical normalised name in a catalogue this size is
overwhelmingly one entity, and every merge is reversible by clearing one column,
so review adds delay without adding safety *for this case alone*. Everything
softer — word order, spelling, transliteration — stays in the console queue for
a human.

Runs on a schedule rather than once, because the catalogue keeps growing: the
ETL bulk loads and OpenLibrary's cache-on-first-use both create authors, and
they create duplicates the same way they did the first time.
"""

import logging

from app.core.db import SessionLocal
from app.jobs.scheduler import LOCK_MERGE_EXACT, advisory_lock
from app.services import merge_service

logger = logging.getLogger(__name__)


async def merge_exact_duplicates() -> None:
    async with SessionLocal() as session:
        async with advisory_lock(session, LOCK_MERGE_EXACT) as acquired:
            if not acquired:
                return
            for kind in ("authors", "publishers"):
                merged = await merge_service.auto_merge_exact(session, kind)
                if merged:
                    logger.info("merge_exact: folded %s duplicate %s", merged, kind)

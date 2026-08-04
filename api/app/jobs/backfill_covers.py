"""Copy hotlinked catalogue covers into our own Supabase bucket.

770 of the catalogue's 772 covers point at covers.openlibrary.org. The edge
proxy means no reader waits on that origin, but a cache is not ownership: if the
image is removed or the host is down when an edge entry expires, the cover is
gone. This walks the backlog a few at a time and repoints each edition at the
copy in our bucket.

Deliberately slow. OpenLibrary is a free service run by a non-profit and it rate
-limits; a backfill that tries to move 770 images at once is abusive and will be
throttled anyway. A small batch on a short interval clears the backlog in a few
hours and then costs one indexed query per run forever.

Dormant without SUPABASE_SERVICE_ROLE_KEY (rule 8).
"""

import asyncio
import logging

import httpx
from sqlalchemy import or_, select

from app.core.config import get_settings
from app.core.db import SessionLocal
from app.jobs.scheduler import LOCK_BACKFILL_COVERS, advisory_lock
from app.models import Edition
from app.services import cover_storage

logger = logging.getLogger(__name__)

# Per run. Raised from 25 (owner request) to clear the backlog in ~30 minutes
# rather than ~5 hours. At this size a run makes ~100 requests over ~90s — about
# 1.1/second while running, then idle for the rest of the interval, which
# averages well under one request a second. Still a trickle by any reasonable
# reading; it is a burst only relative to the previous setting.
BATCH = 100
# Between fetches. Kept non-zero deliberately: the batch size is what changed,
# not the willingness to hammer a free service flat out.
PAUSE_SECONDS = 0.3
# Consecutive transient failures that mean "stop and come back later".
#
# This matters far more now than at 25/run. A transient failure is usually a
# 429, and continuing to push through a rate limit is both rude and useless —
# every subsequent request fails too. Bailing out early keeps a throttled run
# short instead of spending 90 seconds being refused, and the next run picks up
# where this one stopped. A single blip is not a signal, so it takes a run of
# them.
MAX_CONSECUTIVE_FAILURES = 5


async def backfill_covers(client: httpx.AsyncClient | None = None) -> None:
    """`client` is injectable so tests can drive the whole job without the
    network — the same shape as `recommendation_service.recommend`."""
    settings = get_settings()
    if not cover_storage.configured(settings):
        return  # dormant: no key, no external call

    async with SessionLocal() as session:
        async with advisory_lock(session, LOCK_BACKFILL_COVERS) as acquired:
            if not acquired:
                return

            base = settings.supabase_url.rstrip("/")
            rows = (
                (
                    await session.execute(
                        select(Edition)
                        .where(
                            Edition.cover_url.is_not(None),
                            Edition.deleted_at.is_(None),
                            # Anything not already ours. Cheap to evaluate and
                            # what makes re-running a no-op once the backlog is
                            # cleared.
                            or_(
                                Edition.cover_url.not_like(f"{base}/storage/v1/object/public/%"),
                                Edition.cover_url.is_(None),
                            ),
                        )
                        .order_by(Edition.created_at)
                        .limit(BATCH)
                    )
                )
                .scalars()
                .all()
            )
            if not rows:
                return

            moved = dropped = 0
            consecutive_failures = 0
            owns_client = client is None
            client = client or httpx.AsyncClient(timeout=20)
            try:
                for edition in rows:
                    fetched = await cover_storage.fetch_cover(client, edition.cover_url)
                    if fetched.gone or fetched.body:
                        consecutive_failures = 0
                    else:
                        consecutive_failures += 1
                        if consecutive_failures >= MAX_CONSECUTIVE_FAILURES:
                            # Almost certainly being throttled. Stop pushing.
                            logger.info(
                                "backfill_covers: %s consecutive failures — backing off",
                                consecutive_failures,
                            )
                            break

                    if fetched.gone:
                        # A cover that definitively does not exist. Clearing it
                        # is the honest outcome — the app and the site both
                        # render a typeset cover for null, which is better than
                        # a URL that will never load, and it stops this row
                        # being retried every run forever.
                        edition.cover_url = None
                        dropped += 1
                    elif fetched.body:
                        stored = await cover_storage.store_cover(
                            client, settings, edition.id, fetched.body, fetched.content_type
                        )
                        if stored:
                            edition.cover_url = stored
                            moved += 1
                    # Anything else was transient; leave the row untouched and
                    # let the next run try again.
                    await asyncio.sleep(PAUSE_SECONDS)
            finally:
                if owns_client:
                    await client.aclose()

            if moved or dropped:
                await session.commit()
                logger.info("backfill_covers: moved %s, dropped %s dead", moved, dropped)

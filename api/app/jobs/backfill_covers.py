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

# Per run. Small on purpose — see the note about OpenLibrary above.
BATCH = 25
# Between fetches, so a run is a trickle rather than a burst.
PAUSE_SECONDS = 0.4


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
            owns_client = client is None
            client = client or httpx.AsyncClient(timeout=20)
            try:
                for edition in rows:
                    fetched = await cover_storage.fetch_cover(client, edition.cover_url)
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

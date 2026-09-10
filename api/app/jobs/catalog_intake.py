"""The daily catalogue intake job.

Runs in the API process on Railway, beside `backfill_covers` and
`merge_exact`, under a Postgres advisory lock so a second replica can never
double-run it (the pattern every job here uses).

Three steps, deliberately in this order and deliberately separable:

1. **discover** — ask each source adapter what it can see. Writes candidates
   to `catalog_intake` and touches no catalogue table.
2. **rescreen** — re-run the gate over rows held as `incomplete`, so a gate
   fix releases what it was holding without re-crawling anything.
3. **promote** — turn at most `catalog_intake_daily_limit` complete candidates
   into books.

**Dormant unless `CATALOG_INTAKE_ENABLED` is set** (rule 8's shape, applied to
writes rather than to spend): with the flag off the job returns before making
a single request, so merging it to main publishes nothing and a developer
running the API locally never creates a catalogue row.

A note on where this runs. APScheduler here is in-process and in-memory, so a
Railway redeploy — which is every push to main — restarts the schedule and
kills anything mid-run. That is survivable *because* of the staging table: a
promoted candidate is no longer `complete`, so the next run resumes at the
first one that did not finish rather than repeating the batch. This is the
main reason promotion writes its outcome back per book instead of per batch.
"""

import logging

import httpx

from app.core.config import get_settings
from app.core.db import SessionLocal
from app.jobs.scheduler import LOCK_CATALOG_INTAKE, advisory_lock
from app.services import intake_openlibrary, intake_service

logger = logging.getLogger(__name__)

#: Long enough for OpenLibrary's search to answer a faceted query under load,
#: short enough that a hung origin cannot hold the job open until the next run.
TIMEOUT_SECONDS = 30.0

#: Identifies us to the sources we read, so an operator on the other end can
#: see who is crawling and get in touch rather than just blocking us.
USER_AGENT = "Kitabi/1.0 (+https://kitabi.in; catalogue intake)"


async def catalog_intake(client: httpx.AsyncClient | None = None) -> None:
    """`client` is injectable so tests drive the whole job without the network
    — the same shape as `backfill_covers` and `recommendation_service`."""
    settings = get_settings()
    if not settings.catalog_intake_enabled:
        return  # dormant: no requests, no rows

    owned = client is None
    client = client or httpx.AsyncClient(
        timeout=TIMEOUT_SECONDS, headers={"User-Agent": USER_AGENT}
    )
    try:
        async with SessionLocal() as session:
            async with advisory_lock(session, LOCK_CATALOG_INTAKE) as acquired:
                if not acquired:
                    return

                candidates = await intake_openlibrary.discover(
                    client, per_seed=settings.catalog_intake_per_seed
                )
                staged = await intake_service.record(
                    session, candidates, source=intake_openlibrary.SOURCE
                )
                if staged:
                    logger.info("intake: staged %s", staged)

                released = await intake_service.rescreen_incomplete(session)
                if released.get("complete"):
                    logger.info("intake: rescreen released %s", released["complete"])

                promoted = await intake_service.promote(
                    session, limit=settings.catalog_intake_daily_limit
                )
                if promoted:
                    logger.info("intake: promoted %s", promoted)
    finally:
        if owned:
            await client.aclose()

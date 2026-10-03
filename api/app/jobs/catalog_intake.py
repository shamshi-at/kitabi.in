"""The daily catalogue intake job.

Runs in the API process on Railway, beside `backfill_covers` and
`merge_exact`, under a Postgres advisory lock so a second replica can never
double-run it (the pattern every job here uses).

Four steps, deliberately in this order and deliberately separable:

1. **discover** — ask each source adapter what it can see: OpenLibrary for
   the backlist, then each publisher's storefront — its newest page first
   (tonight's new releases), then a few more pages of its backlist. Writes
   candidates to `catalog_intake` and touches no catalogue table.
1b. **enrich** — for rows a storefront's feed left incomplete, read that
   book's own page for the ISBN, the author and the title in its own script.
2. **rescreen** — re-run the gate over rows held as `incomplete`, so a gate
   fix releases what it was holding without re-crawling anything.
3. **promote** — turn at most `catalog_intake_daily_limit` complete candidates
   into books, each with its cover fetched, shrunk and stored in our own R2
   bucket first (`services/cover_ingest`).

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
from app.services import cover_ingest, intake_openlibrary, intake_service, intake_storefront

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
                    # The other jobs here skip silently and run again in five
                    # minutes. This one runs once a night, so a skip is a
                    # whole night's books and should be findable in the log.
                    logger.warning("intake: another run holds the lock — skipped tonight")
                    return

                candidates = await intake_openlibrary.discover(
                    client, per_seed=settings.catalog_intake_per_seed
                )
                staged = await intake_service.record(
                    session, candidates, source=intake_openlibrary.SOURCE
                )
                if staged:
                    logger.info("intake: staged %s", staged)

                await _storefronts(session, client, settings)

                released = await intake_service.rescreen_incomplete(session)
                if released.get("complete"):
                    logger.info("intake: rescreen released %s", released["complete"])

                covers = cover_ingest.ingester(client, settings)
                if covers is None:
                    # Not an error — a dev box has no bucket — but in
                    # production it means every cover from a publisher's own
                    # site is being held, and that should be findable.
                    logger.warning(
                        "intake: R2 cover storage is not configured — only covers "
                        "the edge proxy already serves will be promoted"
                    )
                promoted = await intake_service.promote(
                    session, limit=settings.catalog_intake_daily_limit, covers=covers
                )
                if promoted:
                    logger.info("intake: promoted %s", promoted)
    finally:
        if owned:
            await client.aclose()


async def _storefronts(session, client: httpx.AsyncClient, settings) -> None:
    """Stage what each publisher's shop lists, then fill in from product pages.

    A shop that fails, or whose robots.txt cannot be read or says no, costs
    only itself: the others, and everything after this step, still run.
    """
    robots = {}
    for store in intake_storefront.STORES:
        try:
            rules = await intake_storefront.read_robots(client, store)
            if rules is None or not rules.can_fetch(USER_AGENT, store.feed_url):
                logger.warning("intake/%s: robots.txt does not allow the feed", store.source)
                continue
            robots[store.source] = rules

            # Tonight's new releases — marked, so they are published first.
            newest = await intake_storefront.discover(client, store, pages=[1])
            staged = await intake_service.record(session, newest, source=store.source, fresh=True)
            # …then a little further into the backlist than last night.
            pages = await intake_storefront.backlist_pages(
                session, store, count=settings.catalog_intake_backlist_pages
            )
            older = await intake_storefront.discover(client, store, pages=pages)
            await intake_service.record(session, older, source=store.source)
            logger.info(
                "intake/%s: newest page %s, backlist pages %s (%s products)",
                store.source,
                staged,
                pages,
                len(older),
            )
        except Exception:  # noqa: BLE001 — one shop must not cost the night
            logger.exception("intake/%s: crawl failed", store.source)
            await session.rollback()

    reachable = [s for s in intake_storefront.STORES if s.source in robots]
    try:
        enriched = await intake_storefront.enrich(
            session,
            client,
            limit=settings.catalog_intake_enrich_limit,
            stores=reachable,
            may_fetch=lambda store, url: robots[store.source].can_fetch(USER_AGENT, url),
        )
    except Exception:  # noqa: BLE001 — a bad page must not cost the night's promotions
        logger.exception("intake: reading product pages failed")
        await session.rollback()
        return
    if enriched:
        logger.info("intake: product pages read %s", enriched)

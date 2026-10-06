"""The daily catalogue intake job.

Runs in the API process on Railway, beside `backfill_covers` and
`merge_exact`, under a Postgres advisory lock so a second replica can never
double-run it (the pattern every job here uses).

Four steps, deliberately in this order and deliberately separable:

1. **discover** — ask each source adapter what it can see: OpenLibrary for
   the backlist, then each publisher's storefront — its newest page first
   (tonight's new releases), then a few more pages of its backlist. Writes
   candidates to `catalog_intake` and touches no catalogue table.
1a. **Kerala Book Store** (off unless configured) — the next few pages of the
   Malayalam retailer's sitemap, newest first. One page is a complete record.
1b. **enrich** — for rows a storefront's feed left incomplete, read that
   book's own page for the ISBN, the author and the title in its own script.
1c. **author roles** — for books a shop credits to several people without
   saying who did what, ask the LLM and keep only an answer that checks out
   against the publisher's own text (`services/author_roles`). Paid, metered.
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
from app.services import (
    author_roles,
    cover_ingest,
    intake_keralabookstore,
    intake_openlibrary,
    intake_service,
    intake_storefront,
)

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
                await _keralabookstore(session, client, settings)
                await _author_roles(session, client, settings)

                released = await intake_service.rescreen_incomplete(session)
                if released.get("complete"):
                    logger.info("intake: rescreen released %s", released["complete"])

                await _publish(session, client, settings, settings.catalog_intake_daily_limit)
    finally:
        if owned:
            await client.aclose()


async def _publish(session, client: httpx.AsyncClient, settings, limit: int) -> dict[str, int]:
    """The last step of a night: turn up to `limit` ready candidates into books."""
    covers = cover_ingest.ingester(client, settings)
    if covers is None:
        # Not an error — a dev box has no bucket — but in production it means
        # every cover from a publisher's own site is being held, and that
        # should be findable.
        logger.warning(
            "intake: R2 cover storage is not configured — only covers "
            "the edge proxy already serves will be promoted"
        )
    promoted = await intake_service.promote(session, limit=limit, covers=covers)
    if promoted:
        logger.info("intake: promoted %s", promoted)
    return promoted


async def catch_up(
    limit: int | None = None, client: httpx.AsyncClient | None = None
) -> dict[str, int] | None:
    """Publish what is already ready, now — a night's last step on its own.

    For the morning after a run that stopped early (5 Oct 2026: one book out,
    1,070 ready). It crawls nothing and asks the LLM nothing: the books it
    publishes were found, screened and queued by a run that has already paid
    for all that. Same advisory lock as the nightly job, so it cannot overlap
    one; same dormancy switch, so running it on a laptop — where `api/.env`
    points at production — publishes nothing.

    Run inside the production container:

        python -m app.jobs.catalog_intake          # up to the nightly limit
        python -m app.jobs.catalog_intake 40       # up to 40

    Returns what `promote` counted, or None when it did not run.
    """
    settings = get_settings()
    if not settings.catalog_intake_enabled:
        logger.warning("intake: catch-up not run — the intake is not enabled here")
        return None

    owned = client is None
    client = client or httpx.AsyncClient(
        timeout=TIMEOUT_SECONDS, headers={"User-Agent": USER_AGENT}
    )
    try:
        async with SessionLocal() as session:
            async with advisory_lock(session, LOCK_CATALOG_INTAKE) as acquired:
                if not acquired:
                    logger.warning("intake: another run holds the lock — catch-up not run")
                    return None
                return await _publish(
                    session, client, settings, limit or settings.catalog_intake_daily_limit
                )
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


async def _keralabookstore(session, client: httpx.AsyncClient, settings) -> None:
    """Read the next Kerala Book Store pages, newest not-yet-staged first.

    Off unless `catalog_intake_keralabookstore_pages` is set. A shop that fails,
    or whose robots.txt cannot be read or says no, costs only itself.
    """
    pages = settings.catalog_intake_keralabookstore_pages
    if pages <= 0:
        return
    try:
        rules = await intake_keralabookstore.read_robots(client)
        if rules is None or not rules.can_fetch(USER_AGENT, intake_keralabookstore.SITEMAP_URL):
            logger.warning("intake/%s: robots.txt does not allow the sitemap", "keralabookstore")
            return
        found = await intake_keralabookstore.listings(client)
        if not found:
            return
        todo = intake_keralabookstore.unstaged(
            found, await intake_keralabookstore.staged_ids(session), pages
        )
        candidates = await intake_keralabookstore.read_pages(
            client, todo, may_fetch=lambda url: rules.can_fetch(USER_AGENT, url)
        )
        staged = await intake_service.record(
            session, candidates, source=intake_keralabookstore.SOURCE
        )
        logger.info(
            "intake/%s: %s of %s pages read, staged %s",
            intake_keralabookstore.SOURCE,
            len(candidates),
            len(todo),
            staged,
        )
    except Exception:  # noqa: BLE001 — one shop must not cost the night
        logger.exception("intake/%s: crawl failed", intake_keralabookstore.SOURCE)
        await session.rollback()


async def _author_roles(session, client: httpx.AsyncClient, settings) -> None:
    """Resolve who wrote and who translated the books held for it. A failure
    here leaves those books held and costs nothing else."""
    try:
        # Stored answers first, under tonight's rules — free, and it is what
        # stops a book resolved under an older rule from being published.
        rejudged = await author_roles.rejudge(session)
        if rejudged:
            logger.info("intake: author roles re-judged %s", rejudged)
        resolved = await author_roles.resolve_held(
            session, client, settings, limit=settings.catalog_intake_roles_limit
        )
    except Exception:  # noqa: BLE001 — never the reason a night publishes nothing
        logger.exception("intake: resolving author roles failed")
        await session.rollback()
        return
    if resolved:
        logger.info("intake: author roles %s", resolved)


if __name__ == "__main__":  # pragma: no cover — the operator's door; `catch_up` is tested
    import asyncio
    import sys

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    asked = int(sys.argv[1]) if len(sys.argv) > 1 else None
    print("catch-up:", asyncio.run(catch_up(asked)))

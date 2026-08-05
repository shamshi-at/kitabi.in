"""IndexNow — tell search engines a page exists instead of waiting to be found.

The gap this closes: a newly added book got a URL, a server-rendered page and a
sitemap entry immediately, and then nothing happened. Discovery was entirely
"wait for a crawler to come back and re-read the sitemap", which on a young
domain with little authority is days to weeks. IndexNow is a single keyless HTTP
call that says "this URL changed, come look" — Bing, Yandex, Seznam and Naver
consume it, and one endpoint fans out to all of them.

Google does **not** participate. Nothing here helps Google; that still needs
Search Console and ordinary crawling. Worth being clear about, because the
temptation is to read a 200 back from this as "we're indexed".

Rule 8 holds: no bill, and no credential in the security sense. The key is
*meant* to be public — ownership is proven by serving it at
`https://kitabi.in/<key>.txt`, which is why it lives in the repo next to the
file it must match rather than in a dashboard nobody can diff.

Two rules this module keeps:

* **It never fails a request.** Submission is best-effort and every error is
  swallowed. A book must be created whether or not Bing is reachable.
* **It never announces a page we told crawlers not to index.** A work below the
  content floor (docs/web-platform-plan.md §8.3) renders `noindex, follow`;
  inviting a crawler to fetch one is asking for the one thing we don't want,
  and spends the goodwill this protocol runs on.
"""

from __future__ import annotations

import logging

import httpx

from app.core.config import Settings, get_settings

logger = logging.getLogger(__name__)

# The aggregator: submitting here fans out to every participating engine, so
# there is one call rather than one per search engine.
ENDPOINT = "https://api.indexnow.org/indexnow"

# Must match landing-page/<key>.txt exactly, and that file must be reachable —
# the protocol validates ownership by fetching it. `tests/test_indexnow.py`
# asserts the two stay in step, and that the file is in the deploy allowlist,
# because a key file that 404s makes every submission fail with 403 and the
# only symptom is nothing happening.
KEY = "9b4aeafec5fe4eeaba383d6eb42bee5a"

# The crawler-facing origin. Hardcoded exactly as sitemap_service hardcodes it:
# these must be public page URLs, never the API host.
PUBLIC_BASE = "https://kitabi.in"
HOST = "kitabi.in"

# Short. This runs after the response has been sent, but a hung socket still
# holds a worker; the submission is disposable and the sitemap is the backstop.
TIMEOUT_SECONDS = 5.0


def book_url(slug_or_id: str) -> str:
    """The canonical page URL for a work — the same one the sitemap advertises.

    Never the `/isbn/<isbn>` address: that 301s, and submitting redirects spends
    someone's crawl budget on hops instead of pages — the same rule sitemap.xml
    keeps.
    """
    return f"{PUBLIC_BASE}/book/{slug_or_id}"


def is_enabled(settings: Settings | None = None) -> bool:
    """Off unless switched on explicitly, so a developer creating a book on a
    laptop never announces a localhost page to the internet.

    Production opts in through `ENV INDEXNOW_ENABLED=1` in `api/Dockerfile` —
    declared in the repo rather than a Railway dashboard variable, same as the
    migration guard's opt-in, so what production does is readable from a
    checkout.
    """
    settings = settings or get_settings()
    return bool(settings.indexnow_enabled and KEY)


async def announce(urls: list[str]) -> None:
    """Fire-and-forget entry point for background tasks — CANNOT raise.

    Starlette runs `BackgroundTasks` inside the response cycle and does **not**
    swallow their exceptions, so anything escaping here propagates through the
    ASGI stack after the body is sent. `submit` already catches its own network
    errors, but relying on that alone puts the "adding a book never depends on a
    search engine" guarantee at the mercy of every future edit inside it. The
    blanket catch belongs at the boundary, where the contract is.
    """
    try:
        await submit(urls)
    except Exception as exc:  # noqa: BLE001 — the entire point of this function
        logger.debug("IndexNow announce failed for %s: %s", urls, exc)


async def submit(urls: list[str], *, client: httpx.AsyncClient | None = None) -> bool:
    """Announce these URLs. Returns whether the endpoint accepted them.

    The return value is for tests and logs; no caller should branch on it, and
    none should await it on a request's critical path — this is scheduled as a
    background task so a slow response never delays a reader's book being saved.
    """
    if not urls or not is_enabled():
        return False

    payload = {
        "host": HOST,
        "key": KEY,
        "keyLocation": f"{PUBLIC_BASE}/{KEY}.txt",
        "urlList": urls,
    }
    try:
        if client is None:
            async with httpx.AsyncClient(timeout=TIMEOUT_SECONDS) as owned:
                response = await owned.post(ENDPOINT, json=payload)
        else:
            response = await client.post(ENDPOINT, json=payload)
    except Exception as exc:  # noqa: BLE001 — best-effort by design
        # Debug, not warning: an unreachable third party is not an incident here
        # and a retry loop on it would be worse than the miss.
        logger.debug("IndexNow submission failed for %s: %s", urls, exc)
        return False

    # 200 accepted, 202 accepted-but-key-still-being-validated. Everything else
    # is worth a line, because the failures are configuration mistakes that are
    # otherwise completely silent: 403 = the key file isn't being served,
    # 422 = a URL isn't on this host, 429 = too many submissions.
    if response.status_code in (200, 202):
        return True
    logger.warning(
        "IndexNow returned %s for %s (403=key file unreachable, 422=wrong host, 429=rate limited)",
        response.status_code,
        urls,
    )
    return False

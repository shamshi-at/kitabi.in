"""A tiny in-process TTL cache for the console's slowly-changing global counts —
the nav badges (recomputed on every page), the catalog quality-gap counts (every
catalog page, one of them a JSONB text scan) and the dashboard stats.

In-process is enough and is deliberately all this is: the admin service runs a
single uvicorn worker (admin/Dockerfile), so one process holds the whole cache,
and CLAUDE.md rule 8 rules out Redis or any new service anyway. The values are
global (the same numbers for every admin — no per-user data passes through here),
so one entry serves everyone.

Freshness has two guards. A short TTL bounds how stale any number can be, and the
catalog write paths call `invalidate_catalog()` so an edit's effect on the gap
counts shows immediately rather than waiting out the TTL. A missed invalidation
therefore self-heals within the TTL — it can never wedge a wrong number in place.
"""

import asyncio
import time
from collections.abc import Awaitable, Callable
from typing import Any

# key -> (expires_at_monotonic, value)
_store: dict[str, tuple[float, Any]] = {}
# key -> lock, so a cold key is computed once under concurrency, not once per
# racing request (nav_badges is hit by every page, often several at once).
_locks: dict[str, asyncio.Lock] = {}

# Cache keys.
NAV_BADGES = "nav_badges"
CATALOG_GAPS = "catalog_gaps"
DASHBOARD_STATS = "dashboard_stats"

# Catalog-derived entries — cleared together whenever the catalog is written.
_CATALOG_KEYS = (CATALOG_GAPS, DASHBOARD_STATS)


async def get_or_compute(key: str, ttl: float, compute: Callable[[], Awaitable[Any]]) -> Any:
    """Return the cached value for `key` if still fresh, else await `compute`,
    store it for `ttl` seconds and return it. Concurrent callers for the same
    cold key wait on one computation rather than each running their own."""
    hit = _store.get(key)
    if hit is not None and hit[0] > time.monotonic():
        return hit[1]
    lock = _locks.setdefault(key, asyncio.Lock())
    async with lock:
        # Someone may have filled it while we waited for the lock.
        hit = _store.get(key)
        if hit is not None and hit[0] > time.monotonic():
            return hit[1]
        value = await compute()
        _store[key] = (time.monotonic() + ttl, value)
        return value


def invalidate(*keys: str) -> None:
    for k in keys:
        _store.pop(k, None)


def invalidate_catalog() -> None:
    """Drop the counts a catalog write can change (gap counts, dashboard health).
    Called from the catalog router's mutating endpoints."""
    invalidate(*_CATALOG_KEYS)


def clear() -> None:
    _store.clear()

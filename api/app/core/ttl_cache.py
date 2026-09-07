"""A tiny in-process TTL cache for slowly-changing, global, anonymous values.

Why it exists: every render of the public home, browse and hub pages ran the
same facet counts and the same page-shaped queries against Supabase, and
Supabase meters every byte that leaves the database. Crawlers walking the
faceted browse space produced ~3,700 such renders a day, which is how a 3 MB
catalogue became 5.75 GB of egress in a billing cycle (7 Sep 2026). The edge
cache is per Cloudflare data centre and evicts freely on the free tier, so it
bounds nothing at the origin; this does. A page payload is computed at most
once per TTL per distinct key, however many data centres and bots ask.

In-process is enough and is deliberately all this is: the API runs a single
uvicorn worker, so one process holds the whole cache, and CLAUDE.md rule 8
rules out Redis or any new service. Only global, anonymous values belong here
— nothing keyed on a reader may pass through it.
# SCALE: with more than one API instance each holds its own copy; the TTL
# still bounds staleness, the saving just divides by the instance count.

Freshness is the TTL alone. Admin-console writes happen in another process and
cannot invalidate this cache, so the TTL is the promise: a catalogue edit is on
the public site within `ttl` seconds plus the edge's own window. Mirrors
`admin/console/cache.py`, which the console has used since 1 Sep 2026.
"""

from __future__ import annotations

import asyncio
import time
from collections.abc import Awaitable, Callable
from typing import Any

# key -> (expires_at_monotonic, value)
_store: dict[str, tuple[float, Any]] = {}
# key -> lock, so a cold key is computed once under concurrency — a crawler
# burst on one URL must not fan out into one origin query per request.
_locks: dict[str, asyncio.Lock] = {}

# Bound the store: browse keys are combinatorial, and a crawler can mint them
# faster than they expire. Past this many entries the expired ones are swept,
# and if that is not enough the oldest-expiring go too.
MAX_ENTRIES = 2000


async def get_or_compute(key: str, ttl: float, compute: Callable[[], Awaitable[Any]]) -> Any:
    """Return the cached value for `key` if still fresh, else await `compute`,
    store it for `ttl` seconds and return it. Concurrent callers for the same
    cold key wait on one computation rather than each running their own.

    A `None` result is never stored — "not found" stays a live answer, so a
    row added a moment later is found on the next request rather than after
    the TTL."""
    now = time.monotonic()
    hit = _store.get(key)
    if hit is not None and hit[0] > now:
        return hit[1]
    lock = _locks.setdefault(key, asyncio.Lock())
    async with lock:
        hit = _store.get(key)
        if hit is not None and hit[0] > time.monotonic():
            return hit[1]
        value = await compute()
        if value is not None:
            if len(_store) >= MAX_ENTRIES:
                _sweep()
            _store[key] = (time.monotonic() + ttl, value)
        else:
            _locks.pop(key, None)
        return value


def _sweep() -> None:
    now = time.monotonic()
    for k in [k for k, (exp, _) in _store.items() if exp <= now]:
        _store.pop(k, None)
        _locks.pop(k, None)
    if len(_store) >= MAX_ENTRIES:
        for k, _ in sorted(_store.items(), key=lambda kv: kv[1][0])[: MAX_ENTRIES // 2]:
            _store.pop(k, None)
            _locks.pop(k, None)


def invalidate(*keys: str) -> None:
    for k in keys:
        _store.pop(k, None)


def invalidate_prefix(prefix: str) -> None:
    for k in [k for k in _store if k.startswith(prefix)]:
        _store.pop(k, None)


def clear() -> None:
    _store.clear()
    _locks.clear()


def size() -> int:
    return len(_store)

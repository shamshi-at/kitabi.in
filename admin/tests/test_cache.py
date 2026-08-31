"""Unit tests for the in-process TTL cache (console/cache.py) — the counts
cache behind the nav badges, catalog gaps and dashboard stats."""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pytest

from console import cache


@pytest.fixture(autouse=True)
def _clean():
    cache.clear()
    yield
    cache.clear()


def _counter():
    state = {"n": 0}

    async def compute():
        state["n"] += 1
        await asyncio.sleep(0)  # force a real await point
        return state["n"]

    return state, compute


def test_hit_within_ttl_computes_once():
    async def go():
        state, compute = _counter()
        a = await cache.get_or_compute("k", 10, compute)
        b = await cache.get_or_compute("k", 10, compute)
        assert a == 1 and b == 1 and state["n"] == 1

    asyncio.run(go())


def test_invalidate_forces_recompute():
    async def go():
        state, compute = _counter()
        await cache.get_or_compute("k", 10, compute)
        cache.invalidate("k")
        again = await cache.get_or_compute("k", 10, compute)
        assert again == 2 and state["n"] == 2

    asyncio.run(go())


def test_ttl_expiry_recomputes():
    async def go():
        state, compute = _counter()
        await cache.get_or_compute("t", 0.03, compute)
        await asyncio.sleep(0.05)
        await cache.get_or_compute("t", 0.03, compute)
        assert state["n"] == 2

    asyncio.run(go())


def test_single_flight_under_concurrency():
    # Ten concurrent callers for one cold key must share a single computation,
    # not each run their own (nav_badges is hit by every page, often at once).
    async def go():
        state, compute = _counter()
        results = await asyncio.gather(*[cache.get_or_compute("s", 10, compute) for _ in range(10)])
        assert state["n"] == 1 and set(results) == {1}

    asyncio.run(go())


def test_invalidate_catalog_scopes_to_catalog_keys():
    async def go():
        _, compute = _counter()
        for key in (cache.CATALOG_GAPS, cache.DASHBOARD_STATS, cache.NAV_BADGES):
            await cache.get_or_compute(key, 10, compute)
        cache.invalidate_catalog()
        assert cache.CATALOG_GAPS not in cache._store
        assert cache.DASHBOARD_STATS not in cache._store
        assert cache.NAV_BADGES in cache._store  # moderation badge is untouched

    asyncio.run(go())

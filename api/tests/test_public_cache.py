"""The public pages are memoised at the origin (app/core/ttl_cache.py).

Every render of home, browse and the hubs used to run the facet counts and the
page queries against Supabase — ~3,700 renders a day, mostly crawlers walking
the faceted browse space — and the bytes out are what the free tier meters
(5.75 GB of 5 GB, 7 Sep 2026). The edge cache is per data centre and evicts
freely, so the bound has to be here: one computation per key per TTL.
"""

import asyncio

import pytest

from app.core import ttl_cache
from app.services import public_service

from .test_public_pages import _seed_book


async def test_facet_counts_are_served_from_memory_within_the_ttl(db_sessionmaker):
    async with db_sessionmaker() as db:
        await _seed_book(db, title="Chemmeen", language="Malayalam")
        await db.commit()
        first = await public_service._language_counts(db)
        assert [c.name for c in first] == ["Malayalam"]

        await _seed_book(db, title="Ulysses", language="English", author_name="James Joyce")
        await db.commit()
        # Same object, not a re-query: the new language is not there yet.
        assert await public_service._language_counts(db) is first

        ttl_cache.clear()
        assert {c.name for c in await public_service._language_counts(db)} == {
            "Malayalam",
            "English",
        }


async def test_browse_is_keyed_on_every_filter(db_sessionmaker):
    async with db_sessionmaker() as db:
        await _seed_book(db, title="Chemmeen", language="Malayalam")
        await _seed_book(db, title="Ulysses", language="English", author_name="James Joyce")
        await db.commit()
        everything = await public_service.browse_page(db)
        malayalam = await public_service.browse_page(db, languages=["Malayalam"])
        assert everything.total == 2
        assert malayalam.total == 1
        # The same filters spelled in a different order are the same page.
        both = await public_service.browse_page(db, languages=["English", "Malayalam"])
        assert await public_service.browse_page(db, languages=["Malayalam", "English"]) is both
        assert ttl_cache.size() >= 3


async def test_a_missing_hub_is_not_cached(db_sessionmaker):
    async with db_sessionmaker() as db:
        assert await public_service.hub_page(db, "language", "english") is None
        await _seed_book(db, title="Ulysses", language="English", author_name="James Joyce")
        await db.commit()
        # Facets were cached by the miss; the page itself was not, and a
        # not-found is never pinned, so the hub exists as soon as its facet does.
        ttl_cache.invalidate_prefix(public_service.PUBLIC_CACHE_PREFIX + "language")
        page = await public_service.hub_page(db, "language", "english")
        assert page is not None


async def test_concurrent_cold_callers_compute_once():
    calls = 0

    async def compute():
        nonlocal calls
        calls += 1
        await asyncio.sleep(0.01)
        return "value"

    results = await asyncio.gather(*(ttl_cache.get_or_compute("k", 60, compute) for _ in range(5)))
    assert results == ["value"] * 5
    assert calls == 1


async def test_none_is_never_stored():
    async def compute():
        return None

    assert await ttl_cache.get_or_compute("none", 60, compute) is None
    assert ttl_cache.size() == 0


async def test_the_store_is_bounded():
    async def value():
        return 1

    for i in range(ttl_cache.MAX_ENTRIES + 10):
        await ttl_cache.get_or_compute(f"k{i}", 60, value)
    assert ttl_cache.size() <= ttl_cache.MAX_ENTRIES


@pytest.mark.parametrize("kind", ["authors", "publishers"])
async def test_the_narrow_candidate_load_still_finds_exact_duplicates(db_sessionmaker, kind):
    from app.models import Author, Publisher
    from app.services import merge_service

    model = {"authors": Author, "publishers": Publisher}[kind]
    async with db_sessionmaker() as db:
        db.add_all([model(name="DC Books"), model(name="dc books")])
        await db.commit()
    async with db_sessionmaker() as db:
        found = await merge_service.find_candidates(db, kind)
        assert len(found) == 1 and found[0].auto_mergeable
        assert await merge_service.auto_merge_exact(db, kind) == 1

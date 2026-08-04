"""The page-shaped endpoints behind kitabi.in.

Two things here carry real consequences and get the most attention:

* **The content floor.** Publishing all 1,402 catalog rows — most of them
  transliteration noise with no cover and one edition — teaches a search engine
  the domain produces thin pages and drags down the good ones. These guard the
  rule that decides what may be indexed.
* **Slug *and* UUID resolution.** `/b/<uuid>` links are in Google's index, in
  every share card ever generated, and bound to the app's universal links. If
  UUID resolution ever regresses, all of those 404 at once.
"""

import uuid
from datetime import UTC, datetime

import pytest

from app.models import Author, Edition, Publisher, Rating, Series, Work
from app.services import public_service, slug_service


async def _seed_book(db, *, title="Chemmeen", cover=None, description=None, editions=1, **kw):
    author = Author(name=kw.pop("author_name", "Thakazhi Sivasankara Pillai"))
    db.add(author)
    await db.flush()
    await slug_service.ensure_slug(db, author)

    work = Work(title=title, description=description, authors=[author], **kw)
    db.add(work)
    await db.flush()
    for i in range(editions):
        db.add(Edition(work_id=work.id, cover_url=cover if i == 0 else None))
    await slug_service.ensure_slug(db, work, extras=[author.name])
    await db.commit()
    return work, author


# --------------------------------------------------------------------------
# The content floor
# --------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("kwargs", "expected", "why"),
    [
        ({"cover": "https://x/c.jpg"}, True, "a cover is something to land on"),
        ({"description": "x" * 200}, True, "a real blurb is content"),
        ({"description": "too short"}, False, "a stub blurb is not"),
        ({"editions": 2}, True, "two printings means someone cared"),
        ({}, False, "bare row: no cover, no blurb, one edition"),
    ],
)
async def test_the_content_floor_decides_what_may_be_indexed(
    db_sessionmaker, kwargs, expected, why
):
    async with db_sessionmaker() as db:
        work, _ = await _seed_book(db, **kwargs)
        page = await public_service.book_page(db, str(work.id))
        assert page.indexable is expected, why


async def test_a_rating_alone_lifts_a_book_past_the_floor(db_sessionmaker):
    """This is what makes the floor self-healing: the moment a reader engages,
    the page becomes worth indexing without anyone deciding."""
    async with db_sessionmaker() as db:
        work, _ = await _seed_book(db)
        assert (await public_service.book_page(db, str(work.id))).indexable is False

        db.add(Rating(id=uuid.uuid4(), user_id=uuid.uuid4(), work_id=work.id, value=5))
        await db.commit()
        assert (await public_service.book_page(db, str(work.id))).indexable is True


async def test_author_and_publisher_floors(db_sessionmaker):
    async with db_sessionmaker() as db:
        thin = Author(name="Nobody In Particular")
        db.add(thin)
        await db.flush()
        assert public_service.author_is_indexable(thin, work_count=1) is False
        assert public_service.author_is_indexable(thin, work_count=2) is True
        thin.bio = "A real biography."
        assert public_service.author_is_indexable(thin, work_count=0) is True

        assert public_service.publisher_is_indexable(2) is False
        assert public_service.publisher_is_indexable(3) is True


# --------------------------------------------------------------------------
# Resolution
# --------------------------------------------------------------------------


async def test_a_book_resolves_by_slug_and_by_uuid(db_sessionmaker):
    async with db_sessionmaker() as db:
        work, _ = await _seed_book(db, cover="https://x/c.jpg")
        by_slug = await public_service.book_page(db, work.slug)
        by_uuid = await public_service.book_page(db, str(work.id))
        assert by_slug is not None and by_uuid is not None
        assert by_slug.id == by_uuid.id == work.id


async def test_unknown_and_malformed_keys_are_simply_not_found(db_sessionmaker):
    async with db_sessionmaker() as db:
        assert await public_service.book_page(db, "no-such-book") is None
        assert await public_service.book_page(db, str(uuid.uuid4())) is None
        # Not a UUID and not a slug — must return None, never raise.
        assert await public_service.book_page(db, "../../etc/passwd") is None


async def test_a_soft_deleted_book_is_gone_from_the_public_site(db_sessionmaker):
    async with db_sessionmaker() as db:
        work, _ = await _seed_book(db)
        work.deleted_at = datetime.now(UTC)
        await db.commit()
        assert await public_service.book_page(db, work.slug) is None


# --------------------------------------------------------------------------
# Page contents
# --------------------------------------------------------------------------


async def test_the_book_page_arrives_assembled_in_one_call(db_sessionmaker):
    """The one-payload rule: four sequential edge→Singapore round trips to build
    one page is ~1.2s of TTFB before anything renders."""
    async with db_sessionmaker() as db:
        work, author = await _seed_book(
            db, cover="https://x/c.jpg", description="x" * 200, first_publish_year=1956
        )
        db.add(Work(title="Kayar", authors=[author]))
        await db.commit()

        page = await public_service.book_page(db, work.slug)
        assert page.title == "Chemmeen"
        assert [a.name for a in page.authors] == ["Thakazhi Sivasankara Pillai"]
        assert page.authors[0].slug == "thakazhi-sivasankara-pillai"
        assert len(page.editions) == 1
        assert page.first_publish_year == 1956
        # …and the onward links a crawler needs, without a second request.
        assert any(c.title == "Kayar" for c in page.more_by_author)


async def test_the_cover_pick_is_deterministic(db_sessionmaker):
    """It's the LCP element; 'whatever the database returned first' would make
    the page's largest paint flap between deploys."""
    async with db_sessionmaker() as db:
        work, _ = await _seed_book(db, editions=0)
        for url in ("https://x/second.jpg", "https://x/third.jpg"):
            db.add(Edition(work_id=work.id, cover_url=url))
        await db.commit()
        seen = {
            (await public_service.book_page(db, work.slug)).editions[0].cover_url for _ in range(3)
        }
        assert len(seen) == 1


async def test_author_page_aggregates_without_a_second_request(db_sessionmaker):
    async with db_sessionmaker() as db:
        work, author = await _seed_book(db, first_publish_year=1956)
        publisher = Publisher(name="DC Books")
        db.add(publisher)
        await db.flush()
        await slug_service.ensure_slug(db, publisher)
        db.add(Edition(work_id=work.id, publisher_id=publisher.id))
        await db.commit()

        page = await public_service.author_page(db, author.slug)
        assert page.work_count == 1
        assert page.decades == {"1950s": 1}
        assert [p.name for p in page.publishers] == ["DC Books"]


async def test_series_page_orders_by_reading_order(db_sessionmaker):
    async with db_sessionmaker() as db:
        series = Series(name="Malgudi")
        db.add(series)
        await db.flush()
        await slug_service.ensure_slug(db, series)
        for n, title in ((3, "The Dark Room"), (1, "Swami and Friends"), (2, "The Bachelor")):
            w = Work(title=title)
            db.add(w)
            await db.flush()
            db.add(Edition(work_id=w.id, series_id=series.id, series_number=n))
        await db.commit()

        page = await public_service.series_page(db, "malgudi")
        assert [w.title for w in page.works] == [
            "Swami and Friends",
            "The Bachelor",
            "The Dark Room",
        ]


async def test_home_prefers_a_featured_book_that_will_actually_look_good(db_sessionmaker):
    """An empty hero is worse than a less-celebrated one, so a cover+blurb beats
    a bare high rating."""
    async with db_sessionmaker() as db:
        await _seed_book(db, title="Bare But Adored", aggregate_rating=5.0)
        await _seed_book(
            db,
            title="Complete",
            cover="https://x/c.jpg",
            description="x" * 200,
            aggregate_rating=4.0,
            author_name="Someone Else",
        )
        page = await public_service.home_page(db)
        assert page.featured is not None
        assert page.featured.title == "Complete"


async def test_browse_reports_a_total_so_pages_can_be_walked(db_sessionmaker):
    async with db_sessionmaker() as db:
        for i in range(5):
            db.add(Work(title=f"Book {i}", language="Malayalam"))
        db.add(Work(title="Elsewhere", language="Tamil"))
        await db.commit()

        page = await public_service.browse_page(db, languages=["Malayalam"], per_page=2)
        assert page.total == 5
        assert len(page.works) == 2


async def test_search_calls_out_a_cross_script_hit(db_sessionmaker):
    """Typing "chemmeen" and getting ചെമ്മീൻ is the thing that makes this search
    feel different — the page says so rather than leaving it unexplained."""
    async with db_sessionmaker() as db:
        db.add(Work(title="ചെമ്മീൻ"))
        await db.commit()
        page = await public_service.search_page(db, "chemmeen")
        assert any(not w.title.isascii() for w in page.works)
        assert page.matched_scripts


# --------------------------------------------------------------------------
# Through the router
# --------------------------------------------------------------------------


async def test_public_endpoints_need_no_auth_and_are_cacheable(
    unauthenticated_client, db_sessionmaker
):
    """They're rendered at the edge for anonymous visitors and crawlers. If
    these ever require auth the whole public site goes blank — which is exactly
    how the reviews endpoint ended up invisible on the web."""
    async with db_sessionmaker() as db:
        work, author = await _seed_book(db, cover="https://x/c.jpg")

    for path in ("/public/home", f"/public/book/{work.slug}", f"/public/author/{author.slug}"):
        resp = await unauthenticated_client.get(path)
        assert resp.status_code == 200, path
        assert "s-maxage" in resp.headers.get("cache-control", ""), path


async def test_a_missing_page_is_a_real_404(unauthenticated_client):
    resp = await unauthenticated_client.get("/public/book/nothing-here")
    assert resp.status_code == 404
    assert resp.json()["code"] == "not_found"


async def test_reviews_are_public_on_the_book_page(unauthenticated_client, db_sessionmaker):
    """The most IMDB-ish thing the catalog has, and it was invisible on the web
    because the only endpoint serving it required a signed-in user."""
    async with db_sessionmaker() as db:
        work, _ = await _seed_book(db, cover="https://x/c.jpg")
    resp = await unauthenticated_client.get(f"/public/book/{work.slug}")
    assert resp.status_code == 200
    body = resp.json()
    assert "reviews" in body and "rating" in body


# --------------------------------------------------------------------------
# Reviews, batch lookup, reader profiles
# --------------------------------------------------------------------------


async def test_reviews_page_paginates_and_carries_the_histogram(db_sessionmaker):
    async with db_sessionmaker() as db:
        work, _ = await _seed_book(db, cover="https://x/c.jpg")
        page = await public_service.reviews_page(db, work.slug)
    assert page is not None
    assert page.work.title == "Chemmeen"
    assert page.rating is not None
    assert page.page == 1


async def test_works_by_keys_preserves_the_order_asked_for(db_sessionmaker):
    """Editorial lists are curated sequences — "twelve books, in this order" —
    so the API must not reorder them."""
    async with db_sessionmaker() as db:
        a, _ = await _seed_book(db, title="Alpha", author_name="A")
        b, _ = await _seed_book(db, title="Beta", author_name="B")
        c, _ = await _seed_book(db, title="Gamma", author_name="C")
        cards = await public_service.works_by_keys(db, [c.slug, a.slug, b.slug])
    assert [w.title for w in cards] == ["Gamma", "Alpha", "Beta"]


async def test_works_by_keys_skips_what_it_cannot_resolve(db_sessionmaker):
    """A list must not break because one book on it was merged away."""
    async with db_sessionmaker() as db:
        a, _ = await _seed_book(db, title="Alpha")
        cards = await public_service.works_by_keys(db, ["gone-away", a.slug, "also-gone"])
    assert [w.title for w in cards] == ["Alpha"]


async def test_a_private_reader_has_no_page_at_all(db_sessionmaker):
    """Not an empty page — none. "This handle exists but is private" is itself
    a disclosure, and the visibility flags exist so the web honours them."""
    from app.models import Profile

    async with db_sessionmaker() as db:
        db.add(Profile(id=uuid.uuid4(), email="h@x.test", username="hidden", profile_visible=False))
        db.add(Profile(id=uuid.uuid4(), email="s@x.test", username="shown", profile_visible=True))
        await db.commit()

        assert await public_service.reader_page(db, "hidden") is None
        assert await public_service.reader_page(db, "nobody") is None
        shown = await public_service.reader_page(db, "shown")
    assert shown is not None and shown.username == "shown"


async def test_a_public_reader_with_a_private_library_shows_no_books(db_sessionmaker):
    """Two separate flags. A public profile does not imply a public shelf."""
    from app.models import Profile

    async with db_sessionmaker() as db:
        db.add(
            Profile(
                id=uuid.uuid4(),
                email="r@x.test",
                username="reader",
                profile_visible=True,
                library_visible=False,
            )
        )
        await db.commit()
        page = await public_service.reader_page(db, "reader")
    assert page is not None
    assert page.recent == []
    assert page.library_visible is False


async def test_reader_lookup_is_case_insensitive(db_sessionmaker):
    from app.models import Profile

    async with db_sessionmaker() as db:
        db.add(
            Profile(id=uuid.uuid4(), email="a@x.test", username="arundhati", profile_visible=True)
        )
        await db.commit()
        assert await public_service.reader_page(db, "Arundhati") is not None


async def test_batch_lookup_is_one_query_not_one_per_key(db_sessionmaker):
    """The endpoint exists to avoid N+1; the first version had one inside it.
    Resolving 55 slugs one at a time took 8.0s in production — right at the edge
    renderer's timeout, so /lists intermittently rendered as if no list existed.

    Counts statements rather than asserting on wall-clock, which would be flaky.
    """
    from sqlalchemy import event

    async with db_sessionmaker() as db:
        works = []
        for i in range(12):
            w = Work(title=f"Book {i}", slug=f"book-{i}")
            db.add(w)
            works.append(w)
        await db.commit()

        statements: list[str] = []
        sync_engine = db.bind.sync_engine

        def record(conn, cursor, statement, *args):  # noqa: ANN001
            if statement.lstrip().upper().startswith("SELECT"):
                statements.append(statement)

        event.listen(sync_engine, "before_cursor_execute", record)
        try:
            cards = await public_service.works_by_keys(db, [f"book-{i}" for i in range(12)])
        finally:
            event.remove(sync_engine, "before_cursor_execute", record)

    assert len(cards) == 12
    # One for the works, plus the eager-loaded relations and the batched rating
    # counts. The point is that it does NOT scale with the number of keys.
    assert len(statements) < 8, f"{len(statements)} SELECTs for 12 keys:\n" + "\n".join(statements)

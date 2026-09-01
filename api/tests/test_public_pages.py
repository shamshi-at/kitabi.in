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
from sqlalchemy import select

from app.models import Author, Edition, Genre, Publisher, Rating, Series, Work
from app.services import public_service, slug_service


async def _seed_book(
    db, *, title="Chemmeen", cover=None, description=None, editions=1, isbn=None, **kw
):
    author = Author(name=kw.pop("author_name", "Thakazhi Sivasankara Pillai"))
    db.add(author)
    await db.flush()
    await slug_service.ensure_slug(db, author)

    work = Work(title=title, description=description, authors=[author], **kw)
    db.add(work)
    await db.flush()
    for i in range(editions):
        db.add(
            Edition(
                work_id=work.id, cover_url=cover if i == 0 else None, isbn=isbn if i == 0 else None
            )
        )
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
    """Membership is on the Work since migration 000043 — one row, one
    position, rather than a number per printing that the page had to `min()`."""
    async with db_sessionmaker() as db:
        series = Series(name="Malgudi")
        db.add(series)
        await db.flush()
        await slug_service.ensure_slug(db, series)
        for n, title in ((3, "The Dark Room"), (1, "Swami and Friends"), (2, "The Bachelor")):
            w = Work(title=title, series_id=series.id, series_number=n)
            db.add(w)
            await db.flush()
            db.add(Edition(work_id=w.id))
        await db.commit()

        page = await public_service.series_page(db, "malgudi")
        assert [w.title for w in page.works] == [
            "Swami and Friends",
            "The Bachelor",
            "The Dark Room",
        ]
        assert [e.number for e in page.entries] == [1, 2, 3]


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


async def test_browse_length_filter_counts_match_rows(db_sessionmaker):
    """The Length facet's total and its rows must come from the same
    predicate, or the toolbar says "Nothing here" over a page of books."""
    async with db_sessionmaker() as db:
        short = Work(title="Novella")
        long_ = Work(title="Saga")
        db.add_all([short, long_])
        await db.flush()
        db.add(Edition(work_id=short.id, page_count=150))
        db.add(Edition(work_id=long_.id, page_count=640))
        await db.commit()

        page = await public_service.browse_page(db, length="short")
        assert page.total == 1
        assert [w.title for w in page.works] == ["Novella"]


async def test_browse_genre_count_is_case_insensitive_like_the_rows(db_sessionmaker):
    """count_works matched genre case-sensitively while browse_works folded
    case — so ?genre=fiction rendered books under a zero total. The two
    predicates must agree."""
    async with db_sessionmaker() as db:
        genre = Genre(name="Fiction")
        work = Work(title="Genre-Carried", genres=[genre])
        db.add_all([genre, work])
        await db.commit()

        page = await public_service.browse_page(db, genre="fiction")
        assert [w.title for w in page.works] == ["Genre-Carried"]
        assert page.total == 1


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
# ISBN — the highest-intent query the site can receive
# --------------------------------------------------------------------------
#
# The public search path was never covered for ISBNs: the only ISBN search tests
# hit /catalog/search, which the app uses and the website does not. That mattered
# more than it looked, because an ISBN scores ZERO against a book's title in
# search_rank and `rank()` discards anything scoring zero — the result survives
# only because `_candidates` lifts it to MATCHER_FLOOR first. One line stands
# between ISBN search working and returning nothing, on a path nothing tested.

# 8126403454 and 9788126403455 are the same book: a checksum-valid ISBN-10 and
# the ISBN-13 it converts to.
ISBN10 = "8126403454"
ISBN13 = "9788126403455"


@pytest.mark.parametrize("query", [ISBN13, ISBN10, "978-81-264-0345-5", "812-640-3454"])
async def test_public_search_finds_a_book_by_either_isbn_form(db_sessionmaker, query):
    """A reader holding a 2005 printing types the ISBN-10 off the back cover;
    we catalogued the 2019 printing's ISBN-13. Same book, and it must be found."""
    async with db_sessionmaker() as db:
        work, _ = await _seed_book(db, isbn=ISBN13)

        page = await public_service.search_page(db, query)
        assert [w.id for w in page.works] == [work.id], query
        assert page.order[0] == "book"


async def test_public_search_by_isbn_survives_the_ranker(db_sessionmaker):
    """Pins the MATCHER_FLOOR interaction explicitly, because the failure is
    silent: the database finds the book, the ranker scores it zero against the
    title, and the reader is told the catalogue has never heard of it."""
    async with db_sessionmaker() as db:
        await _seed_book(db, title="Chemmeen", isbn=ISBN13)
        page = await public_service.search_page(db, ISBN13)
        assert page.works, "an ISBN shares no words with a title — it must not be ranked away"
        assert page.total >= 1


async def test_isbn_search_does_not_fuzz_into_a_near_miss(db_sessionmaker):
    """Digits must stay exact. A trigram match on numbers is confident nonsense."""
    async with db_sessionmaker() as db:
        await _seed_book(db, isbn=ISBN13)
        assert (await public_service.search_page(db, "9788126403456")).works == []


async def test_isbn_lookup_resolves_to_the_canonical_book_url(
    unauthenticated_client, db_sessionmaker
):
    """/isbn/<isbn> exists so an ISBN query has a URL to rank. Both forms must
    resolve, or the route only half-solves the problem it was added for."""
    async with db_sessionmaker() as db:
        work, _ = await _seed_book(db, isbn=ISBN13, cover="https://x/c.jpg")

    for form in (ISBN13, ISBN10, "978-81-264-0345-5"):
        resp = await unauthenticated_client.get(f"/public/isbn/{form}")
        assert resp.status_code == 200, form
        assert resp.json()["slug"] == work.slug, form
        assert "s-maxage" in resp.headers.get("cache-control", ""), form


async def test_isbn_lookup_finds_a_book_catalogued_under_the_isbn10(
    unauthenticated_client, db_sessionmaker
):
    """The mirror case — the reconciliation has to work in both directions, and
    testing only one of them is how half a fix ships."""
    async with db_sessionmaker() as db:
        work, _ = await _seed_book(db, isbn=ISBN10)

    for form in (ISBN10, ISBN13):
        resp = await unauthenticated_client.get(f"/public/isbn/{form}")
        assert resp.status_code == 200, form
        assert resp.json()["slug"] == work.slug, form


@pytest.mark.parametrize(
    "path",
    [
        "/public/isbn/9780000000002",  # well-formed, not in the catalogue
        "/public/isbn/chemmeen",  # not an ISBN at all
        "/public/isbn/123",
    ],
)
async def test_isbn_lookup_404s_rather_than_guessing(unauthenticated_client, path):
    resp = await unauthenticated_client.get(path)
    assert resp.status_code == 404
    assert resp.json()["code"] == "not_found"


async def test_isbn_lookup_never_falls_through_to_openlibrary(client):
    """The metering rule (CLAUDE.md): a PUBLIC endpoint must not spend a third
    party's quota. 9780802162175 is a book the fake OpenLibrary client knows
    about and our catalogue does not — the answer is still 404, not a proxied
    lookup a crawler could drive by walking guessed ISBNs.
    """
    resp = await client.get("/public/isbn/9780802162175")
    assert resp.status_code == 404


async def test_a_soft_deleted_edition_does_not_resolve(unauthenticated_client, db_sessionmaker):
    async with db_sessionmaker() as db:
        work, _ = await _seed_book(db, isbn=ISBN13)
        edition = (
            (await db.execute(select(Edition).where(Edition.work_id == work.id))).scalars().first()
        )
        edition.deleted_at = datetime.now(UTC)
        await db.commit()

    resp = await unauthenticated_client.get(f"/public/isbn/{ISBN13}")
    assert resp.status_code == 404


# --------------------------------------------------------------------------
# Slug → id, for the app's universal links
# --------------------------------------------------------------------------


async def test_id_lookup_resolves_a_slug_and_a_uuid(unauthenticated_client, db_sessionmaker):
    """The app opens a tapped kitabi.in link through here.

    Universal links claim `/book/*`, `/author/*` and `/publisher/*` — canonical
    slug URLs — while every in-app screen and every catalog endpoint addresses a
    row by UUID. Both key forms resolve, forever: `/b/<uuid>` links are still in
    the index and still bound to the association files.
    """
    async with db_sessionmaker() as db:
        work, author = await _seed_book(db)
        publisher = Publisher(name="DC Books")
        db.add(publisher)
        await db.flush()
        await slug_service.ensure_slug(db, publisher)
        await db.commit()

    for kind, row in (("book", work), ("author", author), ("publisher", publisher)):
        for key in (row.slug, str(row.id)):
            resp = await unauthenticated_client.get(f"/public/id/{kind}/{key}")
            assert resp.status_code == 200, (kind, key)
            assert resp.json() == {"id": str(row.id), "slug": row.slug}, (kind, key)
            assert "s-maxage" in resp.headers.get("cache-control", "")


async def test_id_lookup_follows_a_merged_author(unauthenticated_client, db_sessionmaker):
    """A link to an author who was merged away opens the survivor. Same rule the
    edge's 301 follows — an app that 404s where the web redirects is a worse
    answer than the browser the reader came from."""
    async with db_sessionmaker() as db:
        survivor = Author(name="Vaikom Muhammad Basheer")
        db.add(survivor)
        await db.flush()
        duplicate = Author(name="Basheer", merged_into_id=survivor.id, deleted_at=datetime.now(UTC))
        db.add(duplicate)
        await db.flush()
        await slug_service.ensure_slug(db, survivor)
        await slug_service.ensure_slug(db, duplicate)
        await db.commit()

    resp = await unauthenticated_client.get(f"/public/id/author/{duplicate.slug}")
    assert resp.status_code == 200
    assert resp.json()["id"] == str(survivor.id)


@pytest.mark.parametrize(
    "path",
    [
        "/public/id/book/no-such-book",
        "/public/id/series/anything",  # not a kind the app links to
        f"/public/id/author/{uuid.uuid4()}",
    ],
)
async def test_id_lookup_404s_rather_than_guessing(unauthenticated_client, path):
    resp = await unauthenticated_client.get(path)
    assert resp.status_code == 404
    assert resp.json()["code"] == "not_found"


async def test_id_lookup_does_not_resolve_a_deleted_book(unauthenticated_client, db_sessionmaker):
    async with db_sessionmaker() as db:
        work, _ = await _seed_book(db)
        (await db.get(Work, work.id)).deleted_at = datetime.now(UTC)
        await db.commit()

    resp = await unauthenticated_client.get(f"/public/id/book/{work.slug}")
    assert resp.status_code == 404


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


# --------------------------------------------------------------------------
# Author / publisher directories
# --------------------------------------------------------------------------


async def test_people_directory_leads_with_the_substantial_ones(db_sessionmaker):
    """A directory of 1,190 authors is useless alphabetically — page one would
    be initials and typos. Most works first makes the first page worth landing
    on, which is also what decides whether it deserves indexing."""
    async with db_sessionmaker() as db:
        prolific = Author(name="Prolific", slug="prolific")
        sparse = Author(name="Sparse", slug="sparse")
        db.add_all([prolific, sparse])
        await db.flush()
        for i in range(3):
            db.add(Work(title=f"Book {i}", authors=[prolific]))
        db.add(Work(title="Only one", authors=[sparse]))
        await db.commit()

        page = await public_service.people_page(db, "authors")

    names = [p.name for p in page.people]
    assert names.index("Prolific") < names.index("Sparse")
    assert next(p.work_count for p in page.people if p.name == "Prolific") == 3
    assert page.total >= 2


async def test_people_directory_rejects_an_unknown_kind(db_sessionmaker):
    async with db_sessionmaker() as db:
        assert await public_service.people_page(db, "wombats") is None


async def test_publisher_directory_counts_works_not_editions(db_sessionmaker):
    """Two printings of one book is one work — counting editions would inflate
    a publisher that reprints a lot into looking like a bigger catalogue."""
    async with db_sessionmaker() as db:
        pub = Publisher(name="DC Books", slug="dc-books")
        work = Work(title="Chemmeen")
        db.add_all([pub, work])
        await db.flush()
        db.add_all(
            [
                Edition(work_id=work.id, publisher_id=pub.id),
                Edition(work_id=work.id, publisher_id=pub.id),
            ]
        )
        await db.commit()

        page = await public_service.people_page(db, "publishers")
    assert next(p.work_count for p in page.people if p.name == "DC Books") == 1


# --------------------------------------------------------------------------
# Typeahead
# --------------------------------------------------------------------------


async def test_suggest_matches_across_scripts(db_sessionmaker):
    """The reason to have suggestions at all: typing "chemmeen" on an English
    keyboard should offer ചെമ്മീൻ."""
    async with db_sessionmaker() as db:
        w = Work(title="ചെമ്മീൻ", slug="chemmeen")
        db.add(w)
        await db.commit()
        page = await public_service.suggest(db, "chemmeen")

    assert page.suggestions
    top = page.suggestions[0]
    assert top.kind == "book"
    assert top.href == "/book/chemmeen"


async def test_suggest_includes_authors_and_publishers_when_there_is_room(db_sessionmaker):
    async with db_sessionmaker() as db:
        db.add_all(
            [
                Author(name="Thakazhi Sivasankara Pillai", slug="thakazhi"),
                Publisher(name="Thakazhi Press", slug="thakazhi-press"),
            ]
        )
        await db.commit()
        page = await public_service.suggest(db, "thakazhi")

    kinds = {s.kind for s in page.suggestions}
    assert "author" in kinds
    assert all(s.href.startswith("/") for s in page.suggestions)


async def test_suggest_is_bounded(db_sessionmaker):
    """It runs on a keystroke; an unbounded list would be a performance bug on
    both ends."""
    async with db_sessionmaker() as db:
        for i in range(30):
            db.add(Work(title=f"Common Title {i}", slug=f"common-{i}"))
        await db.commit()
        page = await public_service.suggest(db, "common", limit=5)
    assert len(page.suggestions) <= 5


async def test_people_directory_sorts_by_name_when_asked(db_sessionmaker):
    async with db_sessionmaker() as db:
        prolific = Author(name="Zed Prolific", slug="zed")
        db.add_all([prolific, Author(name="Aaron Sparse", slug="aaron")])
        await db.flush()
        for i in range(3):
            db.add(Work(title=f"B{i}", authors=[prolific]))
        await db.commit()

        by_books = await public_service.people_page(db, "authors", sort="books")
        by_name = await public_service.people_page(db, "authors", sort="name")

    assert by_books.people[0].name == "Zed Prolific"
    assert by_name.people[0].name == "Aaron Sparse"


async def test_people_directory_filters_by_language(db_sessionmaker):
    async with db_sessionmaker() as db:
        db.add_all(
            [
                Author(name="Malayali Writer", slug="mw", primary_language="Malayalam"),
                Author(name="Tamil Writer", slug="tw", primary_language="Tamil"),
            ]
        )
        await db.commit()
        page = await public_service.people_page(db, "authors", language="Malayalam")

    assert [p.name for p in page.people] == ["Malayali Writer"]
    assert page.total == 1
    assert any(
        lang.name == "Tamil" for lang in page.languages
    ), "the filter row must still offer the languages you are not currently in"


async def test_the_no_publisher_named_placeholder_is_not_a_publisher(db_sessionmaker):
    """[s.n.] is *sine nomine* — a cataloguing placeholder meaning no publisher
    was named. It was showing in the directory with 10 books."""
    async with db_sessionmaker() as db:
        db.add_all(
            [
                Publisher(name="[s.n.]", slug="sn-1"),
                Publisher(name="s.n.", slug="sn-2"),
                Publisher(name="DC Books", slug="dc"),
            ]
        )
        await db.commit()
        page = await public_service.people_page(db, "publishers")

    names = [p.name for p in page.people]
    assert "DC Books" in names
    assert not any("s.n" in n.lower() for n in names), names
    assert page.total == 1, "the placeholder must not be counted either"

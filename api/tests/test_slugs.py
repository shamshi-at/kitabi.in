"""Public URL slugs: romanization, uniqueness, and — the one that actually
bites later — stability.

A slug is a published URL. The failure mode these guard against isn't a crash,
it's a silent one: a title gets edited, every inbound link 404s, and the page's
ranking is gone with no error anywhere.
"""

import uuid

import pytest
from sqlalchemy import select

from app.models import Author, Publisher, Series, Work
from app.services import slug_service
from app.services.slug_service import slugify

# --------------------------------------------------------------------------
# slugify
# --------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("title", "expected"),
    [
        ("The Guide", "the-guide"),
        ("  Spaces   everywhere  ", "spaces-everywhere"),
        ("Randamoozham!!!", "randamoozham"),
        ("Ponniyin Selvan: Part 1", "ponniyin-selvan-part-1"),
        ("A—dash & an ampersand", "a-dash-an-ampersand"),
    ],
)
def test_slugify_latin_titles(title, expected):
    assert slugify(title) == expected


def test_slugify_romanizes_indic_scripts():
    """The whole reason slugs route through `transliterate`: a Malayalam title
    must produce a typeable Latin URL, not percent-encoded mojibake."""
    for native in ("ചെമ്മീൻ", "ആടുജീവിതം", "പാത്തുമ്മായുടെ ആട്"):
        slug = slugify(native)
        assert slug is not None
        # ASCII, url-safe, no leading/trailing or doubled dashes.
        assert slug.isascii()
        assert slug.replace("-", "").isalnum()
        assert not slug.startswith("-") and not slug.endswith("-")
        assert "--" not in slug


def test_slugify_gives_up_rather_than_returning_junk():
    for nothing in (None, "", "   ", "!!!", "…"):
        assert slugify(nothing) is None


def test_slugify_is_length_capped_without_a_trailing_dash():
    slug = slugify("word " * 60)
    assert slug is not None
    assert len(slug) <= slug_service.MAX_SLUG_LEN
    assert not slug.endswith("-")


# --------------------------------------------------------------------------
# uniqueness + disambiguation
# --------------------------------------------------------------------------


async def test_second_book_with_the_same_title_is_disambiguated_by_author(db_sessionmaker):
    async with db_sessionmaker() as db:
        thakazhi = Author(name="Thakazhi Sivasankara Pillai")
        other = Author(name="K. M. Tharakan")
        db.add_all([thakazhi, other])
        await db.flush()

        first = Work(title="Chemmeen", authors=[thakazhi])
        db.add(first)
        await db.flush()
        assert await slug_service.ensure_slug(db, first) == "chemmeen"

        second = Work(title="Chemmeen", authors=[other])
        db.add(second)
        await db.flush()
        # Reads like a fact about the book, not "chemmeen-2".
        assert await slug_service.ensure_slug(db, second) == "chemmeen-k-m-tharakan"


async def test_a_third_collision_falls_back_to_year_then_a_counter(db_sessionmaker):
    async with db_sessionmaker() as db:
        author = Author(name="Anon")
        db.add(author)
        await db.flush()
        slugs = []
        for year in (1956, 1978, 1990):
            w = Work(title="Kayar", authors=[author], first_publish_year=year)
            db.add(w)
            await db.flush()
            slugs.append(await slug_service.ensure_slug(db, w))
        assert slugs[0] == "kayar"
        assert slugs[1] == "kayar-anon"
        assert slugs[2] == "kayar-anon-1990"
        assert len(set(slugs)) == 3


async def test_slugs_are_unique_across_a_pile_of_identical_titles(db_sessionmaker):
    async with db_sessionmaker() as db:
        seen = []
        for _ in range(6):
            w = Work(title="Untitled")
            db.add(w)
            await db.flush()
            seen.append(await slug_service.ensure_slug(db, w))
        assert len(set(seen)) == 6, seen
        assert all(s is not None for s in seen)


async def test_a_title_that_romanizes_to_nothing_gets_no_slug_rather_than_failing(
    db_sessionmaker,
):
    """It stays reachable by UUID. A slug is optional; an insert failing is not
    an acceptable alternative."""
    async with db_sessionmaker() as db:
        w = Work(title="!!!")
        db.add(w)
        await db.flush()
        assert await slug_service.ensure_slug(db, w) is None


async def test_reserved_words_never_become_slugs(db_sessionmaker):
    """A book called "Search" must not collide with the site's own routes."""
    async with db_sessionmaker() as db:
        w = Work(title="Search")
        db.add(w)
        await db.flush()
        assert await slug_service.ensure_slug(db, w) not in slug_service.RESERVED


# --------------------------------------------------------------------------
# stability — the one that matters
# --------------------------------------------------------------------------


async def test_ensure_slug_never_overwrites_an_existing_slug(db_sessionmaker):
    """Retitling a book keeps its published URL. If this ever regresses, every
    inbound link to every renamed book 404s and nothing raises."""
    async with db_sessionmaker() as db:
        w = Work(title="Chemmeen")
        db.add(w)
        await db.flush()
        original = await slug_service.ensure_slug(db, w)

        w.title = "Chemmeen (Revised Edition)"
        await db.flush()
        assert await slug_service.ensure_slug(db, w) == original


async def test_authors_publishers_and_series_all_get_slugs(db_sessionmaker):
    async with db_sessionmaker() as db:
        author = Author(name="തകഴി ശിവശങ്കരപ്പിള്ള")
        publisher = Publisher(name="DC Books")
        series = Series(name="The Malgudi Books")
        db.add_all([author, publisher, series])
        await db.flush()
        assert await slug_service.ensure_slug(db, author) is not None
        assert await slug_service.ensure_slug(db, publisher) == "dc-books"
        assert await slug_service.ensure_slug(db, series) == "the-malgudi-books"


async def test_an_author_slug_prefers_the_pen_name(db_sessionmaker):
    async with db_sessionmaker() as db:
        a = Author(name="Kalki Krishnamurthy", pen_name="Kalki")
        db.add(a)
        await db.flush()
        assert await slug_service.ensure_slug(db, a) == "kalki"


# --------------------------------------------------------------------------
# the backfill safety net
# --------------------------------------------------------------------------


async def test_backfill_fills_rows_that_no_service_path_touched(db_sessionmaker):
    """Simulates the ETL: rows inserted without ever calling ensure_slug."""
    async with db_sessionmaker() as db:
        db.add_all(
            [
                Work(title="Khasakkinte Ithihasam"),
                Work(title="Naalukettu"),
                Author(name="O. V. Vijayan"),
                Publisher(name="Mathrubhumi Books"),
                Series(name="Ponniyin Selvan"),
            ]
        )
        await db.commit()

        assert await slug_service.backfill_missing(db) == 5

        titles = (await db.execute(select(Work.title, Work.slug))).all()
        assert dict(titles) == {
            "Khasakkinte Ithihasam": "khasakkinte-ithihasam",
            "Naalukettu": "naalukettu",
        }


async def test_backfill_is_idempotent_and_cheap_to_rerun(db_sessionmaker):
    async with db_sessionmaker() as db:
        db.add(Work(title="Balyakalasakhi"))
        await db.commit()
        assert await slug_service.backfill_missing(db) == 1
        assert await slug_service.backfill_missing(db) == 0
        assert await slug_service.backfill_missing(db) == 0


async def test_backfill_leaves_already_slugged_rows_alone(db_sessionmaker):
    async with db_sessionmaker() as db:
        w = Work(title="Aarachar", slug="a-deliberately-hand-picked-slug")
        db.add(w)
        await db.commit()
        await slug_service.backfill_missing(db)
        await db.refresh(w)
        assert w.slug == "a-deliberately-hand-picked-slug"


async def test_backfill_skips_soft_deleted_rows(db_sessionmaker):
    from datetime import UTC, datetime

    async with db_sessionmaker() as db:
        db.add(Work(title="Gone", deleted_at=datetime.now(UTC)))
        await db.commit()
        assert await slug_service.backfill_missing(db) == 0


# --------------------------------------------------------------------------
# through the API
# --------------------------------------------------------------------------


async def test_creating_a_book_through_the_api_assigns_a_slug(client, db_sessionmaker):
    resp = await client.post(
        "/catalog/works",
        json={"title": "ഖസാക്കിന്റെ ഇതിഹാസം", "author_names": ["O. V. Vijayan"]},
    )
    assert resp.status_code == 201
    work_id = uuid.UUID(resp.json()["id"])

    async with db_sessionmaker() as db:
        work = await db.get(Work, work_id)
        assert work.slug is not None and work.slug.isascii()
        # …and its author got one too, since the author page needs a URL.
        author = (
            await db.execute(select(Author).where(Author.name == "O. V. Vijayan"))
        ).scalar_one()
        assert author.slug == "o-v-vijayan"

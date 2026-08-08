"""A reader's own public reviews, on their profile — the mirror of
test_public_reviews.py, which reads the same rows from the book's end.

The rule under test throughout: a review surfaces here only when the reader's
profile is public AND the review itself is visible. The two flags are ANDed,
never substituted for one another, and `library_visible` is deliberately not
part of the gate — a review is published on its own flag, and a private shelf
does not retract it (feature-map rules 13 and 16).
"""

import uuid

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.db import get_db
from app.core.security import get_current_user
from app.main import create_app
from app.models import Author, Edition, Profile, Rating, Review, Work
from app.services import public_service, slug_service
from app.services.openlibrary_client import get_openlibrary_client


@pytest.fixture
async def two_user_client(db_sessionmaker, user, user_b, fake_ol_client):
    app = create_app()
    current = {"user": user}

    async def override_db():
        async with db_sessionmaker() as session:
            yield session

    app.dependency_overrides[get_db] = override_db
    app.dependency_overrides[get_current_user] = lambda: current["user"]
    app.dependency_overrides[get_openlibrary_client] = lambda: fake_ol_client

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        c.as_user = lambda u: current.update(user=u)  # type: ignore[attr-defined]
        yield c


async def _seed_book(db, *, title="Chemmeen", cover=None):
    author = Author(name="Thakazhi Sivasankara Pillai")
    db.add(author)
    await db.flush()
    await slug_service.ensure_slug(db, author)
    work = Work(title=title, authors=[author])
    db.add(work)
    await db.flush()
    db.add(Edition(work_id=work.id, cover_url=cover))
    await slug_service.ensure_slug(db, work, extras=[author.name])
    await db.flush()
    return work


async def _seed_reader(
    db, user_b, *, profile_visible=True, library_visible=False, username="anu"
) -> Profile:
    profile = Profile(
        id=uuid.UUID(user_b["id"]),
        email=user_b["email"],
        username=username,
        full_name="Anu Varghese",
        profile_visible=profile_visible,
        library_visible=library_visible,
    )
    db.add(profile)
    await db.flush()
    return profile


# --------------------------------------------------------------------------
# The gate
# --------------------------------------------------------------------------


async def test_only_visible_reviews_reach_the_profile(db_sessionmaker, user_b):
    async with db_sessionmaker() as db:
        profile = await _seed_reader(db, user_b)
        public_book = await _seed_book(db, title="Chemmeen")
        private_book = await _seed_book(db, title="Aadujeevitham")
        db.add(
            Review(
                id=uuid.uuid4(),
                user_id=profile.id,
                work_id=public_book.id,
                body="A quiet, devastating book.",
                visible=True,
            )
        )
        db.add(
            Review(
                id=uuid.uuid4(),
                user_id=profile.id,
                work_id=private_book.id,
                body="Private notes to self.",
                visible=False,
            )
        )
        await db.commit()

        page = await public_service.reader_page(db, "anu")
        assert page is not None
        assert [r.body for r in page.reviews] == ["A quiet, devastating book."]
        assert page.reviews[0].work.title == "Chemmeen"


async def test_a_private_profile_has_no_page_and_so_no_reviews(db_sessionmaker, user_b):
    """The stronger half of the gate: it isn't that the reviews are hidden on a
    page that still renders — there is no page. Asserted through the public
    entry point, because that is the one the web actually calls."""
    async with db_sessionmaker() as db:
        profile = await _seed_reader(db, user_b, profile_visible=False)
        book = await _seed_book(db)
        db.add(
            Review(
                id=uuid.uuid4(),
                user_id=profile.id,
                work_id=book.id,
                body="Said in public, on a profile that is not.",
                visible=True,
            )
        )
        await db.commit()

        assert await public_service.reader_page(db, "anu") is None


async def test_a_visible_review_under_a_private_profile_is_not_readable_by_id(
    db_sessionmaker, user_b
):
    """Belt-and-braces on the service itself, not just the page assembly: a
    caller that reaches past reader_page must still get nothing."""
    from app.services import review_service

    async with db_sessionmaker() as db:
        profile = await _seed_reader(db, user_b, profile_visible=False)
        book = await _seed_book(db)
        db.add(
            Review(
                id=uuid.uuid4(),
                user_id=profile.id,
                work_id=book.id,
                body="Visible review, private reader.",
                visible=True,
            )
        )
        await db.commit()

        assert await review_service.reader_reviews(db, profile.id) == []


async def test_a_private_shelf_does_not_hide_public_reviews(db_sessionmaker, user_b):
    """The distinction that makes this endpoint worth having: `library_visible`
    gates the shelf, not the reviews. Getting this wrong in the safe direction
    is still wrong — it silently unpublishes what a reader chose to publish."""
    async with db_sessionmaker() as db:
        profile = await _seed_reader(db, user_b, library_visible=False)
        book = await _seed_book(db)
        db.add(
            Review(
                id=uuid.uuid4(),
                user_id=profile.id,
                work_id=book.id,
                body="Still stands behind this one.",
                visible=True,
            )
        )
        await db.commit()

        page = await public_service.reader_page(db, "anu")
        assert page is not None
        assert page.library_visible is False
        assert page.recent == []
        assert [r.body for r in page.reviews] == ["Still stands behind this one."]


# --------------------------------------------------------------------------
# Shape
# --------------------------------------------------------------------------


async def test_the_rating_rides_along_and_the_book_is_linkable(db_sessionmaker, user_b):
    async with db_sessionmaker() as db:
        profile = await _seed_reader(db, user_b)
        book = await _seed_book(db, cover="https://img.example/chemmeen.jpg")
        db.add(Rating(id=uuid.uuid4(), user_id=profile.id, work_id=book.id, value=5))
        db.add(
            Review(
                id=uuid.uuid4(),
                user_id=profile.id,
                work_id=book.id,
                body="Five stars, no hesitation.",
                visible=True,
            )
        )
        await db.commit()

        page = await public_service.reader_page(db, "anu")
        assert page is not None
        review = page.reviews[0]
        assert review.rating == 5
        # The slug is what makes the card a link rather than a title.
        assert review.work.slug
        assert review.work.cover_url == "https://img.example/chemmeen.jpg"
        assert [a.name for a in review.work.authors] == ["Thakazhi Sivasankara Pillai"]


async def test_another_readers_rating_is_not_attributed_to_this_one(db_sessionmaker, user, user_b):
    """The outer join is on (user, work), not on work alone. If it slipped to
    work alone, a stranger's 1-star would render as this reader's rating."""
    async with db_sessionmaker() as db:
        profile = await _seed_reader(db, user_b)
        book = await _seed_book(db)
        db.add(Rating(id=uuid.uuid4(), user_id=uuid.UUID(user["id"]), work_id=book.id, value=1))
        db.add(
            Review(
                id=uuid.uuid4(),
                user_id=profile.id,
                work_id=book.id,
                body="Reviewed without rating.",
                visible=True,
            )
        )
        await db.commit()

        page = await public_service.reader_page(db, "anu")
        assert page is not None
        assert page.reviews[0].rating is None


async def test_reviews_are_newest_first(db_sessionmaker, user_b):
    from datetime import UTC, datetime

    async with db_sessionmaker() as db:
        profile = await _seed_reader(db, user_b)
        older = await _seed_book(db, title="The Older One")
        newer = await _seed_book(db, title="The Newer One")
        db.add(
            Review(
                id=uuid.uuid4(),
                user_id=profile.id,
                work_id=older.id,
                body="Read first.",
                visible=True,
                created_at=datetime(2026, 1, 1, tzinfo=UTC),
            )
        )
        db.add(
            Review(
                id=uuid.uuid4(),
                user_id=profile.id,
                work_id=newer.id,
                body="Read later.",
                visible=True,
                created_at=datetime(2026, 8, 1, tzinfo=UTC),
            )
        )
        await db.commit()

        page = await public_service.reader_page(db, "anu")
        assert page is not None
        assert [r.work.title for r in page.reviews] == ["The Newer One", "The Older One"]


# --------------------------------------------------------------------------
# The app's endpoint (/users/{id}/reviews)
# --------------------------------------------------------------------------


async def test_app_endpoint_returns_public_reviews(two_user_client, db_sessionmaker, user_b):
    client = two_user_client
    async with db_sessionmaker() as db:
        profile = await _seed_reader(db, user_b)
        book = await _seed_book(db, cover="https://img.example/c.jpg")
        db.add(
            Review(
                id=uuid.uuid4(),
                user_id=profile.id,
                work_id=book.id,
                body="A quiet, devastating book.",
                visible=True,
            )
        )
        await db.commit()

    resp = await client.get(f"/users/{user_b['id']}/reviews")
    assert resp.status_code == 200
    items = resp.json()
    assert len(items) == 1
    assert items[0]["body"] == "A quiet, devastating book."
    assert items[0]["title"] == "Chemmeen"
    assert items[0]["author_names"] == "Thakazhi Sivasankara Pillai"
    assert items[0]["cover_url"] == "https://img.example/c.jpg"
    assert items[0]["work_id"] == str(book.id)
    # The row has to be openable: the app's book route is work + edition, and
    # a review only knows its Work, so the API picks the printing.
    assert items[0]["edition_id"] is not None


async def test_a_work_with_no_editions_yields_no_dead_link(
    two_user_client, db_sessionmaker, user_b
):
    """A catalogued Work can legitimately have no printing on file yet. The row
    must still render — with nothing to open, rather than a link to nowhere."""
    client = two_user_client
    async with db_sessionmaker() as db:
        profile = await _seed_reader(db, user_b)
        author = Author(name="Thakazhi Sivasankara Pillai")
        db.add(author)
        await db.flush()
        await slug_service.ensure_slug(db, author)
        work = Work(title="Editionless", authors=[author])
        db.add(work)
        await db.flush()
        db.add(
            Review(
                id=uuid.uuid4(),
                user_id=profile.id,
                work_id=work.id,
                body="Read it in manuscript.",
                visible=True,
            )
        )
        await db.commit()

    items = (await client.get(f"/users/{user_b['id']}/reviews")).json()
    assert len(items) == 1
    assert items[0]["edition_id"] is None
    assert items[0]["cover_url"] is None


async def test_app_endpoint_404s_for_a_private_profile(two_user_client, db_sessionmaker, user_b):
    """Same shape as /library and /works: indistinguishable from no such user."""
    client = two_user_client
    async with db_sessionmaker() as db:
        profile = await _seed_reader(db, user_b, profile_visible=False)
        book = await _seed_book(db)
        db.add(
            Review(
                id=uuid.uuid4(),
                user_id=profile.id,
                work_id=book.id,
                body="Not for you.",
                visible=True,
            )
        )
        await db.commit()

    assert (await client.get(f"/users/{user_b['id']}/reviews")).status_code == 404
    assert (await client.get(f"/users/{uuid.uuid4()}/reviews")).status_code == 404

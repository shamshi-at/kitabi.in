"""Public reviews on a Work: visible-only, reviewer identity resolved live
from current profile visibility (anonymous placeholder while private, real
name the instant they go public), a rating attached only when its owner
also left a public review, and the rating_summary (average/count/
distribution) computed from every rating on the work regardless of whether
its owner ever wrote a review."""

import uuid

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.db import get_db
from app.core.security import get_current_user
from app.main import create_app
from app.models import Profile, Rating, Review
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


async def test_only_visible_reviews_are_returned(two_user_client, db_sessionmaker, user_b):
    client = two_user_client
    work = (await client.post("/catalog/works", json={"title": "Chemmeen"})).json()
    async with db_sessionmaker() as db:
        db.add(
            Profile(
                id=uuid.UUID(user_b["id"]),
                email=user_b["email"],
                username="anu",
                full_name="Anu Varghese",
                profile_visible=True,
            )
        )
        db.add(
            Review(
                id=uuid.uuid4(),
                user_id=uuid.UUID(user_b["id"]),
                work_id=uuid.UUID(work["id"]),
                body="A quiet, devastating book.",
                visible=True,
            )
        )
        db.add(
            Review(
                id=uuid.uuid4(),
                user_id=uuid.UUID(user_b["id"]),
                work_id=uuid.UUID(work["id"]),
                body="Private notes to self.",
                visible=False,
            )
        )
        await db.commit()

    resp = await client.get(f"/catalog/works/{work['id']}/reviews")
    assert resp.status_code == 200
    body = resp.json()
    reviews = body["reviews"]
    assert len(reviews) == 1
    assert reviews[0]["body"] == "A quiet, devastating book."
    assert reviews[0]["reviewer"]["display_name"] == "Anu Varghese"
    assert reviews[0]["reviewer"]["is_public"] is True
    assert reviews[0]["reviewer"]["id"] == user_b["id"]


async def test_private_profile_review_is_anonymized_and_flips_live(
    two_user_client, db_sessionmaker, user_b
):
    client = two_user_client
    work = (await client.post("/catalog/works", json={"title": "Aadujeevitham"})).json()
    async with db_sessionmaker() as db:
        db.add(
            Profile(
                id=uuid.UUID(user_b["id"]),
                email=user_b["email"],
                full_name="Benyamin Fan",
                profile_visible=False,
            )
        )
        db.add(
            Review(
                id=uuid.uuid4(),
                user_id=uuid.UUID(user_b["id"]),
                work_id=uuid.UUID(work["id"]),
                body="Harrowing and essential.",
                visible=True,
            )
        )
        await db.commit()

    resp = await client.get(f"/catalog/works/{work['id']}/reviews")
    reviews = resp.json()["reviews"]
    assert len(reviews) == 1
    reviewer = reviews[0]["reviewer"]
    assert reviewer["display_name"].startswith("User_")
    assert reviewer["display_name"] != "Benyamin Fan"
    assert reviewer["is_public"] is False
    assert reviewer["avatar_url"] is None
    anon_name = reviewer["display_name"]

    # Same placeholder every time while private (stable, not random per call).
    resp2 = await client.get(f"/catalog/works/{work['id']}/reviews")
    assert resp2.json()["reviews"][0]["reviewer"]["display_name"] == anon_name

    # They flip their profile public — the very next fetch shows the real name.
    async with db_sessionmaker() as db:
        p = await db.get(Profile, uuid.UUID(user_b["id"]))
        p.profile_visible = True
        await db.commit()

    resp3 = await client.get(f"/catalog/works/{work['id']}/reviews")
    reviewer3 = resp3.json()["reviews"][0]["reviewer"]
    assert reviewer3["display_name"] == "Benyamin Fan"
    assert reviewer3["is_public"] is True


async def test_rating_attaches_only_alongside_a_public_review(
    two_user_client, db_sessionmaker, user_b
):
    client = two_user_client
    work = (await client.post("/catalog/works", json={"title": "Kayar"})).json()
    async with db_sessionmaker() as db:
        db.add(
            Profile(
                id=uuid.UUID(user_b["id"]),
                email=user_b["email"],
                full_name="Reader B",
                profile_visible=True,
            )
        )
        db.add(
            Review(
                id=uuid.uuid4(),
                user_id=uuid.UUID(user_b["id"]),
                work_id=uuid.UUID(work["id"]),
                body="Five stars, no notes.",
                visible=True,
            )
        )
        db.add(
            Rating(
                id=uuid.uuid4(),
                user_id=uuid.UUID(user_b["id"]),
                work_id=uuid.UUID(work["id"]),
                value=5,
            )
        )
        await db.commit()

    resp = await client.get(f"/catalog/works/{work['id']}/reviews")
    reviews = resp.json()["reviews"]
    assert len(reviews) == 1
    assert reviews[0]["rating"] == 5


async def test_naked_rating_has_no_review_but_still_counts_in_the_summary(
    two_user_client, db_sessionmaker, user_b
):
    client = two_user_client
    work = (await client.post("/catalog/works", json={"title": "Randamoozham"})).json()
    async with db_sessionmaker() as db:
        db.add(
            Profile(
                id=uuid.UUID(user_b["id"]),
                email=user_b["email"],
                full_name="Reader B",
                profile_visible=True,
            )
        )
        db.add(
            Rating(
                id=uuid.uuid4(),
                user_id=uuid.UUID(user_b["id"]),
                work_id=uuid.UUID(work["id"]),
                value=4,
            )
        )
        await db.commit()

    resp = await client.get(f"/catalog/works/{work['id']}/reviews")
    body = resp.json()
    # No public review exists, so the review list stays empty...
    assert body["reviews"] == []
    # ...but the rating still counts toward the community summary, since that's
    # computed from every rating on the work, not just reviewed ones.
    assert body["rating_count"] == 1
    assert body["rating_average"] == 4.0
    assert body["rating_distribution"] == {"1": 0, "2": 0, "3": 0, "4": 1, "5": 0}


async def test_rating_summary_averages_and_distributes_across_users(
    two_user_client, db_sessionmaker, user, user_b
):
    client = two_user_client
    work = (await client.post("/catalog/works", json={"title": "Mathilukal"})).json()
    async with db_sessionmaker() as db:
        db.add(
            Profile(
                id=uuid.UUID(user_b["id"]),
                email=user_b["email"],
                full_name="Reader B",
                profile_visible=True,
            )
        )
        db.add(
            Rating(
                id=uuid.uuid4(),
                user_id=uuid.UUID(user["id"]),
                work_id=uuid.UUID(work["id"]),
                value=5,
            )
        )
        db.add(
            Rating(
                id=uuid.uuid4(),
                user_id=uuid.UUID(user_b["id"]),
                work_id=uuid.UUID(work["id"]),
                value=3,
            )
        )
        await db.commit()

    resp = await client.get(f"/catalog/works/{work['id']}/reviews")
    body = resp.json()
    assert body["rating_count"] == 2
    assert body["rating_average"] == 4.0
    assert body["rating_distribution"] == {"1": 0, "2": 0, "3": 1, "4": 0, "5": 1}


async def test_no_ratings_yet_reports_empty_summary(two_user_client, db_sessionmaker):
    client = two_user_client
    work = (await client.post("/catalog/works", json={"title": "Oru Sankeerthanam Pole"})).json()

    resp = await client.get(f"/catalog/works/{work['id']}/reviews")
    body = resp.json()
    assert body["reviews"] == []
    assert body["rating_count"] == 0
    assert body["rating_average"] is None
    assert body["rating_distribution"] == {"1": 0, "2": 0, "3": 0, "4": 0, "5": 0}

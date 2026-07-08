"""Public profiles: visible by default (owner decision, 9 Jul 2026), 404 when
opted out, and the public-library endpoint gated on BOTH visibilities —
private and non-existent must be indistinguishable."""

import uuid

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.db import get_db
from app.core.security import get_current_user
from app.main import create_app
from app.models import LibraryEntry, Profile
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


async def test_bootstrap_creates_a_public_by_default_profile(two_user_client, user):
    resp = await two_user_client.post("/auth/bootstrap")
    assert resp.status_code in (200, 201)
    me = (await two_user_client.get("/me")).json()
    assert me["profile_visible"] is True  # public by default
    assert me["library_visible"] is False  # library stays opt-in


async def test_public_profile_visible_and_private_is_404(
    two_user_client, db_sessionmaker, user, user_b
):
    client = two_user_client
    async with db_sessionmaker() as db:
        db.add(
            Profile(
                id=uuid.UUID(user_b["id"]),
                email=user_b["email"],
                username="anu",
                full_name="Anu Varghese",
                avatar_url="https://img.example/anu.jpg",
                profile_visible=True,
            )
        )
        await db.commit()

    resp = await client.get(f"/users/{user_b['id']}/profile")
    assert resp.status_code == 200
    body = resp.json()
    assert body["username"] == "anu"
    assert body["avatar_url"] == "https://img.example/anu.jpg"
    assert body["library_visible"] is False

    # They opt out → indistinguishable from non-existent.
    async with db_sessionmaker() as db:
        p = await db.get(Profile, uuid.UUID(user_b["id"]))
        p.profile_visible = False
        await db.commit()
    assert (await client.get(f"/users/{user_b['id']}/profile")).status_code == 404
    assert (await client.get(f"/users/{uuid.uuid4()}/profile")).status_code == 404


async def test_public_library_gated_on_library_visibility(
    two_user_client, db_sessionmaker, user, user_b
):
    client = two_user_client
    # user_b: public profile, one catalog book on their shelf.
    work = (await client.post("/catalog/works", json={"title": "Chemmeen"})).json()
    async with db_sessionmaker() as db:
        db.add(
            Profile(
                id=uuid.UUID(user_b["id"]),
                email=user_b["email"],
                username="anu",
                profile_visible=True,
                library_visible=False,
            )
        )
        db.add(
            LibraryEntry(
                id=uuid.uuid4(),
                user_id=uuid.UUID(user_b["id"]),
                edition_id=uuid.UUID(work["editions"][0]["id"]),
                status="read",
            )
        )
        await db.commit()

    # Library private → 404 even though the profile is public.
    assert (await client.get(f"/users/{user_b['id']}/library")).status_code == 404

    async with db_sessionmaker() as db:
        p = await db.get(Profile, uuid.UUID(user_b["id"]))
        p.library_visible = True
        await db.commit()

    resp = await client.get(f"/users/{user_b['id']}/library")
    assert resp.status_code == 200
    shelf = resp.json()
    assert len(shelf) == 1
    assert shelf[0]["title"] == "Chemmeen"
    assert shelf[0]["status"] == "read"
    assert shelf[0]["work_id"] == work["id"]

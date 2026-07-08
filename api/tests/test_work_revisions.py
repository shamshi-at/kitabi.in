"""Wiki-style moderated edits: the contributor's changes apply live; anyone
else's queue as a pending revision the contributor approves or rejects. Works
without a contributor (OpenLibrary imports/seeds) edit live for everyone."""

import uuid

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text

from app.core.db import get_db
from app.core.security import get_current_user
from app.main import create_app
from app.models import Profile


def _client(db_sessionmaker, who: dict) -> AsyncClient:
    app = create_app()

    async def override_db():
        async with db_sessionmaker() as session:
            yield session

    app.dependency_overrides[get_db] = override_db
    app.dependency_overrides[get_current_user] = lambda: who
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


async def _make_profile(db_sessionmaker, user: dict, name: str) -> None:
    async with db_sessionmaker() as session:
        session.add(Profile(id=uuid.UUID(user["id"]), email=user["email"], full_name=name))
        await session.commit()


@pytest.fixture
def user_b() -> dict:
    return {"id": str(uuid.uuid4()), "email": "editor@example.com"}


async def _create_work(client: AsyncClient, title: str = "Chemmeen") -> dict:
    resp = await client.post(
        "/catalog/works",
        json={"title": title, "author_names": ["Thakazhi"], "description": "Original blurb."},
    )
    assert resp.status_code == 201
    return resp.json()


async def test_contributor_edits_apply_immediately(db_sessionmaker, user):
    async with _client(db_sessionmaker, user) as c:
        work = await _create_work(c)
        resp = await c.patch(f"/catalog/works/{work['id']}", json={"description": "Better blurb."})
        assert resp.status_code == 200
        body = resp.json()
        assert body["applied"] is True
        assert body["work"]["description"] == "Better blurb."


async def test_other_users_edit_queues_a_pending_revision(db_sessionmaker, user, user_b):
    await _make_profile(db_sessionmaker, user_b, "Anu")
    async with _client(db_sessionmaker, user) as owner, _client(db_sessionmaker, user_b) as other:
        work = await _create_work(owner)

        resp = await other.patch(
            f"/catalog/works/{work['id']}", json={"description": "Someone else's blurb."}
        )
        assert resp.status_code == 200
        body = resp.json()
        assert body["applied"] is False
        assert body["revision_id"] is not None
        # The live entry is untouched until the contributor approves.
        assert body["work"]["description"] == "Original blurb."

        # It shows up in the contributor's inbox — with proposer name.
        resp = await owner.get("/catalog/revisions/pending")
        inbox = resp.json()
        assert len(inbox) == 1
        assert inbox[0]["work_title"] == "Chemmeen"
        assert inbox[0]["proposed_by_name"] == "Anu"
        assert inbox[0]["payload"] == {"description": "Someone else's blurb."}
        # ...and not in the proposer's.
        resp = await other.get("/catalog/revisions/pending")
        assert resp.json() == []


async def test_approve_applies_the_revision(db_sessionmaker, user, user_b):
    async with _client(db_sessionmaker, user) as owner, _client(db_sessionmaker, user_b) as other:
        work = await _create_work(owner)
        resp = await other.patch(
            f"/catalog/works/{work['id']}",
            json={"description": "Approved blurb.", "first_publish_year": 1956},
        )
        revision_id = resp.json()["revision_id"]

        resp = await owner.post(f"/catalog/revisions/{revision_id}/approve")
        assert resp.status_code == 200
        assert resp.json()["description"] == "Approved blurb."
        assert resp.json()["first_publish_year"] == 1956

        # Decided — gone from the inbox, and not decidable twice.
        assert (await owner.get("/catalog/revisions/pending")).json() == []
        assert (await owner.post(f"/catalog/revisions/{revision_id}/approve")).status_code == 404


async def test_reject_leaves_the_work_unchanged(db_sessionmaker, user, user_b):
    async with _client(db_sessionmaker, user) as owner, _client(db_sessionmaker, user_b) as other:
        work = await _create_work(owner)
        resp = await other.patch(
            f"/catalog/works/{work['id']}", json={"description": "Rejected blurb."}
        )
        revision_id = resp.json()["revision_id"]

        assert (await owner.post(f"/catalog/revisions/{revision_id}/reject")).status_code == 204
        resp = await owner.get(f"/catalog/works/{work['id']}")
        assert resp.json()["description"] == "Original blurb."


async def test_only_the_contributor_can_decide(db_sessionmaker, user, user_b):
    async with _client(db_sessionmaker, user) as owner, _client(db_sessionmaker, user_b) as other:
        work = await _create_work(owner)
        resp = await other.patch(
            f"/catalog/works/{work['id']}", json={"description": "Sneaky self-approve."}
        )
        revision_id = resp.json()["revision_id"]
        # The proposer can't approve their own edit.
        assert (await other.post(f"/catalog/revisions/{revision_id}/approve")).status_code == 403


async def test_unowned_works_edit_live_for_everyone(db_sessionmaker, user, user_b):
    async with _client(db_sessionmaker, user) as owner, _client(db_sessionmaker, user_b) as other:
        work = await _create_work(owner)
        # Simulate an OpenLibrary-imported work: no contributor.
        async with db_sessionmaker() as session:
            await session.execute(
                text("UPDATE works SET created_by_user_id = NULL WHERE id = :id"),
                {"id": work["id"]},
            )
            await session.commit()

        resp = await other.patch(
            f"/catalog/works/{work['id']}", json={"description": "Community fix."}
        )
        assert resp.json()["applied"] is True
        assert resp.json()["work"]["description"] == "Community fix."

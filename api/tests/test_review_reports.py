"""Reporting a public review into the moderation queue
(POST /catalog/reviews/{id}/report → content_reports, the table the admin
console's /moderation/reports already reads): filing creates one open row,
re-filing while it is open adds nothing, your own review is refused, and a
review already hidden (or never visible) is a quiet success with no row —
the reporter's goal is met either way."""

import uuid

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.core.db import get_db
from app.core.security import get_current_user
from app.main import create_app
from app.models import REPORT_OPEN, ContentReport, Profile, Review
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


async def _seed_review(client, db_sessionmaker, user_b, *, visible: bool = True) -> uuid.UUID:
    work = (await client.post("/catalog/works", json={"title": "Chemmeen"})).json()
    review_id = uuid.uuid4()
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
                id=review_id,
                user_id=uuid.UUID(user_b["id"]),
                work_id=uuid.UUID(work["id"]),
                body="A quiet, devastating book.",
                visible=visible,
            )
        )
        await db.commit()
    return review_id


async def _open_reports(db_sessionmaker, review_id: uuid.UUID) -> list[ContentReport]:
    async with db_sessionmaker() as db:
        return list(
            (
                await db.execute(
                    select(ContentReport).where(
                        ContentReport.target_type == "review",
                        ContentReport.target_id == review_id,
                    )
                )
            )
            .scalars()
            .all()
        )


async def test_report_files_one_open_row(two_user_client, db_sessionmaker, user, user_b):
    client = two_user_client
    review_id = await _seed_review(client, db_sessionmaker, user_b)

    resp = await client.post(f"/catalog/reviews/{review_id}/report", json={"reason": "Spam"})
    assert resp.status_code == 200
    assert resp.json()["status"] == "filed"

    rows = await _open_reports(db_sessionmaker, review_id)
    assert len(rows) == 1
    assert rows[0].reporter_user_id == uuid.UUID(user["id"])
    assert rows[0].reason == "Spam"
    assert rows[0].status == REPORT_OPEN


async def test_second_report_by_same_reader_is_idempotent(two_user_client, db_sessionmaker, user_b):
    client = two_user_client
    review_id = await _seed_review(client, db_sessionmaker, user_b)

    await client.post(f"/catalog/reviews/{review_id}/report", json={"reason": "Spam"})
    resp = await client.post(f"/catalog/reviews/{review_id}/report", json={"reason": "Offensive"})
    assert resp.status_code == 200
    assert resp.json()["status"] == "already_reported"
    assert len(await _open_reports(db_sessionmaker, review_id)) == 1


async def test_two_readers_file_two_reports(two_user_client, db_sessionmaker, user, user_b):
    # user_c reports too — the queue groups them, so both rows must exist.
    client = two_user_client
    review_id = await _seed_review(client, db_sessionmaker, user_b)
    user_c = {"id": str(uuid.uuid4()), "email": "c@example.com"}

    await client.post(f"/catalog/reviews/{review_id}/report", json={"reason": "Spam"})
    client.as_user(user_c)
    resp = await client.post(f"/catalog/reviews/{review_id}/report", json={})
    assert resp.json()["status"] == "filed"

    rows = await _open_reports(db_sessionmaker, review_id)
    assert {r.reporter_user_id for r in rows} == {uuid.UUID(user["id"]), uuid.UUID(user_c["id"])}


async def test_own_review_is_refused(two_user_client, db_sessionmaker, user, user_b):
    client = two_user_client
    review_id = await _seed_review(client, db_sessionmaker, user_b)

    client.as_user(user_b)
    resp = await client.post(f"/catalog/reviews/{review_id}/report", json={})
    assert resp.status_code == 400
    assert resp.json()["code"] == "own_review"
    assert await _open_reports(db_sessionmaker, review_id) == []


async def test_hidden_review_is_quiet_success_without_a_row(
    two_user_client, db_sessionmaker, user_b
):
    client = two_user_client
    review_id = await _seed_review(client, db_sessionmaker, user_b, visible=False)

    resp = await client.post(f"/catalog/reviews/{review_id}/report", json={"reason": "Spam"})
    assert resp.status_code == 200
    assert resp.json()["status"] == "already_hidden"
    assert await _open_reports(db_sessionmaker, review_id) == []


async def test_unknown_review_is_404(two_user_client):
    resp = await two_user_client.post(f"/catalog/reviews/{uuid.uuid4()}/report", json={})
    assert resp.status_code == 404


async def test_overlong_reason_is_rejected(two_user_client, db_sessionmaker, user_b):
    client = two_user_client
    review_id = await _seed_review(client, db_sessionmaker, user_b)
    resp = await client.post(f"/catalog/reviews/{review_id}/report", json={"reason": "x" * 201})
    assert resp.status_code == 422

"""Peer-to-peer lending connections — the consent flow (request → accept/deny).

Needs two users acting at once, so it builds its own clients rather than using
the single-user `client` fixture.
"""

import uuid

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.db import get_db
from app.core.security import get_current_user
from app.main import create_app
from app.models.profile import Profile


def _client(db_sessionmaker, who: dict) -> AsyncClient:
    app = create_app()

    async def override_db():
        async with db_sessionmaker() as session:
            yield session

    app.dependency_overrides[get_db] = override_db
    app.dependency_overrides[get_current_user] = lambda: who
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


async def _make_profile(db_sessionmaker, user: dict, username: str) -> None:
    async with db_sessionmaker() as session:
        session.add(Profile(id=uuid.UUID(user["id"]), email=user["email"], username=username))
        await session.commit()


@pytest.fixture
def user_b() -> dict:
    return {"id": str(uuid.uuid4()), "email": "bob@example.com"}


async def test_request_then_accept(db_sessionmaker, user, user_b):
    await _make_profile(db_sessionmaker, user, "alice")
    await _make_profile(db_sessionmaker, user_b, "bob")

    async with _client(db_sessionmaker, user) as a, _client(db_sessionmaker, user_b) as b:
        resp = await a.post("/connections", json={"addressee_id": user_b["id"]})
        assert resp.status_code == 201
        assert resp.json()["status"] == "pending_out"

        # B sees it as an incoming request, from alice.
        resp = await b.get("/connections")
        incoming = resp.json()["incoming"]
        assert len(incoming) == 1
        assert incoming[0]["other"]["username"] == "alice"
        assert incoming[0]["role"] == "addressee"
        conn_id = incoming[0]["id"]

        # A sees it as outgoing.
        assert len((await a.get("/connections")).json()["outgoing"]) == 1

        # B accepts.
        assert (await b.post(f"/connections/{conn_id}/accept")).status_code == 204

        # Now accepted for both, and it moves out of pending buckets.
        assert (await a.get("/connections/status/" + user_b["id"])).json()["status"] == "accepted"
        a_conns = (await a.get("/connections")).json()
        assert a_conns["outgoing"] == []
        assert len(a_conns["accepted"]) == 1


async def test_mutual_request_auto_accepts(db_sessionmaker, user, user_b):
    await _make_profile(db_sessionmaker, user, "alice")
    await _make_profile(db_sessionmaker, user_b, "bob")

    async with _client(db_sessionmaker, user) as a, _client(db_sessionmaker, user_b) as b:
        await a.post("/connections", json={"addressee_id": user_b["id"]})
        # B requesting A back is treated as acceptance — no second row, now accepted.
        resp = await b.post("/connections", json={"addressee_id": user["id"]})
        assert resp.json()["status"] == "accepted"
        assert len((await b.get("/connections")).json()["accepted"]) == 1


async def test_cannot_connect_to_self(db_sessionmaker, user):
    await _make_profile(db_sessionmaker, user, "alice")
    async with _client(db_sessionmaker, user) as a:
        resp = await a.post("/connections", json={"addressee_id": user["id"]})
        assert resp.status_code == 400
        assert resp.json()["code"] == "self_connection"


async def test_request_unknown_user_404(db_sessionmaker, user):
    await _make_profile(db_sessionmaker, user, "alice")
    async with _client(db_sessionmaker, user) as a:
        resp = await a.post("/connections", json={"addressee_id": str(uuid.uuid4())})
        assert resp.status_code == 404


async def test_decline_then_rerequest(db_sessionmaker, user, user_b):
    await _make_profile(db_sessionmaker, user, "alice")
    await _make_profile(db_sessionmaker, user_b, "bob")

    async with _client(db_sessionmaker, user) as a, _client(db_sessionmaker, user_b) as b:
        await a.post("/connections", json={"addressee_id": user_b["id"]})
        conn_id = (await b.get("/connections")).json()["incoming"][0]["id"]

        # B declines.
        assert (await b.post(f"/connections/{conn_id}/decline")).status_code == 204
        assert (await a.get("/connections/status/" + user_b["id"])).json()["status"] == "denied"

        # A can re-request — reopens as pending, no duplicate row.
        resp = await a.post("/connections", json={"addressee_id": user_b["id"]})
        assert resp.json()["status"] == "pending_out"
        assert len((await b.get("/connections")).json()["incoming"]) == 1


async def test_only_addressee_can_accept(db_sessionmaker, user, user_b):
    await _make_profile(db_sessionmaker, user, "alice")
    await _make_profile(db_sessionmaker, user_b, "bob")

    async with _client(db_sessionmaker, user) as a, _client(db_sessionmaker, user_b) as b:
        resp = await a.post("/connections", json={"addressee_id": user_b["id"]})
        assert resp.status_code == 201
        conn_id = (await b.get("/connections")).json()["incoming"][0]["id"]
        # The requester (A) cannot accept their own request.
        assert (await a.post(f"/connections/{conn_id}/accept")).status_code == 403


async def test_denied_request_shows_as_rejected_to_sender(db_sessionmaker, user, user_b):
    await _make_profile(db_sessionmaker, user, "alice")
    await _make_profile(db_sessionmaker, user_b, "bob")
    async with _client(db_sessionmaker, user) as a, _client(db_sessionmaker, user_b) as b:
        await a.post("/connections", json={"addressee_id": user_b["id"]})
        conn_id = (await b.get("/connections")).json()["incoming"][0]["id"]
        await b.post(f"/connections/{conn_id}/decline")
        rejected = (await a.get("/connections")).json()["rejected"]
        assert len(rejected) == 1
        assert rejected[0]["other"]["username"] == "bob"


async def test_remind_requires_connection(db_sessionmaker, user, user_b):
    await _make_profile(db_sessionmaker, user, "alice")
    await _make_profile(db_sessionmaker, user_b, "bob")
    async with _client(db_sessionmaker, user) as a, _client(db_sessionmaker, user_b) as b:
        # Not connected yet — a reminder is refused.
        resp = await a.post(
            "/connections/remind", json={"user_id": user_b["id"], "book_title": "Aadujeevitham"}
        )
        assert resp.status_code == 403
        assert resp.json()["code"] == "not_connected"

        # Connect, then the reminder is accepted (push itself no-ops in tests).
        await a.post("/connections", json={"addressee_id": user_b["id"]})
        conn_id = (await b.get("/connections")).json()["incoming"][0]["id"]
        await b.post(f"/connections/{conn_id}/accept")
        resp = await a.post(
            "/connections/remind", json={"user_id": user_b["id"], "book_title": "Aadujeevitham"}
        )
        assert resp.status_code == 204


async def test_block_prevents_resend(db_sessionmaker, user, user_b):
    await _make_profile(db_sessionmaker, user, "alice")
    await _make_profile(db_sessionmaker, user_b, "bob")
    async with _client(db_sessionmaker, user) as a, _client(db_sessionmaker, user_b) as b:
        await a.post("/connections", json={"addressee_id": user_b["id"]})
        conn_id = (await b.get("/connections")).json()["incoming"][0]["id"]
        assert (await b.post(f"/connections/{conn_id}/block")).status_code == 204

        # A can no longer re-send — a blocked request is terminal.
        resp = await a.post("/connections", json={"addressee_id": user_b["id"]})
        assert resp.status_code == 403
        assert resp.json()["code"] == "blocked"
        # B sees A in the blocked bucket.
        assert len((await b.get("/connections")).json()["blocked"]) == 1


async def test_unblock_lets_them_resend_again(db_sessionmaker, user, user_b):
    await _make_profile(db_sessionmaker, user, "alice")
    await _make_profile(db_sessionmaker, user_b, "bob")
    async with _client(db_sessionmaker, user) as a, _client(db_sessionmaker, user_b) as b:
        await a.post("/connections", json={"addressee_id": user_b["id"]})
        conn_id = (await b.get("/connections")).json()["incoming"][0]["id"]
        await b.post(f"/connections/{conn_id}/block")
        # Only the blocker can unblock.
        assert (await a.post(f"/connections/{conn_id}/unblock")).status_code == 403
        assert (await b.post(f"/connections/{conn_id}/unblock")).status_code == 204
        # Now A can re-send.
        resp = await a.post("/connections", json={"addressee_id": user_b["id"]})
        assert resp.json()["status"] == "pending_out"

"""The first-lend flow: lend to a not-yet-connected Kitabi user, THEN they
accept the request — the loan must fan out at acceptance (it used to stay off
the borrower's shelf forever: mirroring was gated on an accepted connection
and never retried)."""

import uuid

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.db import get_db
from app.core.security import get_current_user
from app.main import create_app
from app.models.profile import Profile
from app.services.openlibrary_client import get_openlibrary_client

DEVICE = str(uuid.uuid4())


def _op(entity: str, entity_id: str, op_type: str, payload: dict) -> dict:
    return {
        "op_id": str(uuid.uuid4()),
        "device_id": DEVICE,
        "entity": entity,
        "entity_id": entity_id,
        "op_type": op_type,
        "payload": payload,
    }


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


async def _seed_profiles(db_sessionmaker, user, user_b) -> None:
    async with db_sessionmaker() as db:
        db.add(Profile(id=uuid.UUID(user["id"]), email=user["email"], username="lender"))
        db.add(Profile(id=uuid.UUID(user_b["id"]), email=user_b["email"], username="borrower"))
        await db.commit()


async def _lend_first_book(client: AsyncClient, borrower_id: str) -> str:
    """Lender: catalog book + library entry + a loan naming the borrower.
    Returns the loan id."""
    work = (await client.post("/catalog/works", json={"title": "Chemmeen"})).json()
    entry_id, loan_id = str(uuid.uuid4()), str(uuid.uuid4())
    resp = await client.post(
        "/sync/push",
        json={
            "ops": [
                _op(
                    "library_entries",
                    entry_id,
                    "create",
                    {"edition_id": work["editions"][0]["id"]},
                ),
                _op(
                    "lending_records",
                    loan_id,
                    "create",
                    {
                        "direction": "lent",
                        "library_entry_id": entry_id,
                        "borrower_name": "Bob",
                        "borrower_user_id": borrower_id,
                        "lent_date": "2026-07-01",
                    },
                ),
            ]
        },
    )
    assert [r["status"] for r in resp.json()["results"]] == ["applied", "applied"]
    return loan_id


async def test_accepting_the_request_fans_out_the_earlier_loan(
    two_user_client, db_sessionmaker, user, user_b
):
    client = two_user_client
    await _seed_profiles(db_sessionmaker, user, user_b)

    # Lend BEFORE any connection exists (the real first-lend flow), then send
    # the request the lend sheet sends.
    loan_id = await _lend_first_book(client, user_b["id"])
    resp = await client.post("/connections", json={"addressee_id": user_b["id"]})
    conn_id = resp.json()["connection_id"]

    # Not yet accepted → nothing on the borrower's shelf.
    client.as_user(user_b)
    changes = (await client.get("/sync/pull", params={"cursor": 0})).json()["changes"]
    assert [c for c in changes if c["entity"] == "lending_records"] == []

    # The borrower approves — the pre-existing loan must fan out right here.
    resp = await client.post(f"/connections/{conn_id}/accept")
    assert resp.status_code == 204

    changes = (await client.get("/sync/pull", params={"cursor": 0})).json()["changes"]
    mirrors = [c["data"] for c in changes if c["entity"] == "lending_records"]
    assert len(mirrors) == 1
    assert mirrors[0]["direction"] == "borrowed"
    assert mirrors[0]["linked_loan_id"] == loan_id
    assert mirrors[0]["returned_date"] is None


async def test_mutual_request_backfills_too(two_user_client, db_sessionmaker, user, user_b):
    """The other acceptance path: the borrower connects by sending their own
    request (mutual intent auto-accepts) — the loan must fan out then as well."""
    client = two_user_client
    await _seed_profiles(db_sessionmaker, user, user_b)

    loan_id = await _lend_first_book(client, user_b["id"])
    await client.post("/connections", json={"addressee_id": user_b["id"]})

    client.as_user(user_b)
    resp = await client.post("/connections", json={"addressee_id": user["id"]})
    assert resp.json()["status"] == "accepted"

    changes = (await client.get("/sync/pull", params={"cursor": 0})).json()["changes"]
    mirrors = [c["data"] for c in changes if c["entity"] == "lending_records"]
    assert len(mirrors) == 1
    assert mirrors[0]["linked_loan_id"] == loan_id


async def test_backfill_skips_returned_history_is_still_mirrored(
    two_user_client, db_sessionmaker, user, user_b
):
    """A loan already returned before the link still mirrors (it's history the
    borrower may want), and accepting twice doesn't duplicate mirrors."""
    client = two_user_client
    await _seed_profiles(db_sessionmaker, user, user_b)

    loan_id = await _lend_first_book(client, user_b["id"])
    resp = await client.post(
        "/sync/push",
        json={"ops": [_op("lending_records", loan_id, "update", {"returned_date": "2026-07-05"})]},
    )
    assert resp.json()["results"][0]["status"] == "applied"

    resp = await client.post("/connections", json={"addressee_id": user_b["id"]})
    conn_id = resp.json()["connection_id"]
    client.as_user(user_b)
    await client.post(f"/connections/{conn_id}/accept")
    # Idempotent: accepting again (no-op server-side) must not duplicate.
    await client.post(f"/connections/{conn_id}/accept")

    changes = (await client.get("/sync/pull", params={"cursor": 0})).json()["changes"]
    mirrors = [c["data"] for c in changes if c["entity"] == "lending_records"]
    assert len(mirrors) == 1
    assert mirrors[0]["returned_date"] == "2026-07-05"

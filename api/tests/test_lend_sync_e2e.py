"""End-to-end lending sync over the real HTTP contract — the exact loop the
apps run: lender pushes a loan, borrower pulls the mirror, borrower marks it
returned, lender pulls the return. Both directions of the linked pair."""

import uuid

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.db import get_db
from app.core.security import get_current_user
from app.main import create_app
from app.models.connection import Connection
from app.models.profile import Profile
from app.services.openlibrary_client import get_openlibrary_client

# One stable device per user, as in the real app (device_id is per-install).
DEVICE_LENDER = str(uuid.uuid4())
DEVICE_BORROWER = str(uuid.uuid4())


def _op(entity: str, entity_id: str, op_type: str, payload: dict, device: str) -> dict:
    return {
        "op_id": str(uuid.uuid4()),
        "device_id": device,
        "entity": entity,
        "entity_id": entity_id,
        "op_type": op_type,
        "payload": payload,
    }


@pytest.fixture
async def two_user_client(db_sessionmaker, user, user_b, fake_ol_client):
    """One client whose authenticated user can be switched mid-test — `.as_user()`
    picks which side of the loan is pushing/pulling."""
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


async def test_lend_and_return_round_trip(two_user_client, db_sessionmaker, user, user_b):
    client = two_user_client
    lender, borrower = uuid.UUID(user["id"]), uuid.UUID(user_b["id"])

    # The two readers exist and are connected (accepted) — the mirror gate.
    async with db_sessionmaker() as db:
        db.add(Profile(id=lender, email=user["email"], username="lender", full_name="Lena"))
        db.add(Profile(id=borrower, email=user_b["email"], username="borrower", full_name="Bob"))
        db.add(Connection(requester_id=lender, addressee_id=borrower, status="accepted"))
        await db.commit()

    # Lender: a catalog book, a library entry, and a loan to the borrower.
    work = (await client.post("/catalog/works", json={"title": "Khasakkinte Itihasam"})).json()
    edition_id = work["editions"][0]["id"]
    entry_id, loan_id = str(uuid.uuid4()), str(uuid.uuid4())
    resp = await client.post(
        "/sync/push",
        json={
            "ops": [
                _op(
                    "library_entries", entry_id, "create", {"edition_id": edition_id}, DEVICE_LENDER
                ),
                _op(
                    "lending_records",
                    loan_id,
                    "create",
                    {
                        "direction": "lent",
                        "library_entry_id": entry_id,
                        "borrower_name": "Bob",
                        "borrower_user_id": str(borrower),
                        "lent_date": "2026-07-01",
                    },
                    DEVICE_LENDER,
                ),
            ]
        },
    )
    assert [r["status"] for r in resp.json()["results"]] == ["applied", "applied"]

    # Borrower: the mirror arrives on a plain cursor pull, ready for the shelf.
    client.as_user(user_b)
    changes = (await client.get("/sync/pull", params={"cursor": 0})).json()["changes"]
    mirrors = [c["data"] for c in changes if c["entity"] == "lending_records"]
    assert len(mirrors) == 1
    mirror = mirrors[0]
    assert mirror["direction"] == "borrowed"
    assert mirror["linked_loan_id"] == loan_id
    assert mirror["edition_id"] == edition_id
    assert mirror["returned_date"] is None

    # Borrower marks it returned — exactly what the app's markReturned pushes.
    resp = await client.post(
        "/sync/push",
        json={
            "ops": [
                _op(
                    "lending_records",
                    mirror["id"],
                    "update",
                    {"returned_date": "2026-07-20"},
                    DEVICE_BORROWER,
                )
            ]
        },
    )
    assert resp.json()["results"][0]["status"] == "applied"

    # Lender: the return reflects back onto the original record via pull.
    client.as_user(user)
    changes = (await client.get("/sync/pull", params={"cursor": 0})).json()["changes"]
    lent = next(c["data"] for c in changes if c["entity"] == "lending_records")
    assert lent["id"] == loan_id
    assert lent["returned_date"] == "2026-07-20"


async def test_lender_return_reaches_borrower(two_user_client, db_sessionmaker, user, user_b):
    """The originally-reported direction: the lender marks the loan returned
    and the borrower's next pull carries it (mirror re-pulled via seq bump)."""
    client = two_user_client
    lender, borrower = uuid.UUID(user["id"]), uuid.UUID(user_b["id"])

    async with db_sessionmaker() as db:
        db.add(Profile(id=lender, email=user["email"], username="lender"))
        db.add(Profile(id=borrower, email=user_b["email"], username="borrower"))
        db.add(Connection(requester_id=lender, addressee_id=borrower, status="accepted"))
        await db.commit()

    work = (await client.post("/catalog/works", json={"title": "Randamoozham"})).json()
    edition_id = work["editions"][0]["id"]
    entry_id, loan_id = str(uuid.uuid4()), str(uuid.uuid4())
    await client.post(
        "/sync/push",
        json={
            "ops": [
                _op(
                    "library_entries", entry_id, "create", {"edition_id": edition_id}, DEVICE_LENDER
                ),
                _op(
                    "lending_records",
                    loan_id,
                    "create",
                    {
                        "direction": "lent",
                        "library_entry_id": entry_id,
                        "borrower_name": "Bob",
                        "borrower_user_id": str(borrower),
                        "lent_date": "2026-07-01",
                    },
                    DEVICE_LENDER,
                ),
            ]
        },
    )

    # Borrower syncs once — mirror arrives, cursor advances past it.
    client.as_user(user_b)
    page = (await client.get("/sync/pull", params={"cursor": 0})).json()
    cursor_after_first_sync = page["next_cursor"]

    # Lender marks the loan returned.
    client.as_user(user)
    resp = await client.post(
        "/sync/push",
        json={
            "ops": [
                _op(
                    "lending_records",
                    loan_id,
                    "update",
                    {"returned_date": "2026-07-21"},
                    DEVICE_LENDER,
                )
            ]
        },
    )
    assert resp.json()["results"][0]["status"] == "applied"

    # Borrower's next incremental pull (from the advanced cursor) sees the
    # mirror again, now returned — this is what was silently not happening
    # when the mirror's server_seq wasn't re-pullable.
    client.as_user(user_b)
    changes = (await client.get("/sync/pull", params={"cursor": cursor_after_first_sync})).json()[
        "changes"
    ]
    mirrors = [c["data"] for c in changes if c["entity"] == "lending_records"]
    assert len(mirrors) == 1
    assert mirrors[0]["returned_date"] == "2026-07-21"

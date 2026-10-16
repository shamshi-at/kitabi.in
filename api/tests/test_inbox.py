"""The in-app inbox behind the bell on Home (owner request, 14 Oct 2026): every
reader-to-reader notification is kept where the reader can find it again, with
read state and clearing — written even though push is off in tests, which is
the point: the bell must not depend on push being configured."""

import uuid

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.db import get_db
from app.core.security import get_current_user
from app.main import create_app
from app.models import Profile


@pytest.fixture
async def client(db_sessionmaker, user):
    app = create_app()
    current = {"user": user}

    async def override_db():
        async with db_sessionmaker() as session:
            yield session

    app.dependency_overrides[get_db] = override_db
    app.dependency_overrides[get_current_user] = lambda: current["user"]
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        c.as_user = lambda u: current.update(user=u)  # type: ignore[attr-defined]
        yield c


@pytest.fixture
async def anu(db_sessionmaker, user):
    other = {"id": str(uuid.uuid4()), "email": "anu@example.com"}
    async with db_sessionmaker() as db:
        db.add(Profile(id=uuid.UUID(user["id"]), email=user["email"], full_name="Shamshi"))
        db.add(Profile(id=uuid.UUID(other["id"]), email=other["email"], full_name="Anu Thomas"))
        await db.commit()
    return other


async def test_a_request_lands_in_the_bell_once(client, user, anu):
    await client.post("/connections", json={"addressee_id": anu["id"]})
    # Re-tapping Connect on a pending request must not say it twice.
    await client.post("/connections", json={"addressee_id": anu["id"]})

    client.as_user(anu)
    assert (await client.get("/notifications/unread")).json() == {"unread": 1}
    inbox = (await client.get("/notifications")).json()
    item = inbox["items"][0]
    assert inbox["unread"] == 1
    assert item["type"] == "connection_request"
    assert item["title"] == "New connection request"
    assert item["body"] == "Shamshi wants to connect on Kitabi"
    assert item["read"] is False
    assert item["actor"]["name"] == "Shamshi"
    assert item["data"] == {"type": "connection_request"}

    # Nothing for the sender.
    client.as_user(user)
    assert (await client.get("/notifications")).json() == {"unread": 0, "items": []}


async def test_accepting_tells_the_requester(client, user, anu):
    resp = await client.post("/connections", json={"addressee_id": anu["id"]})
    client.as_user(anu)
    await client.post(f"/connections/{resp.json()['connection_id']}/accept")
    client.as_user(user)
    items = (await client.get("/notifications")).json()["items"]
    assert [i["body"] for i in items] == ["Anu Thomas accepted your connection on Kitabi"]


async def test_read_one_read_all_and_clear(client, user, anu):
    resp = await client.post("/connections", json={"addressee_id": anu["id"]})
    client.as_user(anu)
    await client.post(f"/connections/{resp.json()['connection_id']}/accept")
    client.as_user(user)
    await client.post("/connections/remind", json={"user_id": anu["id"], "book_title": "Kaalam"})
    client.as_user(anu)
    first = (await client.get("/notifications")).json()["items"]
    assert [i["type"] for i in first] == ["lend_reminder", "connection_request"]
    assert first[0]["body"] == "Shamshi would like “Kaalam” back"

    # Someone else can't mark my notifications read.
    client.as_user(user)
    await client.post("/notifications/read", json={"ids": [first[0]["id"]]})
    client.as_user(anu)
    assert (await client.get("/notifications/unread")).json()["unread"] == 2

    await client.post("/notifications/read", json={"ids": [first[0]["id"]]})
    inbox = (await client.get("/notifications")).json()
    assert inbox["unread"] == 1
    assert [i["read"] for i in inbox["items"]] == [True, False]

    await client.post("/notifications/read-all")
    assert (await client.get("/notifications/unread")).json()["unread"] == 0

    await client.post("/notifications/clear")
    assert (await client.get("/notifications")).json() == {"unread": 0, "items": []}

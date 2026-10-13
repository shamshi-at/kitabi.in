"""Your circle — connections' reading, gated on each person's own consent
(docs/circle-reading-mockups.html). Most of these are privacy tests: every rule
in circle_service's docstring has a case here that fails if it is dropped."""

import uuid
from datetime import UTC, date, datetime, timedelta

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.api import circle as circle_api
from app.core.db import get_db
from app.core.security import get_current_user
from app.main import create_app
from app.models import Author, Connection, Edition, LibraryEntry, Profile, Rating, Review, Work
from app.models.borrow_request import BorrowRequest
from app.models.read import Read

TODAY = datetime.now(UTC).date()


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


def _who(name: str) -> dict:
    return {"id": str(uuid.uuid4()), "email": f"{name}@example.com"}


async def _profile(db, who: dict, name: str, *, reading=False, ratings=False, owned=False):
    db.add(
        Profile(
            id=uuid.UUID(who["id"]),
            email=who["email"],
            full_name=name,
            circle_share_reading=reading,
            circle_share_ratings=ratings,
            circle_share_owned=owned,
        )
    )


def _connect(db, a: dict, b: dict, status: str = "accepted"):
    db.add(
        Connection(requester_id=uuid.UUID(a["id"]), addressee_id=uuid.UUID(b["id"]), status=status)
    )


async def _book(db, title: str, *, group: uuid.UUID | None = None, language=None):
    author = Author(name=f"Author of {title}")
    work = Work(title=title, authors=[author], translation_group_id=group, language=language)
    db.add(work)
    await db.flush()
    edition = Edition(work_id=work.id)
    db.add(edition)
    await db.flush()
    return work, edition


def _entry(db, who: dict, edition: Edition, status="read", **kw) -> LibraryEntry:
    entry = LibraryEntry(
        id=uuid.uuid4(), user_id=uuid.UUID(who["id"]), edition_id=edition.id, status=status, **kw
    )
    db.add(entry)
    return entry


def _rate(db, who: dict, work: Work, value: int):
    db.add(Rating(id=uuid.uuid4(), user_id=uuid.UUID(who["id"]), work_id=work.id, value=value))


@pytest.fixture
async def world(db_sessionmaker, user):
    """Me plus four connections with different consents, and one stranger."""
    anu, rahul, faisal, quiet, stranger = (_who(n) for n in ("anu", "rahul", "faisal", "q", "s"))
    async with db_sessionmaker() as db:
        await _profile(db, user, "Me", reading=True, ratings=True)
        await _profile(db, anu, "Anu", reading=True, ratings=True)
        await _profile(db, rahul, "Rahul", reading=True)  # no ratings
        await _profile(db, faisal, "Faisal", owned=True)  # owns only
        await _profile(db, quiet, "Quiet")  # shares nothing
        await _profile(db, stranger, "Stranger", reading=True, ratings=True, owned=True)
        for other in (anu, rahul, faisal, quiet):
            _connect(db, user, other)
        await db.commit()
    return {"anu": anu, "rahul": rahul, "faisal": faisal, "quiet": quiet, "stranger": stranger}


async def test_book_page_shows_only_what_each_person_shares(client, db_sessionmaker, world):
    async with db_sessionmaker() as db:
        work, edition = await _book(db, "Randamoozham")
        _entry(db, world["anu"], edition, finish_date=TODAY)
        _rate(db, world["anu"], work, 5)
        db.add(
            Review(
                id=uuid.uuid4(),
                user_id=uuid.UUID(world["anu"]["id"]),
                work_id=work.id,
                body="The Bhima I never knew I needed.",
                visible=True,
            )
        )
        _entry(db, world["rahul"], edition, status="reading", start_date=TODAY)
        _rate(db, world["rahul"], work, 2)  # not shared: ratings switch off
        _entry(db, world["faisal"], edition, status="read")  # status not shared
        _rate(db, world["faisal"], work, 1)
        _entry(db, world["quiet"], edition)
        _entry(db, world["stranger"], edition)
        await db.commit()

    body = (await client.get(f"/circle/works/{work.id}")).json()
    by_name = {p["name"]: p for p in body["people"]}
    assert set(by_name) == {"Anu", "Rahul", "Faisal"}
    assert by_name["Anu"]["status"] == "read"
    assert by_name["Anu"]["rating"] == 5
    assert by_name["Anu"]["review"] == "The Bhima I never knew I needed."
    assert by_name["Rahul"]["status"] == "reading"
    assert by_name["Rahul"]["rating"] is None
    # Faisal shares owning, not reading — so he is a copy, not a reader.
    assert by_name["Faisal"]["status"] is None and by_name["Faisal"]["owns"] is True
    assert by_name["Faisal"]["rating"] is None
    assert body["read_count"] == 1 and body["reading_count"] == 1 and body["owns_count"] == 1
    assert body["avg_rating"] == 5.0


async def test_pending_denied_and_blocked_connections_never_count(
    client, db_sessionmaker, user, world
):
    async with db_sessionmaker() as db:
        _, edition = await _book(db, "Naalukettu")
        for status in ("pending", "denied", "blocked"):
            who = _who(status)
            await _profile(db, who, status, reading=True, ratings=True, owned=True)
            _connect(db, user, who, status=status)
            _entry(db, who, edition)
        await db.commit()
    body = (await client.get(f"/circle/works/{edition.work_id}")).json()
    assert body["people"] == []


async def test_kept_to_myself_hides_the_person_on_that_book_entirely(
    client, db_sessionmaker, world
):
    async with db_sessionmaker() as db:
        work, edition = await _book(db, "Pathummayude Aadu")
        other_printing = Edition(work_id=work.id)
        db.add(other_printing)
        await db.flush()
        # One hidden copy hides every copy of the same book.
        _entry(db, world["anu"], edition, circle_hidden=True)
        _entry(db, world["anu"], other_printing, status="reading")
        _rate(db, world["anu"], work, 5)
        await db.commit()
    body = (await client.get(f"/circle/works/{work.id}")).json()
    assert body["people"] == [] and body["avg_rating"] is None


async def test_private_review_is_never_quoted(client, db_sessionmaker, world):
    async with db_sessionmaker() as db:
        work, edition = await _book(db, "Manju")
        _entry(db, world["anu"], edition)
        db.add(
            Review(
                id=uuid.uuid4(),
                user_id=uuid.UUID(world["anu"]["id"]),
                work_id=work.id,
                body="private thoughts",
                visible=False,
            )
        )
        await db.commit()
    body = (await client.get(f"/circle/works/{work.id}")).json()
    assert body["people"][0]["review"] is None


async def test_wishlist_is_not_reading_and_not_owning(client, db_sessionmaker, world):
    async with db_sessionmaker() as db:
        _, edition = await _book(db, "Kaalam")
        _entry(db, world["anu"], edition, status="wishlist")
        _entry(db, world["faisal"], edition, status="wishlist")
        await db.commit()
    body = (await client.get(f"/circle/works/{edition.work_id}")).json()
    assert body["people"] == []


async def test_read_count_comes_from_reads(client, db_sessionmaker, world):
    async with db_sessionmaker() as db:
        _, edition = await _book(db, "Khasakkinte Itihasam")
        entry = _entry(db, world["anu"], edition, status="reading")
        await db.flush()
        for year in (2024, 2025):
            db.add(
                Read(
                    id=uuid.uuid4(),
                    user_id=entry.user_id,
                    library_entry_id=entry.id,
                    status="read",
                    finish_date=date(year, 3, 1),
                )
            )
        await db.commit()
    person = (await client.get(f"/circle/works/{edition.work_id}")).json()["people"][0]
    # Re-reading: currently reading, two finished passes behind it.
    assert person["status"] == "reading" and person["read_count"] == 2


async def test_reciprocity_caller_who_shares_nothing_gets_an_invite(
    client, db_sessionmaker, user, world
):
    async with db_sessionmaker() as db:
        _, edition = await _book(db, "Asuravithu")
        _entry(db, world["anu"], edition)
        me = await db.get(Profile, uuid.UUID(user["id"]))
        me.circle_share_reading = False
        me.circle_share_ratings = True  # ratings alone share nothing
        await db.commit()
    body = (await client.get(f"/circle/works/{edition.work_id}")).json()
    # Anu, Rahul and Faisal share something; Quiet doesn't; the stranger isn't a connection.
    assert body == {**body, "invite": 3, "people": []}
    signals = (
        await client.post("/circle/signals", json={"work_ids": [str(edition.work_id)]})
    ).json()
    assert signals == {"invite": 3, "signals": {}}
    assert (await client.get("/circle/pick")).json() == {"invite": 3, "pick": None}


async def test_signals_batch_names_faces_and_skips_silent_works(client, db_sessionmaker, world):
    async with db_sessionmaker() as db:
        _, loud = await _book(db, "Randamoozham")
        _, silent = await _book(db, "Manju")
        _entry(db, world["anu"], loud, finish_date=TODAY)
        _entry(db, world["rahul"], loud, finish_date=TODAY - timedelta(days=3))
        _entry(db, world["faisal"], loud)
        await db.commit()
    resp = await client.post(
        "/circle/signals", json={"work_ids": [str(loud.work_id), str(silent.work_id)]}
    )
    signals = resp.json()["signals"]
    assert list(signals) == [str(loud.work_id)]
    sig = signals[str(loud.work_id)]
    assert sig["read_count"] == 2 and sig["owns_count"] == 1
    assert [p["name"] for p in sig["readers"]] == ["Anu", "Rahul"]  # newest first


async def test_signals_refuses_an_oversized_batch(client, world):
    ids = [str(uuid.uuid4()) for _ in range(51)]
    assert (await client.post("/circle/signals", json={"work_ids": ids})).status_code == 422


async def test_translation_bridge(client, db_sessionmaker, world):
    group = uuid.uuid4()
    async with db_sessionmaker() as db:
        original, _ = await _book(db, "Randamoozham", group=group, language="Malayalam")
        _, english = await _book(db, "Second Turn", group=group, language="English")
        _entry(db, world["anu"], english)
        await db.commit()
    body = (await client.get(f"/circle/works/{original.id}")).json()
    assert body["translations"] == [
        {
            "work_id": str(english.work_id),
            "edition_id": str(english.id),
            "title": "Second Turn",
            "language": "English",
            "read_count": 1,
            "names": ["Anu"],
        }
    ]


async def test_pick_prefers_borrowing_a_wishlist_book(client, db_sessionmaker, user, world):
    async with db_sessionmaker() as db:
        loved, loved_ed = await _book(db, "Aadujeevitham")
        _entry(db, world["anu"], loved_ed, finish_date=TODAY)
        _rate(db, world["anu"], loved, 5)
        wanted, wanted_ed = await _book(db, "Kaalam")
        _entry(db, user, wanted_ed, status="wishlist")
        _entry(db, world["faisal"], wanted_ed, status="pending")
        await db.commit()
    pick = (await client.get("/circle/pick")).json()["pick"]
    assert pick["kind"] == "borrow"
    assert pick["work"]["id"] == str(wanted.id)
    assert pick["person"]["name"] == "Faisal"

    # Dismissed → the next reason down.
    pick = (await client.get(f"/circle/pick?dismissed={wanted.id}")).json()["pick"]
    assert pick["kind"] == "loved" and pick["person"]["name"] == "Anu"
    assert pick["person"]["rating"] == 5


async def test_pick_loved_skips_books_already_on_my_shelf_and_old_or_low_ratings(
    client, db_sessionmaker, user, world
):
    async with db_sessionmaker() as db:
        mine, mine_ed = await _book(db, "Mine already")
        _entry(db, user, mine_ed, status="read")
        _entry(db, world["anu"], mine_ed, finish_date=TODAY)
        _rate(db, world["anu"], mine, 5)
        old, old_ed = await _book(db, "Long ago")
        _entry(db, world["anu"], old_ed, finish_date=TODAY - timedelta(days=200))
        _rate(db, world["anu"], old, 5)
        meh, meh_ed = await _book(db, "Meh")
        _entry(db, world["anu"], meh_ed, finish_date=TODAY)
        _rate(db, world["anu"], meh, 3)
        await db.commit()
    assert (await client.get("/circle/pick")).json() == {"invite": None, "pick": None}


async def test_pick_cluster_and_read_along(client, db_sessionmaker, user, world):
    async with db_sessionmaker() as db:
        _, many = await _book(db, "Everyone read it")
        _entry(db, world["anu"], many, finish_date=TODAY)
        _entry(db, world["rahul"], many, finish_date=TODAY)
        await db.commit()
    pick = (await client.get("/circle/pick")).json()["pick"]
    assert pick["kind"] == "cluster"
    assert {p["name"] for p in pick["people"]} == {"Anu", "Rahul"}

    async with db_sessionmaker() as db:
        waiting, waiting_ed = await _book(db, "On my to-read")
        _entry(db, user, waiting_ed, status="pending")
        _entry(db, world["rahul"], waiting_ed, status="reading", start_date=TODAY)
        await db.commit()
    pick = (await client.get("/circle/pick")).json()["pick"]
    assert pick["kind"] == "read_along" and pick["person"]["name"] == "Rahul"


async def test_pick_kindred(client, db_sessionmaker, user, world):
    async with db_sessionmaker() as db:
        work, edition = await _book(db, "Khasakkinte Itihasam")
        _entry(db, user, edition)
        _rate(db, user, work, 5)
        _entry(db, world["anu"], edition, finish_date=TODAY - timedelta(days=400))
        _rate(db, world["anu"], work, 5)
        await db.commit()
    pick = (await client.get("/circle/pick")).json()["pick"]
    assert pick["kind"] == "kindred" and pick["my_rating"] == 5
    assert pick["person"]["name"] == "Anu"


async def test_borrow_ask_only_for_a_visible_copy(client, db_sessionmaker, world, monkeypatch):
    sent = []

    async def fake_notify(*args, **kwargs):
        sent.append(args)

    monkeypatch.setattr(circle_api.push_service, "notify_borrow_ask", fake_notify)
    async with db_sessionmaker() as db:
        _, edition = await _book(db, "Kaalam")
        _entry(db, world["faisal"], edition, status="pending")
        _, hidden = await _book(db, "Hidden one")
        _entry(db, world["faisal"], hidden, circle_hidden=True)
        _, rahuls = await _book(db, "Rahul's")
        _entry(db, world["rahul"], rahuls)  # Rahul doesn't share owning
        await db.commit()

    ok = {"owner_id": world["faisal"]["id"], "edition_id": str(edition.id)}
    assert (await client.post("/circle/borrow-ask", json=ok)).status_code == 204
    # Tapped twice: still one push.
    assert (await client.post("/circle/borrow-ask", json=ok)).status_code == 204
    assert len(sent) == 1

    for owner, ed in ((world["faisal"], hidden), (world["rahul"], rahuls)):
        payload = {"owner_id": owner["id"], "edition_id": str(ed.id)}
        assert (await client.post("/circle/borrow-ask", json=payload)).status_code == 404
    stranger = {"owner_id": world["stranger"]["id"], "edition_id": str(edition.id)}
    assert (await client.post("/circle/borrow-ask", json=stranger)).status_code == 404
    assert len(sent) == 1


async def test_an_ask_is_a_record_the_owner_can_find_and_decline(
    client, db_sessionmaker, user, world, monkeypatch
):
    """Owner report, 14 Oct 2026: the ask arrived as a push and existed nowhere
    else — tapping it found nothing, and the app had no trace of it."""
    sent = []

    async def fake_notify(*args, **kwargs):
        sent.append(args)

    monkeypatch.setattr(circle_api.push_service, "notify_borrow_ask", fake_notify)
    async with db_sessionmaker() as db:
        _, edition = await _book(db, "Kaalam")
        _entry(db, world["faisal"], edition, status="pending")
        await db.commit()
    ask = {"owner_id": world["faisal"]["id"], "edition_id": str(edition.id)}
    assert (await client.post("/circle/borrow-ask", json=ask)).status_code == 204
    request_id = sent[0][5]

    mine = (await client.get("/circle/borrow-asks")).json()
    assert mine["incoming"] == []
    assert [(a["person"]["name"], a["title"]) for a in mine["outgoing"]] == [("Faisal", "Kaalam")]

    client.as_user(world["faisal"])
    bell = (await client.get("/notifications")).json()["items"]
    assert [(i["type"], i["body"]) for i in bell] == [
        ("borrow_ask", "Me would like to borrow “Kaalam”")
    ]
    assert bell[0]["data"]["request_id"] == str(request_id)
    theirs = (await client.get("/circle/borrow-asks")).json()
    assert [(a["person"]["name"], a["title"]) for a in theirs["incoming"]] == [("Me", "Kaalam")]
    assert theirs["incoming"][0]["id"] == str(request_id)
    assert theirs["incoming"][0]["edition_id"] == str(edition.id)

    # Only the owner can answer it.
    client.as_user(user)
    assert (await client.post(f"/circle/borrow-asks/{request_id}/decline")).status_code == 404
    client.as_user(world["faisal"])
    assert (await client.post(f"/circle/borrow-asks/{request_id}/decline")).status_code == 204
    assert (await client.get("/circle/borrow-asks")).json()["incoming"] == []

    # "Not now" must not turn into a fresh notification a minute later.
    client.as_user(user)
    assert (await client.post("/circle/borrow-ask", json=ask)).status_code == 204
    assert len(sent) == 1
    assert (await client.get("/circle/borrow-asks")).json()["outgoing"] == []


async def test_lending_the_book_answers_the_ask(client, db_sessionmaker, user, world, monkeypatch):
    async def fake_notify(*args, **kwargs):
        return None

    monkeypatch.setattr(circle_api.push_service, "notify_borrow_ask", fake_notify)
    async with db_sessionmaker() as db:
        _, edition = await _book(db, "Kaalam")
        faisals = _entry(db, world["faisal"], edition, status="pending")
        await db.commit()
    ask = {"owner_id": world["faisal"]["id"], "edition_id": str(edition.id)}
    await client.post("/circle/borrow-ask", json=ask)

    # Faisal lends it to me from anywhere — here, the ordinary sync push.
    client.as_user(world["faisal"])
    loan_id = str(uuid.uuid4())
    op = {
        "op_id": str(uuid.uuid4()),
        "device_id": str(uuid.uuid4()),
        "entity": "lending_records",
        "entity_id": loan_id,
        "op_type": "create",
        "payload": {
            "id": loan_id,
            "direction": "lent",
            "library_entry_id": str(faisals.id),
            "borrower_name": "Me",
            "borrower_user_id": user["id"],
            "lent_date": TODAY.isoformat(),
        },
    }
    resp = await client.post("/sync/push", json={"ops": [op]})
    assert resp.json()["results"][0]["status"] == "applied"
    assert (await client.get("/circle/borrow-asks")).json()["incoming"] == []
    client.as_user(user)
    bodies = [i["body"] for i in (await client.get("/notifications")).json()["items"]]
    assert "Faisal lent you “Kaalam” on Kitabi" in bodies
    async with db_sessionmaker() as db:
        row = (await db.execute(select(BorrowRequest))).scalar_one()
        assert row.status == "lent" and row.resolved_at is not None


async def test_me_exposes_and_updates_circle_switches(client, world):
    me = (await client.get("/me")).json()
    assert me["circle_share_reading"] is True and me["circle_share_owned"] is False
    resp = await client.patch("/me", json={"circle_share_owned": True})
    assert resp.json()["circle_share_owned"] is True


async def test_circle_hidden_syncs_on_library_entries(client, db_sessionmaker, world):
    async with db_sessionmaker() as db:
        _, edition = await _book(db, "Synced")
        await db.commit()
    entry_id = str(uuid.uuid4())
    device = str(uuid.uuid4())
    op = {
        "op_id": str(uuid.uuid4()),
        "device_id": device,
        "entity": "library_entries",
        "entity_id": entry_id,
        "op_type": "create",
        "payload": {"id": entry_id, "edition_id": str(edition.id), "circle_hidden": True},
    }
    resp = await client.post("/sync/push", json={"ops": [op]})
    assert resp.json()["results"][0]["status"] == "applied"
    pulled = (await client.get("/sync/pull?cursor=0")).json()["changes"]
    row = next(c["data"] for c in pulled if c["entity"] == "library_entries")
    assert row["circle_hidden"] is True

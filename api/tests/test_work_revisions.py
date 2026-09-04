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


# ── Edition edits ────────────────────────────────────────────────────────────
# `PATCH /catalog/editions/{id}` had no gate at all until 5 Sep 2026: it went
# straight to update_edition, so any signed-in reader could rewrite any
# printing's ISBN, page count, format, publisher and covers on the shared
# catalogue — with no approval and no revision record — while the far less
# destructive Work-level edit beside it was queued. These pin the symmetry.


async def _live_edition(client: AsyncClient, work_id: str, edition_id: str) -> dict:
    """The printing, found by id — `editions[0]` is the blank edition
    `_create_work` makes, not the one under test (CLAUDE.md: editions[0] is a
    representative, never an answer)."""
    live = (await client.get(f"/catalog/works/{work_id}")).json()
    return next(e for e in live["editions"] if e["id"] == edition_id)


async def _edition_id(client: AsyncClient, work: dict) -> str:
    resp = await client.post(
        f"/catalog/works/{work['id']}/editions",
        json={"isbn": "9788126415419", "page_count": 184, "format": "Paperback"},
    )
    assert resp.status_code == 201
    return resp.json()["id"]


async def test_contributor_edition_edits_apply_immediately(db_sessionmaker, user):
    async with _client(db_sessionmaker, user) as c:
        work = await _create_work(c)
        edition_id = await _edition_id(c, work)

        resp = await c.patch(f"/catalog/editions/{edition_id}", json={"page_count": 216})
        assert resp.status_code == 200
        body = resp.json()
        assert body["applied"] is True
        assert body["revision_id"] is None
        assert body["edition"]["page_count"] == 216


async def test_other_users_edition_edit_queues_a_pending_revision(db_sessionmaker, user, user_b):
    await _make_profile(db_sessionmaker, user_b, "Anu")
    async with _client(db_sessionmaker, user) as owner, _client(db_sessionmaker, user_b) as other:
        work = await _create_work(owner)
        edition_id = await _edition_id(owner, work)

        resp = await other.patch(
            f"/catalog/editions/{edition_id}",
            json={"page_count": 55, "cover_url": "https://x/covers/theirs.jpg"},
        )
        assert resp.status_code == 200
        body = resp.json()
        assert body["applied"] is False
        assert body["revision_id"] is not None
        # The live printing is untouched — this is the whole point: a reader's
        # captured cover and page count no longer land on someone else's row.
        assert body["edition"]["page_count"] == 184
        assert body["edition"]["cover_url"] is None

        # …and it is really untouched in the catalogue, not just in the reply.
        assert (await _live_edition(owner, work["id"], edition_id))["page_count"] == 184

        # It lands in the *Work contributor's* inbox, naming the printing.
        inbox = (await owner.get("/catalog/revisions/pending")).json()
        assert len(inbox) == 1
        assert inbox[0]["edition_id"] == edition_id
        assert inbox[0]["work_title"] == "Chemmeen"
        assert inbox[0]["proposed_by_name"] == "Anu"
        assert inbox[0]["payload"] == {
            "page_count": 55,
            "cover_url": "https://x/covers/theirs.jpg",
        }
        # ...and not in the proposer's.
        assert (await other.get("/catalog/revisions/pending")).json() == []


async def test_approving_an_edition_revision_applies_it_to_the_printing(
    db_sessionmaker, user, user_b
):
    async with _client(db_sessionmaker, user) as owner, _client(db_sessionmaker, user_b) as other:
        work = await _create_work(owner)
        edition_id = await _edition_id(owner, work)
        resp = await other.patch(
            f"/catalog/editions/{edition_id}", json={"page_count": 240, "format": "Hardcover"}
        )
        revision_id = resp.json()["revision_id"]

        # Approving returns the live Work, edition edits included — it is what
        # every caller renders next, and it carries the printing.
        resp = await owner.post(f"/catalog/revisions/{revision_id}/approve")
        assert resp.status_code == 200
        edition = next(e for e in resp.json()["editions"] if e["id"] == edition_id)
        assert edition["page_count"] == 240
        assert edition["format"] == "Hardcover"

        assert (await owner.get("/catalog/revisions/pending")).json() == []
        assert (await owner.post(f"/catalog/revisions/{revision_id}/approve")).status_code == 404


async def test_rejecting_an_edition_revision_leaves_the_printing_unchanged(
    db_sessionmaker, user, user_b
):
    async with _client(db_sessionmaker, user) as owner, _client(db_sessionmaker, user_b) as other:
        work = await _create_work(owner)
        edition_id = await _edition_id(owner, work)
        resp = await other.patch(f"/catalog/editions/{edition_id}", json={"page_count": 55})
        revision_id = resp.json()["revision_id"]

        assert (await owner.post(f"/catalog/revisions/{revision_id}/reject")).status_code == 204
        assert (await _live_edition(owner, work["id"], edition_id))["page_count"] == 184


async def test_only_the_contributor_can_decide_an_edition_revision(db_sessionmaker, user, user_b):
    async with _client(db_sessionmaker, user) as owner, _client(db_sessionmaker, user_b) as other:
        work = await _create_work(owner)
        edition_id = await _edition_id(owner, work)
        resp = await other.patch(f"/catalog/editions/{edition_id}", json={"page_count": 55})
        revision_id = resp.json()["revision_id"]
        assert (await other.post(f"/catalog/revisions/{revision_id}/approve")).status_code == 403


async def test_unowned_editions_edit_live_for_everyone(db_sessionmaker, user, user_b):
    async with _client(db_sessionmaker, user) as owner, _client(db_sessionmaker, user_b) as other:
        work = await _create_work(owner)
        edition_id = await _edition_id(owner, work)
        # Simulate an OpenLibrary-imported book: no contributor. The gate reads
        # the *Work's* contributor, since an Edition has none of its own.
        async with db_sessionmaker() as session:
            await session.execute(
                text("UPDATE works SET created_by_user_id = NULL WHERE id = :id"),
                {"id": work["id"]},
            )
            await session.commit()

        resp = await other.patch(f"/catalog/editions/{edition_id}", json={"page_count": 216})
        assert resp.json()["applied"] is True
        assert resp.json()["edition"]["page_count"] == 216


async def test_a_wrong_isbn_can_still_be_corrected_it_just_queues(db_sessionmaker, user, user_b):
    """The approval queue is where that judgement belongs — not a hard block."""
    async with _client(db_sessionmaker, user) as owner, _client(db_sessionmaker, user_b) as other:
        work = await _create_work(owner)
        edition_id = await _edition_id(owner, work)

        resp = await other.patch(f"/catalog/editions/{edition_id}", json={"isbn": "9789386906366"})
        assert resp.status_code == 200
        revision_id = resp.json()["revision_id"]
        assert revision_id is not None

        assert (await owner.post(f"/catalog/revisions/{revision_id}/approve")).status_code == 200
        assert (await _live_edition(owner, work["id"], edition_id))["isbn"] == "9789386906366"


async def test_an_isbn_that_names_another_book_is_refused_not_queued(db_sessionmaker, user, user_b):
    """A clash is not a matter of opinion, and the app answers one by offering
    the book that ISBN already names. Queuing it instead would swap that offer
    for a "sent for approval" about an edit that could never apply."""
    async with _client(db_sessionmaker, user) as owner, _client(db_sessionmaker, user_b) as other:
        work = await _create_work(owner)
        edition_id = await _edition_id(owner, work)
        taken = await _create_work(owner, title="Balyakalasakhi")
        resp = await owner.post(
            f"/catalog/works/{taken['id']}/editions", json={"isbn": "9789386906366"}
        )
        assert resp.status_code == 201

        resp = await other.patch(f"/catalog/editions/{edition_id}", json={"isbn": "9789386906366"})
        assert resp.status_code == 409
        # Nothing queued either — the reader gets the conflict, not a promise.
        assert (await owner.get("/catalog/revisions/pending")).json() == []


async def test_an_approval_that_cannot_apply_leaves_the_revision_pending(
    db_sessionmaker, user, user_b
):
    """The ISBN was free when the edit was proposed and taken by the time the
    contributor got to it. The apply raises, the transaction rolls back, and
    the revision must still be sitting in the inbox — a queue that consumes a
    revision it failed to apply loses the edit with nothing to show for it."""
    async with _client(db_sessionmaker, user) as owner, _client(db_sessionmaker, user_b) as other:
        work = await _create_work(owner)
        edition_id = await _edition_id(owner, work)
        resp = await other.patch(f"/catalog/editions/{edition_id}", json={"isbn": "9789386906366"})
        revision_id = resp.json()["revision_id"]

        # Someone else claims that ISBN in the meantime.
        taken = await _create_work(owner, title="Balyakalasakhi")
        assert (
            await owner.post(
                f"/catalog/works/{taken['id']}/editions", json={"isbn": "9789386906366"}
            )
        ).status_code == 201

        assert (await owner.post(f"/catalog/revisions/{revision_id}/approve")).status_code == 409
        inbox = (await owner.get("/catalog/revisions/pending")).json()
        assert [r["id"] for r in inbox] == [revision_id]
        assert (await _live_edition(owner, work["id"], edition_id))["isbn"] == "9788126415419"

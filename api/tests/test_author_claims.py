"""A "This is me" author claim is queued for review, never applied on submit.

The guarantee under test: the claimant sees their claim as pending, and every
other reader keeps seeing `authors.linked_user_id` exactly as it was. Only an
approval touches the shared catalog row.
"""

import uuid

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.core.db import get_db
from app.core.security import get_current_user
from app.main import create_app
from app.models import CLAIM_PENDING, Author, AuthorClaim
from app.services import catalog_service


def _client(db_sessionmaker, who: dict) -> AsyncClient:
    app = create_app()

    async def override_db():
        async with db_sessionmaker() as session:
            yield session

    app.dependency_overrides[get_db] = override_db
    app.dependency_overrides[get_current_user] = lambda: who
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


@pytest.fixture
def user_b() -> dict:
    return {"id": str(uuid.uuid4()), "email": "claimant@example.com"}


async def _claim_row(db_sessionmaker, author_id: str) -> AuthorClaim | None:
    async with db_sessionmaker() as session:
        return (
            await session.execute(
                select(AuthorClaim).where(AuthorClaim.author_id == uuid.UUID(author_id))
            )
        ).scalar_one_or_none()


async def test_claiming_an_existing_author_does_not_link_it(client, db_sessionmaker):
    author = (await client.post("/catalog/authors", json={"name": "Anuja Menon"})).json()

    resp = await client.post(f"/catalog/authors/{author['id']}/link")

    assert resp.status_code == 200
    # The shared row is untouched — this is the whole point.
    assert resp.json()["linked_user_id"] is None
    assert resp.json()["claim_pending"] is True
    claim = await _claim_row(db_sessionmaker, author["id"])
    assert claim is not None and claim.status == CLAIM_PENDING


async def test_claimant_sees_pending_but_others_see_the_old_value(db_sessionmaker, user, user_b):
    async with _client(db_sessionmaker, user) as owner, _client(db_sessionmaker, user_b) as other:
        author = (await owner.post("/catalog/authors", json={"name": "Benyamin"})).json()
        await other.post(f"/catalog/authors/{author['id']}/link")

        mine = (await other.get(f"/catalog/authors/{author['id']}")).json()["author"]
        theirs = (await owner.get(f"/catalog/authors/{author['id']}")).json()["author"]

    assert mine["claim_pending"] is True
    # Everyone else sees no claim at all — not even that one is pending.
    assert theirs["claim_pending"] is False
    assert mine["linked_user_id"] is None and theirs["linked_user_id"] is None


async def test_create_author_is_me_queues_instead_of_linking(client, db_sessionmaker, user):
    resp = await client.post("/catalog/authors", json={"name": "Anu Varghese", "is_me": True})

    assert resp.status_code == 201
    body = resp.json()
    assert body["linked_user_id"] is None, "a brand-new row must not self-link either"
    assert body["claim_pending"] is True
    claim = await _claim_row(db_sessionmaker, body["id"])
    assert claim is not None and str(claim.user_id) == user["id"]


async def test_is_me_on_an_existing_name_also_queues(client, db_sessionmaker):
    """Typing an existing author's name into the add form must not be a way
    around review — the get-or-create hit files a claim too."""
    first = (await client.post("/catalog/authors", json={"name": "K.R. Meera"})).json()
    second = (
        await client.post("/catalog/authors", json={"name": "k.r. meera", "is_me": True})
    ).json()

    assert second["id"] == first["id"]
    assert second["linked_user_id"] is None
    claim = await _claim_row(db_sessionmaker, first["id"])
    assert claim is not None


async def test_create_author_without_is_me_files_no_claim(client, db_sessionmaker):
    resp = await client.post("/catalog/authors", json={"name": "M.T. Vasudevan Nair"})

    assert resp.json()["linked_user_id"] is None
    assert resp.json()["claim_pending"] is False
    assert await _claim_row(db_sessionmaker, resp.json()["id"]) is None


async def test_claiming_twice_is_idempotent(client, db_sessionmaker):
    author = (await client.post("/catalog/authors", json={"name": "Sara Joseph"})).json()

    await client.post(f"/catalog/authors/{author['id']}/link")
    second = await client.post(f"/catalog/authors/{author['id']}/link")

    assert second.status_code == 200
    async with db_sessionmaker() as session:
        rows = (
            (
                await session.execute(
                    select(AuthorClaim).where(AuthorClaim.author_id == uuid.UUID(author["id"]))
                )
            )
            .scalars()
            .all()
        )
    assert len(rows) == 1, "re-tapping must not stack duplicate claims"


async def test_two_readers_may_both_claim_the_same_author(db_sessionmaker, user, user_b):
    """The case review exists to settle — both claims must be representable."""
    async with _client(db_sessionmaker, user) as one, _client(db_sessionmaker, user_b) as two:
        author = (await one.post("/catalog/authors", json={"name": "Contested Name"})).json()
        assert (await one.post(f"/catalog/authors/{author['id']}/link")).status_code == 200
        assert (await two.post(f"/catalog/authors/{author['id']}/link")).status_code == 200

    async with db_sessionmaker() as session:
        rows = (
            (
                await session.execute(
                    select(AuthorClaim).where(AuthorClaim.author_id == uuid.UUID(author["id"]))
                )
            )
            .scalars()
            .all()
        )
    assert len(rows) == 2


async def test_claiming_an_already_linked_author_is_conflict(client, db_sessionmaker):
    author = (await client.post("/catalog/authors", json={"name": "Already Linked"})).json()
    async with db_sessionmaker() as session:
        row = await session.get(Author, uuid.UUID(author["id"]))
        row.linked_user_id = uuid.uuid4()  # approved for somebody else
        await session.commit()

    resp = await client.post(f"/catalog/authors/{author['id']}/link")

    assert resp.status_code == 409
    # The structured-error handler flattens `detail` into the body (CLAUDE.md).
    assert resp.json()["code"] == "already_linked"


async def test_claiming_an_unknown_author_is_404(client):
    resp = await client.post(f"/catalog/authors/{uuid.uuid4()}/link")
    assert resp.status_code == 404


async def test_approval_is_what_links_the_author(client, db_sessionmaker, user):
    """Approval is manual for now (no endpoint) — this is the whole decision
    path a reviewer will call, so it is the part worth pinning down."""
    author = (await client.post("/catalog/authors", json={"name": "Verified Later"})).json()
    await client.post(f"/catalog/authors/{author['id']}/link")
    claim = await _claim_row(db_sessionmaker, author["id"])

    async with db_sessionmaker() as session:
        approved = await catalog_service.approve_claim(session, claim.id, uuid.UUID(user["id"]))
        assert approved.status == "approved"
        assert approved.decided_at is not None

    # Now — and only now — every reader sees the new value.
    after = (await client.get(f"/catalog/authors/{author['id']}")).json()["author"]
    assert after["linked_user_id"] == user["id"]
    # The claim is resolved, so it is no longer "pending" to its claimant.
    assert after["claim_pending"] is False


async def test_rejection_leaves_the_shared_row_alone(client, db_sessionmaker, user):
    author = (await client.post("/catalog/authors", json={"name": "Rejected Claim"})).json()
    await client.post(f"/catalog/authors/{author['id']}/link")
    claim = await _claim_row(db_sessionmaker, author["id"])

    async with db_sessionmaker() as session:
        rejected = await catalog_service.reject_claim(session, claim.id, uuid.UUID(user["id"]))
        assert rejected.status == "rejected"

    after = (await client.get(f"/catalog/authors/{author['id']}")).json()["author"]
    assert after["linked_user_id"] is None
    assert after["claim_pending"] is False


async def test_a_rejected_claim_is_not_silently_reopened(client, db_sessionmaker, user):
    """Tapping the button again after a rejection must not undo the decision."""
    author = (await client.post("/catalog/authors", json={"name": "Persistent"})).json()
    await client.post(f"/catalog/authors/{author['id']}/link")
    claim = await _claim_row(db_sessionmaker, author["id"])
    async with db_sessionmaker() as session:
        await catalog_service.reject_claim(session, claim.id, uuid.UUID(user["id"]))

    resp = await client.post(f"/catalog/authors/{author['id']}/link")

    assert resp.status_code == 200
    assert resp.json()["claim_pending"] is True, "the button still reports what it did"
    reloaded = await _claim_row(db_sessionmaker, author["id"])
    assert reloaded.status == "rejected", "the decision stands until a human revisits it"


async def test_approving_a_decided_claim_is_conflict(client, db_sessionmaker, user):
    author = (await client.post("/catalog/authors", json={"name": "Twice Decided"})).json()
    await client.post(f"/catalog/authors/{author['id']}/link")
    claim = await _claim_row(db_sessionmaker, author["id"])

    async with db_sessionmaker() as session:
        await catalog_service.approve_claim(session, claim.id, uuid.UUID(user["id"]))
    with pytest.raises(Exception) as excinfo:
        async with db_sessionmaker() as session:
            await catalog_service.approve_claim(session, claim.id, uuid.UUID(user["id"]))
    assert "already" in str(excinfo.value).lower()


async def test_approving_a_claim_on_a_since_linked_author_does_not_overwrite(
    client, db_sessionmaker, user, user_b
):
    """Two pending claims, one already approved: approving the loser must not
    quietly steal the author from the reader who was approved first."""
    author = (await client.post("/catalog/authors", json={"name": "Race Condition"})).json()
    await client.post(f"/catalog/authors/{author['id']}/link")
    claim = await _claim_row(db_sessionmaker, author["id"])
    async with db_sessionmaker() as session:
        row = await session.get(Author, uuid.UUID(author["id"]))
        row.linked_user_id = uuid.UUID(user_b["id"])  # decided elsewhere first
        await session.commit()

    with pytest.raises(Exception) as excinfo:
        async with db_sessionmaker() as session:
            await catalog_service.approve_claim(session, claim.id, uuid.UUID(user["id"]))

    assert "already" in str(excinfo.value).lower()
    async with db_sessionmaker() as session:
        row = await session.get(Author, uuid.UUID(author["id"]))
        assert str(row.linked_user_id) == user_b["id"]

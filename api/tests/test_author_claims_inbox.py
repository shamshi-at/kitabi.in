"""A reader can see their own "This is me" claims and take one back.

Filing a claim used to be a dead end: the button said "pending review", the
profile's Pending-edits inbox showed nothing (that lists work revisions, a
different feature), and there was no way back from a mis-tap — owner report,
23 Jul 2026.
"""

import uuid

import pytest
from sqlalchemy import select

from app.models import CLAIM_PENDING, AuthorClaim


async def _author(client, name: str = "Anuja Menon") -> dict:
    resp = await client.post("/catalog/authors", json={"name": name})
    assert resp.status_code == 201, resp.text
    return resp.json()


async def test_a_filed_claim_is_visible_to_its_claimant(client):
    author = await _author(client)
    await client.post(f"/catalog/authors/{author['id']}/link")

    body = (await client.get("/catalog/claims/mine")).json()

    assert len(body) == 1
    assert body[0]["author_id"] == author["id"]
    assert body[0]["author_name"] == "Anuja Menon"
    assert body[0]["status"] == CLAIM_PENDING


async def test_no_claims_is_an_empty_list_not_an_error(client):
    resp = await client.get("/catalog/claims/mine")
    assert resp.status_code == 200
    assert resp.json() == []


async def test_withdrawing_removes_the_claim_and_the_pending_badge(client, db_sessionmaker):
    author = await _author(client, "Kamala Das")
    claim = (await client.post(f"/catalog/authors/{author['id']}/link")).json()
    assert claim["claim_pending"] is True

    listed = (await client.get("/catalog/claims/mine")).json()
    resp = await client.delete(f"/catalog/claims/{listed[0]['id']}")

    assert resp.status_code == 204
    assert (await client.get("/catalog/claims/mine")).json() == []
    # The author no longer reports a pending claim to its would-be claimant.
    detail = (await client.get(f"/catalog/authors/{author['id']}")).json()["author"]
    assert detail["claim_pending"] is False
    async with db_sessionmaker() as session:
        rows = (await session.execute(select(AuthorClaim))).scalars().all()
        assert rows == []


async def test_withdrawing_frees_the_reader_to_claim_again(client):
    """A mis-tap must not bar them for good — the row is deleted, not marked,
    so the (author_id, user_id) unique pair is free again."""
    author = await _author(client, "M.T. Vasudevan Nair")
    await client.post(f"/catalog/authors/{author['id']}/link")
    listed = (await client.get("/catalog/claims/mine")).json()
    await client.delete(f"/catalog/claims/{listed[0]['id']}")

    again = await client.post(f"/catalog/authors/{author['id']}/link")

    assert again.status_code == 200
    assert len((await client.get("/catalog/claims/mine")).json()) == 1


async def test_cannot_withdraw_someone_elses_claim(client, db_sessionmaker, user_b):
    """Another reader's claim is reported missing, not forbidden — its
    existence isn't the caller's business."""
    author = await _author(client, "Basheer")
    async with db_sessionmaker() as session:
        other = AuthorClaim(author_id=uuid.UUID(author["id"]), user_id=uuid.UUID(user_b["id"]))
        session.add(other)
        await session.commit()
        await session.refresh(other)

    resp = await client.delete(f"/catalog/claims/{other.id}")

    assert resp.status_code == 404
    assert resp.json()["code"] == "not_found"
    async with db_sessionmaker() as session:
        assert (await session.get(AuthorClaim, other.id)) is not None


@pytest.mark.parametrize("decided", ["approved", "rejected"])
async def test_cannot_withdraw_a_decided_claim(client, db_sessionmaker, user, decided):
    """Otherwise a rejected claimant could erase the rejection and re-file —
    exactly what record_claim refuses to do by reopening."""
    author = await _author(client, f"Decided {decided}")
    async with db_sessionmaker() as session:
        claim = AuthorClaim(
            author_id=uuid.UUID(author["id"]),
            user_id=uuid.UUID(user["id"]),
            status=decided,
        )
        session.add(claim)
        await session.commit()
        await session.refresh(claim)

    resp = await client.delete(f"/catalog/claims/{claim.id}")

    assert resp.status_code == 409
    assert resp.json()["code"] == "already_decided"


async def test_claims_require_auth(unauthenticated_client):
    assert (await unauthenticated_client.get("/catalog/claims/mine")).status_code == 401
    assert (
        await unauthenticated_client.delete(f"/catalog/claims/{uuid.uuid4()}")
    ).status_code == 401

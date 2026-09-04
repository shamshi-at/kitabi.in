""""These are all the same book, listed several times."

A typo'd title arrives as three or four catalogue rows at once — "Dharmapuranam"
beside "Dharmapuranm" beside "Dharma Puranam" — and until now only the admin
console could fold them together. The reader holding the book is the one who can
tell, so the merge is theirs to make (owner request, 4 Sep 2026) — but only over
rows nobody has claimed, or rows they contributed themselves.
"""

import uuid

from sqlalchemy import select

from app.models import Edition, Rating, Work


async def _work(db, title, *, contributor=None):
    work = Work(title=title, created_by_user_id=contributor)
    db.add(work)
    await db.flush()
    return work


async def test_the_duplicates_fold_into_the_one_being_kept(client, db_sessionmaker, user):
    async with db_sessionmaker() as db:
        keep = await _work(db, "Dharmapuranam")
        a = await _work(db, "Dharmapuranm")
        b = await _work(db, "Dharma Puranam")
        db.add(Edition(work_id=a.id, isbn="9788171300662", page_count=255))
        await db.commit()
        keep_id, a_id, b_id = str(keep.id), str(a.id), str(b.id)

    resp = await client.post(
        f"/catalog/works/{keep_id}/merge",
        json={"absorb_ids": [a_id, b_id]},
    )

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["work"]["id"] == keep_id
    assert {m["title"] for m in body["merged"]} == {"Dharmapuranm", "Dharma Puranam"}
    # The edition that hung off a duplicate is now the survivor's — that is the
    # whole point, and it is what the reader's library entries ride on.
    assert [e["isbn"] for e in body["work"]["editions"]] == ["9788171300662"]

    async with db_sessionmaker() as db:
        gone = (await db.execute(select(Work).where(Work.id == uuid.UUID(a_id)))).scalar_one()
        # Soft-deleted (rule 3), never destroyed: a mistaken merge is a
        # correction, not an excavation.
        assert gone.deleted_at is not None


async def test_another_readers_book_is_not_ours_to_merge_away(client, db_sessionmaker):
    async with db_sessionmaker() as db:
        keep = await _work(db, "Dharmapuranam")
        theirs = await _work(db, "Dharmapuranm", contributor=uuid.uuid4())
        await db.commit()
        keep_id, theirs_id = str(keep.id), str(theirs.id)

    resp = await client.post(f"/catalog/works/{keep_id}/merge", json={"absorb_ids": [theirs_id]})

    assert resp.status_code == 403
    assert resp.json()["code"] == "not_yours_to_merge"
    assert "Dharmapuranm" in resp.json()["message"]


async def test_a_reader_may_merge_away_a_book_they_contributed(client, db_sessionmaker, user):
    async with db_sessionmaker() as db:
        keep = await _work(db, "Dharmapuranam")
        mine = await _work(db, "Dharmapuranm", contributor=uuid.UUID(user["id"]))
        await db.commit()
        keep_id, mine_id = str(keep.id), str(mine.id)

    resp = await client.post(f"/catalog/works/{keep_id}/merge", json={"absorb_ids": [mine_id]})
    assert resp.status_code == 200, resp.text


async def test_one_refusal_stops_the_whole_merge(client, db_sessionmaker):
    """Every id is checked before the first row moves. A refusal found halfway
    would leave some duplicates folded and the rest still listed — a state
    nobody asked for and nobody can see from the outside."""
    async with db_sessionmaker() as db:
        keep = await _work(db, "Dharmapuranam")
        ok = await _work(db, "Dharmapuranm")
        theirs = await _work(db, "Dharma Puranam", contributor=uuid.uuid4())
        await db.commit()
        keep_id, ok_id, theirs_id = str(keep.id), str(ok.id), str(theirs.id)

    resp = await client.post(
        f"/catalog/works/{keep_id}/merge", json={"absorb_ids": [ok_id, theirs_id]}
    )
    assert resp.status_code == 403

    async with db_sessionmaker() as db:
        untouched = (await db.execute(select(Work).where(Work.id == uuid.UUID(ok_id)))).scalar_one()
        assert untouched.deleted_at is None


async def test_a_work_cannot_be_merged_into_itself(client, db_sessionmaker):
    async with db_sessionmaker() as db:
        keep = await _work(db, "Dharmapuranam")
        await db.commit()
        keep_id = str(keep.id)

    resp = await client.post(f"/catalog/works/{keep_id}/merge", json={"absorb_ids": [keep_id]})
    assert resp.status_code == 400
    assert resp.json()["code"] == "same_work"


async def test_ratings_on_a_duplicate_survive_the_merge(client, db_sessionmaker):
    """The dangerous part: a merge moves *other readers'* data."""
    other = uuid.uuid4()
    async with db_sessionmaker() as db:
        keep = await _work(db, "Dharmapuranam")
        dupe = await _work(db, "Dharmapuranm")
        db.add(Rating(user_id=other, work_id=dupe.id, value=5))
        await db.commit()
        keep_id, dupe_id = str(keep.id), str(dupe.id)

    resp = await client.post(f"/catalog/works/{keep_id}/merge", json={"absorb_ids": [dupe_id]})
    assert resp.status_code == 200, resp.text

    async with db_sessionmaker() as db:
        rating = (await db.execute(select(Rating).where(Rating.user_id == other))).scalar_one()
        assert str(rating.work_id) == keep_id


async def test_the_absorb_list_is_capped(client, db_sessionmaker):
    async with db_sessionmaker() as db:
        keep = await _work(db, "Dharmapuranam")
        await db.commit()
        keep_id = str(keep.id)

    resp = await client.post(
        f"/catalog/works/{keep_id}/merge",
        json={"absorb_ids": [str(uuid.uuid4()) for _ in range(11)]},
    )
    assert resp.status_code == 422

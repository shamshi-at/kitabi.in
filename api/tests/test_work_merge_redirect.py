"""A merged book's URL moves to the survivor instead of dying.

Authors, publishers and series have carried `merged_into_id` since the console's
dedupe; Works never did, because only an admin could merge one. Readers can now,
and a book page is the one page on this site that actually earns inbound links —
so a merge that leaves the old URL 404ing discards exactly the ranking it was
supposed to consolidate (owner request, 4 Sep 2026).
"""

import uuid

from sqlalchemy import select

from app.models import Work
from app.services import catalog_service


async def _work(db, title, *, slug=None):
    work = Work(title=title, slug=slug)
    db.add(work)
    await db.flush()
    return work


async def test_a_merged_work_points_at_the_survivor(client, db_sessionmaker):
    async with db_sessionmaker() as db:
        keep = await _work(db, "Dharmapuranam", slug="dharmapuranam")
        dupe = await _work(db, "Dharmapuranm", slug="dharmapuranm")
        await db.commit()
        keep_id, dupe_id = str(keep.id), str(dupe.id)

    resp = await client.post(f"/catalog/works/{keep_id}/merge", json={"absorb_ids": [dupe_id]})
    assert resp.status_code == 200, resp.text

    async with db_sessionmaker() as db:
        absorbed = (
            await db.execute(select(Work).where(Work.id == uuid.UUID(dupe_id)))
        ).scalar_one()
        assert str(absorbed.merged_into_id) == keep_id
        # Soft-deleted *and* pointed: the delete is what hides it, the pointer
        # is what keeps its URL alive.
        assert absorbed.deleted_at is not None


async def test_the_old_url_resolves_to_the_survivors_slug(client, db_sessionmaker):
    """What the edge asks for on a 404, so it can 301."""
    async with db_sessionmaker() as db:
        keep = await _work(db, "Dharmapuranam", slug="dharmapuranam")
        dupe = await _work(db, "Dharmapuranm", slug="dharmapuranm")
        await db.commit()
        keep_id, dupe_id = str(keep.id), str(dupe.id)

    await client.post(f"/catalog/works/{keep_id}/merge", json={"absorb_ids": [dupe_id]})

    by_slug = await client.get("/public/merged/book/dharmapuranm")
    assert by_slug.status_code == 200
    assert by_slug.json()["slug"] == "dharmapuranam"

    # The UUID form too — every /b/<uuid> share link ever generated uses it.
    by_id = await client.get(f"/public/merged/book/{dupe_id}")
    assert by_id.status_code == 200
    assert by_id.json()["slug"] == "dharmapuranam"


async def test_a_live_book_is_not_a_redirect(client, db_sessionmaker):
    async with db_sessionmaker() as db:
        await _work(db, "Chemmeen", slug="chemmeen")
        await db.commit()

    assert (await client.get("/public/merged/book/chemmeen")).status_code == 404


async def test_an_app_link_to_a_merged_book_opens_the_survivor(client, db_sessionmaker):
    """`/public/id/book/...` is how the app turns a kitabi.in link into a screen.
    It excluded books from merge-following, because Works had no pointer."""
    async with db_sessionmaker() as db:
        keep = await _work(db, "Dharmapuranam", slug="dharmapuranam")
        dupe = await _work(db, "Dharmapuranm", slug="dharmapuranm")
        await db.commit()
        keep_id, dupe_id = str(keep.id), str(dupe.id)

    await client.post(f"/catalog/works/{keep_id}/merge", json={"absorb_ids": [dupe_id]})

    resp = await client.get("/public/id/book/dharmapuranm")
    assert resp.status_code == 200, resp.text
    assert resp.json()["id"] == keep_id


async def test_merging_a_book_others_were_merged_into_keeps_the_graph_flat(client, db_sessionmaker):
    """Resolution does a single hop, so a chain silently 404s at its far end —
    the exact failure the pointer exists to prevent."""
    async with db_sessionmaker() as db:
        first = await _work(db, "Dharmapuranam", slug="dharmapuranam")
        middle = await _work(db, "Dharma Puranam", slug="dharma-puranam")
        far = await _work(db, "Dharmapuranm", slug="dharmapuranm")
        await db.commit()
        first_id, middle_id, far_id = str(first.id), str(middle.id), str(far.id)

    # far -> middle, then middle -> first.
    r1 = await client.post(f"/catalog/works/{middle_id}/merge", json={"absorb_ids": [far_id]})
    assert r1.status_code == 200, r1.text
    r2 = await client.post(f"/catalog/works/{first_id}/merge", json={"absorb_ids": [middle_id]})
    assert r2.status_code == 200, r2.text

    async with db_sessionmaker() as db:
        rows = {
            str(w.id): w.merged_into_id for w in (await db.execute(select(Work))).scalars().all()
        }
    # Both point *directly* at the survivor — no hop through the middle row.
    assert str(rows[far_id]) == first_id
    assert str(rows[middle_id]) == first_id

    # And the far end still resolves, which is the whole point.
    resp = await client.get("/public/merged/book/dharmapuranm")
    assert resp.status_code == 200
    assert resp.json()["slug"] == "dharmapuranam"


async def test_clearing_the_column_undoes_the_merge(db_sessionmaker):
    """The pointer is reversible by design — a mistaken merge is a correction,
    not an excavation."""
    async with db_sessionmaker() as db:
        keep = await _work(db, "Dharmapuranam")
        dupe = await _work(db, "Dharmapuranm")
        await db.commit()
        await catalog_service.merge_works(db, keep.id, dupe.id)

    async with db_sessionmaker() as db:
        absorbed = (await db.execute(select(Work).where(Work.id == dupe.id))).scalar_one()
        assert absorbed.merged_into_id == keep.id
        absorbed.merged_into_id = None
        absorbed.deleted_at = None
        await db.commit()

    async with db_sessionmaker() as db:
        back = (await db.execute(select(Work).where(Work.id == dupe.id))).scalar_one()
        assert back.merged_into_id is None
        assert back.deleted_at is None

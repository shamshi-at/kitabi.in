"""Merging one Work into another — the admin console's duplicate fix.

The dangerous part is that it moves *other readers'* data (ratings, reviews)
and the editions their library entries hang off, so these tests assert nothing
is lost and the absorbed work is soft-deleted, not destroyed.
"""

import uuid

from sqlalchemy import select

from app.models import (
    Author,
    Edition,
    LibraryEntry,
    Rating,
    Review,
    Work,
    work_authors,
)
from app.services import catalog_service


async def _work(db, title: str) -> Work:
    w = Work(title=title)
    db.add(w)
    await db.flush()
    return w


async def test_merge_moves_editions_ratings_reviews_and_soft_deletes(db_sessionmaker):
    async with db_sessionmaker() as db:
        keep = await _work(db, "ചെമ്മീൻ")
        absorb = await _work(db, "Chemeen")  # the duplicate
        author = Author(name="Thakazhi")
        db.add(author)
        await db.flush()
        await db.execute(work_authors.insert().values(work_id=absorb.id, author_id=author.id))
        ed = Edition(work_id=absorb.id, isbn="9990001112223")
        db.add(ed)
        await db.flush()
        reader = uuid.uuid4()
        db.add(LibraryEntry(id=uuid.uuid4(), user_id=reader, edition_id=ed.id, status="read"))
        db.add(Rating(id=uuid.uuid4(), user_id=reader, work_id=absorb.id, value=5))
        db.add(
            Review(
                id=uuid.uuid4(), user_id=reader, work_id=absorb.id, body="Wonderful", visible=True
            )
        )
        await db.commit()
        keep_id, absorb_id, ed_id = keep.id, absorb.id, ed.id

    async with db_sessionmaker() as db:
        preview = await catalog_service.merge_preview(db, keep_id, absorb_id)
        assert preview["editions"] == 1
        assert preview["ratings"] == 1
        assert preview["reviews"] == 1
        assert preview["library_entries"] == 1

    async with db_sessionmaker() as db:
        await catalog_service.merge_works(db, keep_id, absorb_id)

    async with db_sessionmaker() as db:
        # Everything now hangs off the kept work.
        assert (await db.get(Edition, ed_id)).work_id == keep_id
        assert (await db.scalar(select(Rating.work_id).where(Rating.work_id == keep_id))) == keep_id
        assert (await db.scalar(select(Review.work_id).where(Review.work_id == keep_id))) == keep_id
        wa = (
            (
                await db.execute(
                    select(work_authors.c.author_id).where(work_authors.c.work_id == keep_id)
                )
            )
            .scalars()
            .all()
        )
        assert len(wa) == 1
        # The library entry followed its edition — not lost.
        entry = (
            await db.execute(select(LibraryEntry).where(LibraryEntry.edition_id == ed_id))
        ).scalar_one()
        assert entry.status == "read"
        # The absorbed work is soft-deleted, never destroyed.
        absorbed = await db.get(Work, absorb_id)
        assert absorbed.deleted_at is not None


async def test_merge_moved_ratings_get_a_fresh_server_seq(db_sessionmaker):
    """Layer-2 rows must re-sync after a merge, or the reader's device keeps
    the rating pointed at the now-deleted work."""
    async with db_sessionmaker() as db:
        keep = await _work(db, "Keep")
        absorb = await _work(db, "Absorb")
        r = Rating(id=uuid.uuid4(), user_id=uuid.uuid4(), work_id=absorb.id, value=4)
        db.add(r)
        await db.commit()
        keep_id, absorb_id, rid = keep.id, absorb.id, r.id
        before = r.server_seq

    async with db_sessionmaker() as db:
        await catalog_service.merge_works(db, keep_id, absorb_id)

    async with db_sessionmaker() as db:
        moved = await db.get(Rating, rid)
        assert moved.work_id == keep_id
        assert moved.server_seq > before


async def test_merge_refuses_self_and_missing(db_sessionmaker):
    async with db_sessionmaker() as db:
        w = await _work(db, "Only one")
        await db.commit()
        wid = w.id

    async with db_sessionmaker() as db:
        for keep, absorb, code in [(wid, wid, 400), (wid, uuid.uuid4(), 404)]:
            try:
                await catalog_service.merge_works(db, keep, absorb)
                raise AssertionError("expected failure")
            except Exception as exc:  # noqa: BLE001
                assert getattr(exc, "status_code", None) == code

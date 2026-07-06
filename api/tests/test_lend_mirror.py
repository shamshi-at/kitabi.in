"""Server-side mirroring of an outgoing loan onto the borrower's account."""

import uuid
from datetime import date

from sqlalchemy import select

from app.models import LendingRecord, LibraryEntry
from app.models.connection import Connection
from app.models.edition import Edition
from app.models.profile import Profile
from app.models.work import Work
from app.services import lend_mirror_service


async def _seed_lend(db, lender, borrower, *, connected: bool):
    db.add(Profile(id=lender, email="l@x.com", username="lender", full_name="Lena Lender"))
    db.add(Profile(id=borrower, email="b@x.com", username="borrower"))
    if connected:
        db.add(Connection(requester_id=lender, addressee_id=borrower, status="accepted"))
    work = Work(title="The Loaned Book")
    db.add(work)
    await db.flush()
    edition = Edition(work_id=work.id)
    db.add(edition)
    await db.flush()
    entry = LibraryEntry(user_id=lender, edition_id=edition.id)
    db.add(entry)
    await db.flush()
    rec = LendingRecord(
        user_id=lender,
        direction="lent",
        library_entry_id=entry.id,
        borrower_name="Bob",
        borrower_user_id=borrower,
        lent_date=date(2026, 7, 1),
    )
    db.add(rec)
    await db.flush()
    await db.commit()
    return rec.id, edition.id


async def _borrowed(db, borrower):
    rows = (
        (await db.execute(select(LendingRecord).where(LendingRecord.user_id == borrower)))
        .scalars()
        .all()
    )
    return rows


async def test_mirror_creates_borrowed_record(db_sessionmaker, user, user_b):
    lender, borrower = uuid.UUID(user["id"]), uuid.UUID(user_b["id"])
    async with db_sessionmaker() as db:
        rec_id, edition_id = await _seed_lend(db, lender, borrower, connected=True)
    async with db_sessionmaker() as db:
        await lend_mirror_service.mirror_lending(db, lender, rec_id)
    async with db_sessionmaker() as db:
        rows = await _borrowed(db, borrower)
    assert len(rows) == 1
    m = rows[0]
    assert m.direction == "borrowed"
    assert m.edition_id == edition_id
    assert m.borrower_user_id == lender  # a borrowed row points back at the lender
    assert m.borrower_name == "Lena Lender"
    assert m.linked_loan_id == rec_id


async def test_no_mirror_without_accepted_connection(db_sessionmaker, user, user_b):
    lender, borrower = uuid.UUID(user["id"]), uuid.UUID(user_b["id"])
    async with db_sessionmaker() as db:
        rec_id, _ = await _seed_lend(db, lender, borrower, connected=False)
    async with db_sessionmaker() as db:
        await lend_mirror_service.mirror_lending(db, lender, rec_id)
    async with db_sessionmaker() as db:
        assert await _borrowed(db, borrower) == []


async def test_mirror_is_idempotent_and_tracks_return(db_sessionmaker, user, user_b):
    lender, borrower = uuid.UUID(user["id"]), uuid.UUID(user_b["id"])
    async with db_sessionmaker() as db:
        rec_id, _ = await _seed_lend(db, lender, borrower, connected=True)
    async with db_sessionmaker() as db:
        await lend_mirror_service.mirror_lending(db, lender, rec_id)
        await lend_mirror_service.mirror_lending(db, lender, rec_id)  # again → no dupe
    # Lender marks it returned; mirror should reflect it.
    async with db_sessionmaker() as db:
        lent = await db.get(LendingRecord, rec_id)
        lent.returned_date = date(2026, 7, 20)
        await db.commit()
    async with db_sessionmaker() as db:
        await lend_mirror_service.mirror_lending(db, lender, rec_id)
    async with db_sessionmaker() as db:
        rows = await _borrowed(db, borrower)
    assert len(rows) == 1
    assert rows[0].returned_date == date(2026, 7, 20)

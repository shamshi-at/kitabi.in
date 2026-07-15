"""Server-side mirroring of an outgoing loan onto the borrower's account."""

import uuid
from datetime import UTC, date, datetime

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


async def test_mirror_creates_a_library_entry_for_the_borrower(db_sessionmaker, user, user_b):
    """Owner request, 15 Jul 2026: an auto-mirrored loan must unify the same
    way a self-logged borrow does — a real ownership='borrowed' LibraryEntry
    on the borrower's account, linked back from the mirror record — so a
    lend from a connected friend reads/tracks/stays-on-the-shelf identically
    to logging a borrow by hand."""
    lender, borrower = uuid.UUID(user["id"]), uuid.UUID(user_b["id"])
    async with db_sessionmaker() as db:
        rec_id, edition_id = await _seed_lend(db, lender, borrower, connected=True)
    async with db_sessionmaker() as db:
        await lend_mirror_service.mirror_lending(db, lender, rec_id)
    async with db_sessionmaker() as db:
        mirror = (await _borrowed(db, borrower))[0]
        assert mirror.library_entry_id is not None
        entry = await db.get(LibraryEntry, mirror.library_entry_id)
        assert entry is not None
        assert entry.user_id == borrower
        assert entry.edition_id == edition_id
        assert entry.ownership == "borrowed"
        assert entry.deleted_at is None


async def test_no_mirror_without_accepted_connection(db_sessionmaker, user, user_b):
    lender, borrower = uuid.UUID(user["id"]), uuid.UUID(user_b["id"])
    async with db_sessionmaker() as db:
        rec_id, _ = await _seed_lend(db, lender, borrower, connected=False)
    async with db_sessionmaker() as db:
        await lend_mirror_service.mirror_lending(db, lender, rec_id)
    async with db_sessionmaker() as db:
        assert await _borrowed(db, borrower) == []


async def test_borrower_return_reflects_onto_lender(db_sessionmaker, user, user_b):
    """The other direction: the borrower marks the book returned on their
    mirror — the lender's original record picks up the return (with a seq bump
    so it re-pulls) and stays theirs otherwise."""
    lender, borrower = uuid.UUID(user["id"]), uuid.UUID(user_b["id"])
    async with db_sessionmaker() as db:
        rec_id, _ = await _seed_lend(db, lender, borrower, connected=True)
    async with db_sessionmaker() as db:
        await lend_mirror_service.mirror_lending(db, lender, rec_id)
    async with db_sessionmaker() as db:
        lent_seq_before = (await db.get(LendingRecord, rec_id)).server_seq
        mirror = (await _borrowed(db, borrower))[0]
        mirror.returned_date = date(2026, 7, 21)  # what the borrower's push op applies
        await db.commit()
        mirror_id = mirror.id
    async with db_sessionmaker() as db:
        await lend_mirror_service.mirror_lending(db, borrower, mirror_id)
    async with db_sessionmaker() as db:
        lent = await db.get(LendingRecord, rec_id)
    assert lent.returned_date == date(2026, 7, 21)
    assert lent.server_seq > lent_seq_before  # re-pulls to the lender's devices


async def test_reflection_ignores_spoofed_link(db_sessionmaker, user, user_b):
    """linked_loan_id arrives in client payloads — a borrowed row whose target
    loan doesn't name this user as its borrower must never mutate it."""
    lender, borrower = uuid.UUID(user["id"]), uuid.UUID(user_b["id"])
    async with db_sessionmaker() as db:
        rec_id, edition_id = await _seed_lend(db, lender, borrower, connected=True)
        # A crafted borrowed row from someone the loan doesn't point at.
        intruder = uuid.uuid4()
        db.add(Profile(id=intruder, email="i@x.com", username="intruder"))
        fake = LendingRecord(
            user_id=intruder,
            direction="borrowed",
            edition_id=edition_id,
            borrower_name="Lena Lender",
            linked_loan_id=rec_id,
            lent_date=date(2026, 7, 1),
            returned_date=date(2026, 7, 2),
        )
        db.add(fake)
        await db.flush()
        fake_id = fake.id
        await db.commit()
    async with db_sessionmaker() as db:
        await lend_mirror_service.mirror_lending(db, intruder, fake_id)
    async with db_sessionmaker() as db:
        lent = await db.get(LendingRecord, rec_id)
    assert lent.returned_date is None  # untouched


async def test_existing_mirror_updates_survive_disconnect(db_sessionmaker, user, user_b):
    """The connection gates *creating* a mirror, not keeping an existing pair
    in step — a return marked after the readers disconnect must still flow."""
    lender, borrower = uuid.UUID(user["id"]), uuid.UUID(user_b["id"])
    async with db_sessionmaker() as db:
        rec_id, _ = await _seed_lend(db, lender, borrower, connected=True)
    async with db_sessionmaker() as db:
        await lend_mirror_service.mirror_lending(db, lender, rec_id)
    async with db_sessionmaker() as db:
        conn = (await db.execute(select(Connection))).scalars().first()
        conn.status = "denied"
        lent = await db.get(LendingRecord, rec_id)
        lent.returned_date = date(2026, 7, 22)
        await db.commit()
    async with db_sessionmaker() as db:
        await lend_mirror_service.mirror_lending(db, lender, rec_id)
    async with db_sessionmaker() as db:
        rows = await _borrowed(db, borrower)
    assert rows[0].returned_date == date(2026, 7, 22)


async def test_no_born_deleted_mirror(db_sessionmaker, user, user_b):
    """A loan already soft-deleted when it first reaches the mirror step has
    nothing to show the borrower — no ghost row is created."""
    lender, borrower = uuid.UUID(user["id"]), uuid.UUID(user_b["id"])
    async with db_sessionmaker() as db:
        rec_id, _ = await _seed_lend(db, lender, borrower, connected=True)
        lent = await db.get(LendingRecord, rec_id)
        lent.deleted_at = datetime.now(UTC)
        await db.commit()
    async with db_sessionmaker() as db:
        await lend_mirror_service.mirror_lending(db, lender, rec_id)
    async with db_sessionmaker() as db:
        assert await _borrowed(db, borrower) == []


async def test_unlinking_a_loan_retires_the_mirror(db_sessionmaker, user, user_b):
    """Re-pointing a loan at a private contact clears borrower_user_id — the
    mirror it once fanned out must soft-delete (with a seq bump) or the former
    borrower's shelf shows a frozen "with you" row forever."""
    lender, borrower = uuid.UUID(user["id"]), uuid.UUID(user_b["id"])
    async with db_sessionmaker() as db:
        rec_id, _ = await _seed_lend(db, lender, borrower, connected=True)
    async with db_sessionmaker() as db:
        await lend_mirror_service.mirror_lending(db, lender, rec_id)
    async with db_sessionmaker() as db:
        mirror_seq_before = (await _borrowed(db, borrower))[0].server_seq
        lent = await db.get(LendingRecord, rec_id)
        lent.borrower_user_id = None  # what updateBorrower(null) applies
        lent.borrower_name = "Bob (private)"
        await db.commit()
    async with db_sessionmaker() as db:
        await lend_mirror_service.mirror_lending(db, lender, rec_id)
    async with db_sessionmaker() as db:
        rows = await _borrowed(db, borrower)
    assert len(rows) == 1
    assert rows[0].deleted_at is not None
    assert rows[0].server_seq > mirror_seq_before  # the removal re-pulls


async def test_duplicate_mirror_insert_hits_db_constraint(db_sessionmaker, user, user_b):
    """uq_lending_mirror_pair: the database refuses a second mirror for the same
    (borrower, source loan) even if the app-level existence check races."""
    lender, borrower = uuid.UUID(user["id"]), uuid.UUID(user_b["id"])
    async with db_sessionmaker() as db:
        rec_id, edition_id = await _seed_lend(db, lender, borrower, connected=True)
    async with db_sessionmaker() as db:
        await lend_mirror_service.mirror_lending(db, lender, rec_id)
    import pytest
    from sqlalchemy.exc import IntegrityError

    async with db_sessionmaker() as db:
        db.add(
            LendingRecord(
                user_id=borrower,
                direction="borrowed",
                edition_id=edition_id,
                borrower_name="Lena Lender",
                linked_loan_id=rec_id,
                lent_date=date(2026, 7, 1),
            )
        )
        with pytest.raises(IntegrityError):
            await db.flush()


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

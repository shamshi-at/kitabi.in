"""Keep the two sides of a linked loan in step.

When a reader lends a book to a *linked, accepted* Kitabi user, the counterparty
should see it on their Borrowed shelf without doing anything — the [V1] "lending
record that appears on their account automatically" (feature-map.md). This
service creates/keeps-in-step a mirror `direction='borrowed'` record on the
borrower's account (correlated by `linked_loan_id`), which then pulls to their
device via the normal sync cursor. It also runs the other way: a borrower
marking the book returned reflects onto the lender's original record.

Runs AFTER the pusher's own sync op has committed (see sync_service.apply_ops),
and commits on its own — so a failure here can never reject the pusher's op.
"""

import uuid
from datetime import UTC, datetime

from sqlalchemy import and_, or_, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Edition, LendingRecord, LibraryEntry, Work
from app.models.profile import Profile
from app.services import connection_service, push_service


def _display_name(p: Profile | None) -> str:
    if p is None:
        return "A Kitabi reader"
    if p.full_name and p.full_name.strip():
        return p.full_name.strip()
    if p.username:
        return f"@{p.username}"
    return "A Kitabi reader"


async def mirror_lending(db: AsyncSession, user_id: uuid.UUID, record_id: uuid.UUID) -> None:
    """Fan an applied lending op out to the counterparty. `user_id` is whoever
    pushed the op — the lender for a `lent` record, the borrower for a
    `borrowed` mirror."""
    record = await db.get(LendingRecord, record_id)
    if record is None:
        return
    if record.direction == "lent":
        await _mirror_onto_borrower(db, user_id, record)
    elif record.direction == "borrowed" and record.linked_loan_id is not None:
        await _reflect_onto_lender(db, user_id, record)


async def _resolve_edition_id(db: AsyncSession, record: LendingRecord) -> uuid.UUID | None:
    """A lent record hangs off the lender's library entry; resolve the edition
    so both sides of the pair point at the same catalog book."""
    if record.edition_id is not None:
        return record.edition_id
    if record.library_entry_id is not None:
        entry = await db.get(LibraryEntry, record.library_entry_id)
        return entry.edition_id if entry else None
    return None


async def _mirror_onto_borrower(
    db: AsyncSession, lender_id: uuid.UUID, lent: LendingRecord
) -> None:
    if lent.borrower_user_id is None:
        # The loan no longer names a Kitabi borrower (unlinked to a private
        # contact) — retire any mirror it once fanned out, or the borrower's
        # shelf shows a frozen "with you" row forever.
        await _retire_orphaned_mirror(db, lent)
        return
    borrower_id = lent.borrower_user_id

    edition_id = await _resolve_edition_id(db, lent)
    if edition_id is None:
        return

    mirror = (
        await db.execute(
            select(LendingRecord).where(
                LendingRecord.user_id == borrower_id,
                LendingRecord.linked_loan_id == lent.id,
            )
        )
    ).scalar_one_or_none()

    lender_name = _display_name(await db.get(Profile, lender_id))

    # What happened, so we can push the borrower the right notification below.
    is_new = mirror is None
    just_returned = False

    if mirror is None:
        # Creating a brand-new mirror is gated on an accepted connection — loans
        # only fan out between linked readers. Keeping an existing pair in step
        # deliberately is NOT: once a loan has mirrored, returns/edits/deletes
        # must keep flowing even if the connection is later dropped, or the two
        # ledgers silently diverge forever.
        if not await connection_service.are_connected(db, lender_id, borrower_id):
            return
        # A loan deleted before it ever mirrored has nothing to show the
        # borrower — don't create a born-deleted ghost row.
        if lent.deleted_at is not None:
            return
        # The borrower gets a real LibraryEntry too (owner request, 15 Jul
        # 2026) — same unification as a self-logged borrow, so an
        # auto-mirrored loan reads/tracks/stays-on-the-shelf identically.
        # Reuses an existing entry for this edition if the borrower already
        # has one (owned, or borrowed-and-returned before) rather than
        # forking a second row for the same book — same rule the app's own
        # logBorrowed applies. A fresh INSERT still gets server_seq from the
        # column's server_default (only UPDATEs need the explicit nextval
        # bump).
        borrowed_entry = (
            await db.execute(
                select(LibraryEntry).where(
                    LibraryEntry.user_id == borrower_id,
                    LibraryEntry.edition_id == edition_id,
                    LibraryEntry.deleted_at.is_(None),
                )
            )
        ).scalar_one_or_none()
        if borrowed_entry is None:
            borrowed_entry = LibraryEntry(
                id=uuid.uuid4(),
                user_id=borrower_id,
                edition_id=edition_id,
                status="pending",
                ownership="borrowed",
            )
            db.add(borrowed_entry)
            await db.flush()
        mirror = LendingRecord(
            id=uuid.uuid4(),
            user_id=borrower_id,
            direction="borrowed",
            library_entry_id=borrowed_entry.id,
            edition_id=edition_id,
            borrower_name=lender_name,  # for a borrowed row, this is the lender
            borrower_user_id=lender_id,
            linked_loan_id=lent.id,
            lent_date=lent.lent_date,
            due_date=lent.due_date,
            returned_date=lent.returned_date,
            deleted_at=lent.deleted_at,
        )
        db.add(mirror)
        try:
            await db.flush()
        except IntegrityError:
            # uq_lending_mirror_pair: a concurrent push already created the
            # mirror. Retry once from the top — it takes the update path now.
            await db.rollback()
            fresh = await db.get(LendingRecord, lent.id)
            if fresh is not None:
                await _mirror_onto_borrower(db, lender_id, fresh)
            return
        await db.refresh(mirror, ["server_seq"])
    else:
        # Keep the mirror in step — returns, due-date edits, un/deletes.
        just_returned = mirror.returned_date is None and lent.returned_date is not None
        mirror.lent_date = lent.lent_date
        mirror.due_date = lent.due_date
        mirror.returned_date = lent.returned_date
        mirror.borrower_name = lender_name
        mirror.deleted_at = lent.deleted_at
        # server_default nextval only fires on INSERT — bump explicitly so the
        # update re-pulls to the borrower (CLAUDE.md sync lesson).
        mirror.server_seq = text("nextval('sync_seq')")
        await db.flush()

    await db.commit()

    # Push the borrower about a new loan / its return (best-effort, off the
    # committed transaction). Skip deleted loans.
    if lent.deleted_at is None:
        book_title, book_cover = await _book_title_cover(db, edition_id)
        if is_new:
            await push_service.notify_book_lent(lender_id, borrower_id, book_title, book_cover)
        elif just_returned:
            await push_service.notify_book_returned(lender_id, borrower_id, book_title, book_cover)


async def backfill_mirrors(db: AsyncSession, a: uuid.UUID, b: uuid.UUID) -> None:
    """Fan out every loan that predates the pair's connection.

    A loan lent to a not-yet-connected Kitabi user never mirrors (creation is
    gated on an accepted connection), and nothing used to retry — so the
    borrower approved the request and still saw an empty Borrowed shelf.
    Called right after a connection between [a] and [b] lands on accepted;
    `_mirror_onto_borrower` dedupes, so this is idempotent."""
    stmt = select(LendingRecord).where(
        LendingRecord.direction == "lent",
        LendingRecord.deleted_at.is_(None),
        or_(
            and_(LendingRecord.user_id == a, LendingRecord.borrower_user_id == b),
            and_(LendingRecord.user_id == b, LendingRecord.borrower_user_id == a),
        ),
    )
    for lent in (await db.execute(stmt)).scalars().all():
        await _mirror_onto_borrower(db, lent.user_id, lent)


async def _retire_orphaned_mirror(db: AsyncSession, lent: LendingRecord) -> None:
    """Soft-delete the mirror of a loan whose Kitabi link was cleared
    (`updateBorrower(borrowerUserId: null)`), with a seq bump so the removal
    pulls to the former borrower's device."""
    mirror = (
        await db.execute(select(LendingRecord).where(LendingRecord.linked_loan_id == lent.id))
    ).scalar_one_or_none()
    if mirror is None or mirror.deleted_at is not None:
        return
    mirror.deleted_at = datetime.now(UTC)
    mirror.server_seq = text("nextval('sync_seq')")
    await db.flush()
    await db.commit()


async def _reflect_onto_lender(
    db: AsyncSession, borrower_id: uuid.UUID, borrowed: LendingRecord
) -> None:
    """The borrower's side of a linked pair changed — reflect the return onto
    the lender's original record so *either* party closing the loop updates
    both ledgers. Only `returned_date` flows back: the lent row is the lender's
    own ledger entry, so a borrower deleting their mirror doesn't touch it."""
    lent = await db.get(LendingRecord, borrowed.linked_loan_id)
    # The pair must genuinely point at each other — `linked_loan_id` arrives in
    # client payloads, so without the borrower check anyone could craft a
    # borrowed row against a stranger's loan and mutate it.
    if lent is None or lent.direction != "lent" or lent.borrower_user_id != borrower_id:
        return
    if lent.returned_date == borrowed.returned_date:
        return  # already in step (e.g. the lender's own change round-tripping)

    just_returned = lent.returned_date is None and borrowed.returned_date is not None
    lent.returned_date = borrowed.returned_date
    # server_default nextval only fires on INSERT — bump explicitly so the
    # change re-pulls to the lender (CLAUDE.md sync lesson).
    lent.server_seq = text("nextval('sync_seq')")
    await db.flush()
    await db.commit()

    if just_returned and lent.deleted_at is None:
        edition_id = await _resolve_edition_id(db, lent)
        if edition_id is not None:
            book_title, book_cover = await _book_title_cover(db, edition_id)
        else:
            book_title, book_cover = "a book", None
        await push_service.notify_book_returned(borrower_id, lent.user_id, book_title, book_cover)


async def _book_title_cover(db: AsyncSession, edition_id: uuid.UUID) -> tuple[str, str | None]:
    """The Work title (for the message) and the Edition cover URL (for the rich
    notification image), resolved from the borrower's mirrored edition."""
    edition = await db.get(Edition, edition_id)
    work = await db.get(Work, edition.work_id) if edition is not None else None
    title = work.title if work is not None and work.title else "a book"
    cover = edition.cover_url if edition is not None else None
    return title, cover

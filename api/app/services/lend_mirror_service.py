"""Reflect an outgoing loan onto the borrower's account.

When a reader lends a book to a *linked, accepted* Kitabi user, the counterparty
should see it on their Borrowed shelf without doing anything — the [V1] "lending
record that appears on their account automatically" (feature-map.md). This
service creates/keeps-in-step a mirror `direction='borrowed'` record on the
borrower's account (correlated by `linked_loan_id`), which then pulls to their
device via the normal sync cursor.

Runs AFTER the lender's own sync op has committed (see sync_service.apply_ops),
and commits on its own — so a failure here can never reject the lender's loan.
"""

import uuid

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import LendingRecord, LibraryEntry
from app.models.profile import Profile
from app.services import connection_service


def _display_name(p: Profile | None) -> str:
    if p is None:
        return "A Kitabi reader"
    if p.full_name and p.full_name.strip():
        return p.full_name.strip()
    if p.username:
        return f"@{p.username}"
    return "A Kitabi reader"


async def mirror_lending(db: AsyncSession, lender_id: uuid.UUID, record_id: uuid.UUID) -> None:
    lent = await db.get(LendingRecord, record_id)
    if lent is None or lent.direction != "lent" or lent.borrower_user_id is None:
        return
    borrower_id = lent.borrower_user_id
    if not await connection_service.are_connected(db, lender_id, borrower_id):
        return

    # A lent record hangs off the lender's library entry; resolve the edition so
    # the borrower's mirror points at the same catalog book.
    edition_id = lent.edition_id
    if edition_id is None and lent.library_entry_id is not None:
        entry = await db.get(LibraryEntry, lent.library_entry_id)
        edition_id = entry.edition_id if entry else None
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

    if mirror is None:
        mirror = LendingRecord(
            id=uuid.uuid4(),
            user_id=borrower_id,
            direction="borrowed",
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
        await db.flush()
        await db.refresh(mirror, ["server_seq"])
    else:
        # Keep the mirror in step — returns, due-date edits, un/deletes.
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

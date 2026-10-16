"""Asks to borrow — "could you lend me this?" between connections, kept as a
record until the owner answers it (models/borrow_request.py).

The gate on *making* an ask is the circle's (`circle.borrow_ask` only accepts a
copy the asker could already see on that book); this module keeps the record
honest afterwards: one open ask per copy, no re-ask within a day of the last,
closed by the lending mirror when the owner lends that book to the asker, and
only shown while the two are still connected.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

from fastapi import HTTPException, status
from sqlalchemy import or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.borrow_request import (
    STATUS_DECLINED,
    STATUS_LENT,
    STATUS_OPEN,
    BorrowRequest,
)
from app.models.edition import Edition
from app.models.profile import Profile
from app.schemas.circle import BorrowAskOut, BorrowAskPersonOut, BorrowAsksOut
from app.services import circle_service

# A declined ask can be made again, but not straight away — "not now" should
# not turn into a notification a minute later.
REASK_AFTER = timedelta(hours=24)


async def ask(
    db: AsyncSession, requester_id: uuid.UUID, owner_id: uuid.UUID, edition_id: uuid.UUID
) -> tuple[BorrowRequest, bool]:
    """The ask for this copy, and whether it is new (only a new one notifies).
    An open ask is reused; a recent answered one holds off a fresh ask."""
    since = datetime.now(UTC) - REASK_AFTER
    existing = (
        (
            await db.execute(
                select(BorrowRequest)
                .where(
                    BorrowRequest.requester_id == requester_id,
                    BorrowRequest.owner_id == owner_id,
                    BorrowRequest.edition_id == edition_id,
                    or_(
                        BorrowRequest.status == STATUS_OPEN,
                        BorrowRequest.created_at >= since,
                    ),
                )
                .order_by(BorrowRequest.created_at.desc())
            )
        )
        .scalars()
        .first()
    )
    if existing is not None:
        return existing, False
    row = BorrowRequest(
        requester_id=requester_id, owner_id=owner_id, edition_id=edition_id, status=STATUS_OPEN
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return row, True


async def list_for(db: AsyncSession, me: uuid.UUID) -> BorrowAsksOut:
    """Open asks to me (incoming) and from me (outgoing), newest first, only
    between readers who are still connected."""
    connected = await circle_service.accepted_ids(db, me)
    if not connected:
        return BorrowAsksOut()
    rows = (
        (
            await db.execute(
                select(BorrowRequest)
                .where(
                    BorrowRequest.status == STATUS_OPEN,
                    or_(
                        (BorrowRequest.owner_id == me) & BorrowRequest.requester_id.in_(connected),
                        (BorrowRequest.requester_id == me) & BorrowRequest.owner_id.in_(connected),
                    ),
                )
                .order_by(BorrowRequest.created_at.desc())
                .limit(100)
            )
        )
        .scalars()
        .all()
    )
    if not rows:
        return BorrowAsksOut()
    people = {
        p.id: p
        for p in (
            await db.execute(
                select(Profile).where(
                    Profile.id.in_(
                        {r.owner_id if r.requester_id == me else r.requester_id for r in rows}
                    )
                )
            )
        )
        .scalars()
        .all()
    }
    editions = {
        e.id: e
        for e in (
            await db.execute(select(Edition).where(Edition.id.in_({r.edition_id for r in rows})))
        )
        .unique()
        .scalars()
        .all()
    }
    out = BorrowAsksOut()
    for r in rows:
        other_id = r.owner_id if r.requester_id == me else r.requester_id
        other = people.get(other_id)
        edition = editions.get(r.edition_id)
        if other is None or other.deleted_at is not None or edition is None:
            continue
        work = edition.work
        item = BorrowAskOut(
            id=r.id,
            person=BorrowAskPersonOut(
                user_id=other.id,
                name=circle_service.display_name(other),
                username=other.username,
                avatar_url=other.avatar_url,
            ),
            work_id=work.id,
            edition_id=edition.id,
            title=work.title,
            author=work.authors[0].name if work.authors else None,
            cover_url=edition.cover_url,
            created_at=r.created_at,
        )
        (out.incoming if r.owner_id == me else out.outgoing).append(item)
    return out


async def decline(db: AsyncSession, me: uuid.UUID, request_id: uuid.UUID) -> None:
    """The owner's "not now". Silent — nobody is told they were turned down."""
    row = await db.get(BorrowRequest, request_id)
    if row is None or row.owner_id != me:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "No such request"},
        )
    if row.status == STATUS_OPEN:
        row.status = STATUS_DECLINED
        row.resolved_at = datetime.now(UTC)
        await db.commit()


async def close_for_loan(
    db: AsyncSession, lender_id: uuid.UUID, borrower_id: uuid.UUID, edition_id: uuid.UUID
) -> None:
    """The owner lent this book to the reader who asked — from the request card
    or from anywhere else — so the ask is answered. Matched on the *work*: the
    owner may hand over a different printing of the same book. The caller
    commits."""
    work_id = (
        await db.execute(select(Edition.work_id).where(Edition.id == edition_id))
    ).scalar_one_or_none()
    if work_id is None:
        return
    asked_editions = select(Edition.id).where(Edition.work_id == work_id)
    await db.execute(
        update(BorrowRequest)
        .where(
            BorrowRequest.owner_id == lender_id,
            BorrowRequest.requester_id == borrower_id,
            BorrowRequest.status == STATUS_OPEN,
            BorrowRequest.edition_id.in_(asked_editions),
        )
        .values(status=STATUS_LENT, resolved_at=datetime.now(UTC))
    )

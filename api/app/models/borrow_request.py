"""BorrowRequest — one reader asking a connection to lend them a copy.

The first cut of "ask to borrow" (13 Oct 2026) was a push and nothing else, so
an ask existed only for as long as the notification did: the owner tapped it,
landed somewhere that never mentioned it, and could find it nowhere in the app
afterwards (owner report, 14 Oct 2026). A request is a record — the same move
lending made in rule 14 — so it can sit in an inbox until it's answered.

Cross-user and online-only like `Connection`: not a syncable Layer-2 table, the
app reads and answers it through `/circle/borrow-asks`.

`status`: 'open' → 'lent' (the owner lent that book to the asker, from any
screen — closed by the lending mirror) or 'declined' (the owner said "not
now"). Nothing is deleted.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, String, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base

STATUS_OPEN = "open"
STATUS_LENT = "lent"
STATUS_DECLINED = "declined"


class BorrowRequest(Base):
    __tablename__ = "borrow_requests"
    __table_args__ = (
        Index("ix_borrow_requests_owner_status", "owner_id", "status"),
        Index("ix_borrow_requests_requester_status", "requester_id", "status"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    requester_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    owner_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    # The owner's copy that was asked for.
    edition_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("editions.id"), nullable=False)
    status: Mapped[str] = mapped_column(String, nullable=False, default=STATUS_OPEN)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)

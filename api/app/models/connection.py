"""Connection model — a directed, consented lending link between two Kitabi users;
cross-user and online-only, so it is not a syncable Layer-2 table."""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, String, UniqueConstraint, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class Connection(Base):
    """A directed lending connection between two Kitabi users, with consent.

    Not a SyncableMixin table: like `Profile`, it's cross-user and lives online
    only (the offline sync engine is strictly per-user Layer-2 data, and a
    connection by definition spans two users). The app talks to it directly via
    the `/connections` API.

    `requester_id` sent the request; `addressee_id` must approve it. `status` is
    'pending' → 'accepted' (both consent, loans auto-link thereafter) or 'denied'
    (either party can decline/disconnect). One row per ordered pair; a reverse
    request from the addressee is treated as an accept rather than a second row.

    This is the `[LATER]` peer-to-peer social layer atop the `[V1]`
    `lending_records.borrower_user_id` link (feature-map.md) — the record still
    carries the borrower's id regardless; the connection governs whether that
    link is mutually confirmed.
    """

    __tablename__ = "connections"
    __table_args__ = (UniqueConstraint("requester_id", "addressee_id", name="uq_connections_pair"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    requester_id: Mapped[uuid.UUID] = mapped_column(Uuid, index=True, nullable=False)
    addressee_id: Mapped[uuid.UUID] = mapped_column(Uuid, index=True, nullable=False)
    # 'pending' | 'accepted' | 'denied' | 'blocked'
    status: Mapped[str] = mapped_column(String, nullable=False, default="pending")
    # Who blocked, when status == 'blocked'. A denied request can be re-sent
    # (reopens to pending); a blocked one can't — only the blocker can unblock.
    blocked_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, default=None)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

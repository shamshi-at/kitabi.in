"""ActiveReadingSession — the sitting that is running *right now*, for one
account, so a reader's other devices can see and stop it.

Deliberately **not** a SyncableMixin table, and deliberately not a row in
`reading_sessions`. Two reasons, both structural:

* A live sitting cannot be offline-first. Offline-first means every device may
  hold its own truth and reconcile later (rule 6: delete-wins, then LWW), which
  is exactly wrong here — two phones cannot both own "the" running timer, and a
  stop that loses a merge would silently discard a reader's sitting. So this is
  server-owned, online-only transport state, the same category as
  `device_tokens`.
* `reading_sessions` rows are *finished* sittings. Every insights, pace and
  reading-log query is written against that assumption; letting half-open rows
  in would mean auditing all of them for `ended_at IS NULL`. The finished
  sitting still syncs exactly as it does today — this table only covers the
  window between start and stop.

One row per user (`user_id` is the primary key): starting a sitting anywhere
replaces whatever was running, which is the same rule the app already enforces
on one device.
"""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, Integer, String, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class ActiveReadingSession(Base):
    __tablename__ = "active_reading_sessions"

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)

    #: The sitting's client-minted UUID. The app mints it at *start* (so a note
    #: written mid-sitting can reference it), and the `reading_sessions` row
    #: written at stop carries the same id — which is what lets either device
    #: write that row without creating two.
    session_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)

    library_entry_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    page_start: Mapped[int | None] = mapped_column(Integer, default=None)

    #: When the reader last answered "yes, still reading". Carried so the other
    #: device computes the same deadline instead of stopping a live sitting out
    #: from under them (the 26 Jul lesson: a confirmation has to move the
    #: deadline for *every* mechanism).
    confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)

    #: Which install started it — so the push that announces the sitting can be
    #: sent to the reader's *other* devices and not back to this one (a visible
    #: notification is drawn by the OS before any app code could ignore it).
    #: Also echoed in the payload, for the foreground case where the app sees it.
    device_id: Mapped[str | None] = mapped_column(String, default=None)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

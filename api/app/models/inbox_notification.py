"""InboxNotification — what a reader was notified about, kept where they can
find it again (the bell on Home).

A push is gone the moment it's swiped away, and on iOS a push that arrives while
the app is closed runs no app code at all, so the device can't be the one to
remember it. The server writes this row at the same moment it sends the push,
from the same text (services/notification_text.py) — and writes it even when
push isn't configured, so the inbox works with notifications off (owner
request, 14 Oct 2026).

Cross-user and online-only like `Connection`; not a syncable Layer-2 table.
Never deleted: "Clear" sets `cleared_at` (rule 3), "read" sets `read_at`.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import DateTime, Index, String, Uuid, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class InboxNotification(Base):
    __tablename__ = "notifications"
    __table_args__ = (Index("ix_notifications_user_created", "user_id", "created_at"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    # Who it's for.
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    # Who did it — the face on the row. Null for anything Kitabi itself says.
    actor_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, default=None)
    type: Mapped[str] = mapped_column(String, nullable=False)
    title: Mapped[str] = mapped_column(String, nullable=False)
    body: Mapped[str] = mapped_column(String, nullable=False)
    # The same data the push carries — the app routes a tap with it.
    data: Mapped[dict] = mapped_column(JSONB, default=dict, nullable=False)
    image_url: Mapped[str | None] = mapped_column(String, default=None)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
    cleared_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)

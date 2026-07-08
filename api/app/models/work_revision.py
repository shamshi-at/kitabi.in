"""Pending edit to a catalog Work — the wiki-style moderation queue.

An edit from the reader who contributed the Work (or to a Work nobody owns,
e.g. OpenLibrary imports) applies immediately; anyone else's edit lands here
as a `pending` revision that the contributor approves or rejects. This is the
deliberately-minimal V1 of moderation (feature-map.md: community later) — a
proper moderator role can take over the approver side without changing the
data shape.
"""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, Uuid, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class WorkRevision(Base):
    __tablename__ = "work_revisions"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    work_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("works.id"), nullable=False, index=True
    )
    proposed_by_user_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False, index=True)
    # The WorkUpdate fields as submitted (exclude_unset) — validated again
    # through WorkUpdate before being applied on approval.
    payload: Mapped[dict] = mapped_column(JSONB, nullable=False)
    status: Mapped[str] = mapped_column(String, nullable=False, default="pending", index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
    decided_by_user_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, default=None)

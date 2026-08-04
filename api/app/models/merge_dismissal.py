"""A human decision that two catalog rows are NOT the same entity.

The duplicate matchers recompute from names every run, so without recording a
rejection the reviewer is asked the same question forever and the queue never
empties. Pairs are stored ordered, so "A is not B" and "B is not A" are one
fact rather than two.
"""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, String, UniqueConstraint, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class MergeDismissal(Base):
    __tablename__ = "merge_dismissals"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    kind: Mapped[str] = mapped_column(String, nullable=False)
    left_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    right_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    dismissed_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, default=None)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    __table_args__ = (
        UniqueConstraint("kind", "left_id", "right_id", name="uq_merge_dismissal_pair"),
    )

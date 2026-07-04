import uuid

from sqlalchemy import CheckConstraint, ForeignKey, Index, Integer, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, SyncableMixin


class Rating(SyncableMixin, Base):
    """A star rating (1-5) — attaches to the Work, not the Edition
    (feature-map.md rule 17), so it's shared across every printing of the
    same book. Each translation is its own Work (product decision, 5 Jul
    2026) and so has its own independent rating pool."""

    __tablename__ = "ratings"
    # Overriding SyncableMixin's __table_args__ directive, so re-declare its
    # (user_id, server_seq) pull index alongside this table's own constraint.
    __table_args__ = (
        CheckConstraint("value BETWEEN 1 AND 5", name="ck_ratings_value_range"),
        Index("ix_ratings_user_seq", "user_id", "server_seq"),
    )

    work_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("works.id"), nullable=False)
    value: Mapped[int] = mapped_column(Integer, nullable=False)

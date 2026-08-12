"""Rating model — a syncable (Layer-2) 1-5 star rating on a Work or a Series."""

import uuid

from sqlalchemy import CheckConstraint, ForeignKey, Index, Integer, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, SyncableMixin


class Rating(SyncableMixin, Base):
    """A star rating (1-5) on exactly one subject.

    On a **Work** it attaches to the book, not the Edition (feature-map.md
    rule 17), so it is shared across every printing; each translation is its own
    Work (product decision, 5 Jul 2026) and so has its own independent pool.

    On a **Series** it rates the saga as a whole. That is a different claim from
    rating its volumes — "the Chola epic is a five-star series" is not "each of
    these five books is five stars" — so the two pools never mix. `series_id`
    and `work_id` are mutually exclusive, enforced in the database
    (migration 000044) rather than by every writer remembering.
    """

    __tablename__ = "ratings"
    # Overriding SyncableMixin's __table_args__ directive, so re-declare its
    # (user_id, server_seq) pull index alongside this table's own constraints.
    __table_args__ = (
        CheckConstraint("value BETWEEN 1 AND 5", name="ck_ratings_value_range"),
        CheckConstraint("num_nonnulls(work_id, series_id) = 1", name="ck_ratings_one_subject"),
        Index("ix_ratings_user_seq", "user_id", "server_seq"),
    )

    work_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("works.id"), nullable=True, default=None
    )
    series_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("series.id"), nullable=True, default=None, index=True
    )
    value: Mapped[int] = mapped_column(Integer, nullable=False)

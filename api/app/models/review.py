"""Review model — a syncable (Layer-2) text review on a Work or a Series, with
its own visibility flag; kept separate from the rating and the entry's notes."""

import uuid

from sqlalchemy import Boolean, CheckConstraint, ForeignKey, Index, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, SyncableMixin


class Review(SyncableMixin, Base):
    """Text review on exactly one subject — a Work or a Series — plus the user,
    with its own visibility flag (feature-map.md rule 13's three-way split:
    never merge with the rating or with personal notes). Defaults private; the
    user's `profiles.reviews_visible_default` only seeds the initial value
    client-side, it isn't read here.

    A series review is the same act on a different subject, which is why it
    lives here rather than in a table of its own: moderation reports, the public
    renderer, the reader's profile list and the sync entity are all
    subject-agnostic, and a second table would fork every one of them.
    `work_id` and `series_id` are mutually exclusive (migration 000044).
    """

    __tablename__ = "reviews"
    # Declaring __table_args__ here REPLACES SyncableMixin's directive, so its
    # (user_id, server_seq) pull index has to be re-declared alongside the new
    # constraint — dropping it would quietly turn every sync pull into a scan.
    __table_args__ = (
        CheckConstraint("num_nonnulls(work_id, series_id) = 1", name="ck_reviews_one_subject"),
        Index("ix_reviews_user_seq", "user_id", "server_seq"),
    )

    work_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("works.id"), nullable=True, default=None
    )
    series_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("series.id"), nullable=True, default=None, index=True
    )
    body: Mapped[str] = mapped_column(String, nullable=False)
    visible: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

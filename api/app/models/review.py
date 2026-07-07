"""Review model — a syncable (Layer-2) text review on a Work + user, with its own
visibility flag; kept separate from the Work's rating and the entry's notes."""

import uuid

from sqlalchemy import Boolean, ForeignKey, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, SyncableMixin


class Review(SyncableMixin, Base):
    """Text review — attaches to Work + user, with its own visibility flag
    (feature-map.md rule 13's three-way split: never merge with the rating
    or with personal notes). Defaults private; the user's
    `profiles.reviews_visible_default` only seeds the initial value client-side,
    it isn't read here."""

    __tablename__ = "reviews"

    work_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("works.id"), nullable=False)
    body: Mapped[str] = mapped_column(String, nullable=False)
    visible: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

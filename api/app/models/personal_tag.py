"""PersonalTag model — a user's own syncable (Layer-2) shelf/tag, kept distinct
from the global, catalog-owned Genre."""

from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, SyncableMixin


class PersonalTag(SyncableMixin, Base):
    """A user's own shelf/tag (e.g. "beach reads") — Layer 2, never
    conflated with the global, catalog-owned Genre (feature-map.md rule 6)."""

    __tablename__ = "personal_tags"

    name: Mapped[str] = mapped_column(String, nullable=False)

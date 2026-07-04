from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, CatalogMixin


class Author(CatalogMixin, Base):
    """Layer 1 catalog entity — linkable so filtering/grouping works
    (feature-map.md). `external_source`/`external_id` let us avoid re-fetching
    the same author from OpenLibrary on a later search (cache-on-first-use)."""

    __tablename__ = "authors"

    name: Mapped[str] = mapped_column(String, nullable=False, index=True)
    bio: Mapped[str | None] = mapped_column(String, default=None)
    external_source: Mapped[str | None] = mapped_column(String, default=None)
    external_id: Mapped[str | None] = mapped_column(String, default=None, index=True)

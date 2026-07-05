from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, CatalogMixin


class Author(CatalogMixin, Base):
    """Layer 1 catalog entity — linkable so filtering/grouping works
    (feature-map.md). `external_source`/`external_id` let us avoid re-fetching
    the same author from OpenLibrary on a later search (cache-on-first-use)."""

    __tablename__ = "authors"

    name: Mapped[str] = mapped_column(String, nullable=False, index=True)
    # The name they write/are known under, when different from `name` (e.g.
    # Kamala Das wrote Malayalam as "Madhavikutty").
    pen_name: Mapped[str | None] = mapped_column(String, default=None)
    image_url: Mapped[str | None] = mapped_column(String, default=None)
    bio: Mapped[str | None] = mapped_column(String, default=None)
    external_source: Mapped[str | None] = mapped_column(String, default=None)
    external_id: Mapped[str | None] = mapped_column(String, default=None, index=True)

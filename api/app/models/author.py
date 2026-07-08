"""Author model — a server-authoritative Layer-1 catalog entity linkable to Works."""

import uuid

from sqlalchemy import String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, CatalogMixin


class Author(CatalogMixin, Base):
    """Layer 1 catalog entity — linkable so filtering/grouping works
    (feature-map.md). `external_source`/`external_id` let us avoid re-fetching
    the same author from OpenLibrary on a later search (cache-on-first-use)."""

    __tablename__ = "authors"

    name: Mapped[str] = mapped_column(String, nullable=False, index=True)
    # Cross-script search form of `name` — see Work.title_translit.
    name_translit: Mapped[str | None] = mapped_column(String, default=None)
    # The name they write/are known under, when different from `name` (e.g.
    # Kamala Das wrote Malayalam as "Madhavikutty").
    pen_name: Mapped[str | None] = mapped_column(String, default=None)
    image_url: Mapped[str | None] = mapped_column(String, default=None)
    # The language they primarily write in (e.g. "Malayalam") — surfaced in the
    # author picker so a user can tell two same-named authors apart at a glance.
    primary_language: Mapped[str | None] = mapped_column(String, default=None)
    bio: Mapped[str | None] = mapped_column(String, default=None)
    external_source: Mapped[str | None] = mapped_column(String, default=None)
    external_id: Mapped[str | None] = mapped_column(String, default=None, index=True)
    # The reader who added this author to the catalog — for their contribution
    # score. Null for OpenLibrary-imported / seeded rows.
    created_by_user_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, default=None, index=True)

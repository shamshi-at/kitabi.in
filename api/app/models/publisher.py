"""Publisher model — a server-authoritative Layer-1 catalog entity referenced by
Editions."""

import uuid

from sqlalchemy import ForeignKey, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, CatalogMixin


class Publisher(CatalogMixin, Base):
    """Layer 1 catalog entity — same rationale as Author (feature-map.md)."""

    __tablename__ = "publishers"

    name: Mapped[str] = mapped_column(String, nullable=False, index=True)
    # Public URL segment — /publisher/dc-books. Assigned once, never recomputed.
    slug: Mapped[str | None] = mapped_column(String, default=None, unique=True, index=True)
    # Set when this row was merged into another as a duplicate. The row is soft
    # deleted too, but the pointer is what keeps its URL alive: resolution
    # follows it and 301s to the survivor rather than 404ing, so a merge
    # consolidates ranking instead of discarding it. Clearing this column undoes
    # the merge (services/merge_service).
    merged_into_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("publishers.id"), default=None, index=True
    )
    # Cross-script search form of `name` — see Work.title_translit.
    name_translit: Mapped[str | None] = mapped_column(String, default=None)
    # Spelling-insensitive search skeleton — see Work.title_fold.
    name_fold: Mapped[str | None] = mapped_column(String, default=None)
    logo_url: Mapped[str | None] = mapped_column(String, default=None)
    # The language this house mainly publishes in — parity with Author so the
    # publisher picker can show the same at-a-glance detail.
    primary_language: Mapped[str | None] = mapped_column(String, default=None)
    external_source: Mapped[str | None] = mapped_column(String, default=None)
    external_id: Mapped[str | None] = mapped_column(String, default=None, index=True)

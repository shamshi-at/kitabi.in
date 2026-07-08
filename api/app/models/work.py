"""Work model (Layer-1 catalog) plus the work_authors / work_genres join tables —
the abstract creative book that ratings, reviews, and translation links attach to."""

import uuid
from typing import TYPE_CHECKING

from sqlalchemy import Column, Float, ForeignKey, Index, String, Table, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, CatalogMixin

if TYPE_CHECKING:
    from app.models.author import Author
    from app.models.edition import Edition
    from app.models.genre import Genre

# Many-to-many join tables — plain association tables (no extra columns yet),
# so a lightweight Table object is enough; no need for a mapped class.
work_authors = Table(
    "work_authors",
    Base.metadata,
    Column("work_id", Uuid, ForeignKey("works.id"), primary_key=True),
    Column("author_id", Uuid, ForeignKey("authors.id"), primary_key=True),
)

work_genres = Table(
    "work_genres",
    Base.metadata,
    Column("work_id", Uuid, ForeignKey("works.id"), primary_key=True),
    Column("genre_id", Uuid, ForeignKey("genres.id"), primary_key=True),
)


class Work(CatalogMixin, Base):
    """The abstract creative work (feature-map.md rule 17: Work vs Edition).

    Ratings, reviews, and translation links attach here — to the Work, not a
    specific printing — so a cross-user rating average (and translation
    linking) is shared across every Edition of the same book. Ownership,
    cover, page count, and ISBN live on Edition instead.
    """

    __tablename__ = "works"

    title: Mapped[str] = mapped_column(String, nullable=False, index=True)
    # Lowercase Latin romanization of `title` for cross-script search
    # ("Kayary" finds "കയർ"). Maintained by app/models/translit_hooks.py on
    # every insert/update; GIN-trigram-indexed by migration 000020.
    title_translit: Mapped[str | None] = mapped_column(String, default=None)
    subtitle: Mapped[str | None] = mapped_column(String, default=None)
    description: Mapped[str | None] = mapped_column(String, default=None)
    language: Mapped[str | None] = mapped_column(String, default=None)
    first_publish_year: Mapped[int | None] = mapped_column(default=None)

    # [WIRED] — computes once Layer 2 ratings exist (Phase 3); null until then.
    # Never written to directly by the add/edit flow.
    aggregate_rating: Mapped[float | None] = mapped_column(Float, default=None)

    # [WIRED] — translation linking (feature-map.md). Works sharing a non-null
    # value here are considered translations of one another; no directionality,
    # no join table needed for this lightweight a structure. UI lands later.
    translation_group_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, default=None, index=True)

    external_source: Mapped[str | None] = mapped_column(String, default=None)
    external_id: Mapped[str | None] = mapped_column(String, default=None, index=True)

    # The reader who contributed this Work to the catalog — powers their
    # contribution score. Null for OpenLibrary-imported / seeded rows.
    created_by_user_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, default=None, index=True)

    authors: Mapped[list["Author"]] = relationship(secondary=work_authors, lazy="selectin")
    genres: Mapped[list["Genre"]] = relationship(secondary=work_genres, lazy="selectin")
    editions: Mapped[list["Edition"]] = relationship(back_populates="work", lazy="selectin")

    __table_args__ = (Index("ix_works_translation_group", "translation_group_id"),)

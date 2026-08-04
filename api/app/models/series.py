"""Series model — a named ordering of Works (Layer-1 catalog); the per-book
sequence number lives on Edition, not here."""

from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, CatalogMixin


class Series(CatalogMixin, Base):
    """A named ordering of works (e.g. "Ponniyin Selvan"). Book number lives
    on Edition (S7b: "book № of №"), not here — a series is just its name."""

    __tablename__ = "series"

    name: Mapped[str] = mapped_column(String, nullable=False, index=True)
    # Public URL segment — /series/malgudi. Assigned once, never recomputed.
    slug: Mapped[str | None] = mapped_column(String, default=None, unique=True, index=True)

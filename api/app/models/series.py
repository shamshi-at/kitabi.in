from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, CatalogMixin


class Series(CatalogMixin, Base):
    """A named ordering of works (e.g. "Ponniyin Selvan"). Book number lives
    on Edition (S7b: "book № of №"), not here — a series is just its name."""

    __tablename__ = "series"

    name: Mapped[str] = mapped_column(String, nullable=False, index=True)

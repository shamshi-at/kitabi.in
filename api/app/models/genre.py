from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, CatalogMixin


class Genre(CatalogMixin, Base):
    """Global, descriptive — belongs to the book, not to the user
    (feature-map.md rule 6: personal tags != global genres)."""

    __tablename__ = "genres"

    name: Mapped[str] = mapped_column(String, nullable=False, unique=True, index=True)

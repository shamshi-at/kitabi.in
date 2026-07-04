import uuid
from datetime import date

from sqlalchemy import Boolean, Date, ForeignKey, Integer, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, SyncableMixin

READING_STATUSES = ("pending", "reading", "read", "stopped", "wishlist")


class LibraryEntry(SyncableMixin, Base):
    """A user's personal copy of an Edition (Layer 2). Ownership, reading
    status, progress, favorite flag, and notes live here — never on the
    shared catalog (CLAUDE.md rule 17: ownership attaches to the Edition
    the user owns, not the abstract Work).

    `notes` is always private (feature-map.md rule 13's three-way split) —
    no visibility flag, unlike Review.
    """

    __tablename__ = "library_entries"

    edition_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("editions.id"), nullable=False)
    status: Mapped[str] = mapped_column(String, nullable=False, default="pending")
    start_date: Mapped[date | None] = mapped_column(Date, default=None)
    finish_date: Mapped[date | None] = mapped_column(Date, default=None)
    current_page: Mapped[int | None] = mapped_column(Integer, default=None)
    is_favorite: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    notes: Mapped[str | None] = mapped_column(String, default=None)

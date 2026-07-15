"""LibraryEntry model — a user's personal, syncable (Layer-2) copy of an Edition,
holding ownership, reading status, progress, favorite flag, and private notes."""

import uuid
from datetime import date

from sqlalchemy import Boolean, Date, ForeignKey, Integer, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, SyncableMixin

READING_STATUSES = ("pending", "reading", "read", "stopped", "wishlist")

# 'owned' — a copy you have. 'borrowed' — someone else's copy, currently or
# formerly with you (see `ownership` docstring below for the full lifecycle).
OWNERSHIP_VALUES = ("owned", "borrowed")


class LibraryEntry(SyncableMixin, Base):
    """A user's personal copy of an Edition (Layer 2). Ownership, reading
    status, progress, favorite flag, and notes live here — never on the
    shared catalog (CLAUDE.md rule 17: ownership attaches to the Edition
    the user owns, not the abstract Work).

    `notes` is always private (feature-map.md rule 13's three-way split) —
    no visibility flag, unlike Review.

    `ownership` (added 15 Jul 2026, owner request) unifies borrowed books
    into the same row shape as owned ones, so reading status/progress/notes
    all work identically regardless of whose copy it is:
    - `'owned'` (default) — a copy you have, from the add-book flow.
    - `'borrowed'` — created by the "log a borrowed book" flow, linked to a
      `LendingRecord` via that record's `library_entry_id` (reused for both
      lend directions — see lending_record.py). The entry is never deleted
      or hidden when the loan is returned: "returned" is derived entirely
      from the linked `LendingRecord.returned_date`, not stored here, so
      there's exactly one place that fact lives. If the reader later buys
      their own copy, `ownership` flips to `'owned'` on this same row (same
      id — reading history/progress/notes carry over untouched) while the
      `LendingRecord` stays put as a permanent log of the loan.
    """

    __tablename__ = "library_entries"

    edition_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("editions.id"), nullable=False)
    status: Mapped[str] = mapped_column(String, nullable=False, default="pending")
    ownership: Mapped[str] = mapped_column(String, nullable=False, default="owned")
    start_date: Mapped[date | None] = mapped_column(Date, default=None)
    finish_date: Mapped[date | None] = mapped_column(Date, default=None)
    current_page: Mapped[int | None] = mapped_column(Integer, default=None)
    is_favorite: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    notes: Mapped[str | None] = mapped_column(String, default=None)

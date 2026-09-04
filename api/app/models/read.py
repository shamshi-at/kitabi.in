"""Read model — one pass through a book.

CLAUDE.md rule 19: a read is a record, not a counter. Rule 14's shape applied
to reading itself, and for the same reason lending got it — "lent to X, on this
date, returned" is a fact with a shape, and so is "read it, between these dates,
in these sittings, thinking these things".
"""

import uuid
from datetime import date

from sqlalchemy import Date, ForeignKey, Integer, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, SyncableMixin


class Read(SyncableMixin, Base):
    """One pass through the book on a library entry.

    A book read three times has three beginnings, three endings, three paces
    and three sets of thoughts; `library_entries` has exactly one `start_date`,
    one `finish_date` and one `current_page` to hold them. Those columns stay
    exactly where they are as a **mirror of the current read**, so every
    existing reader of them keeps working — this table is additive, and the
    entry remains the answer to "where is this book now".

    **There is deliberately no `ordinal` column.** "Second read" is a position,
    and a stored position is a counter that two offline devices would both
    write: start a re-read on each with no signal and both claim "third".
    Position is derived by ordering an entry's reads on `start_date` (falling
    back to `created_at`), so devices converge without agreeing on a number.

    `status` uses the entry's own vocabulary for the pass: 'reading', 'read',
    'stopped'.
    """

    __tablename__ = "reads"

    library_entry_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("library_entries.id"), nullable=False
    )
    status: Mapped[str] = mapped_column(String, nullable=False, default="reading")
    # Dates, not timestamps — a read begins and ends on a day, and the wire
    # format is YYYY-MM-DD (the 16 Jul 2026 lesson: Pydantic only accepts a
    # datetime string for a `date` field when the time part is zero).
    start_date: Mapped[date | None] = mapped_column(Date, default=None)
    finish_date: Mapped[date | None] = mapped_column(Date, default=None)
    current_page: Mapped[int | None] = mapped_column(Integer, default=None)

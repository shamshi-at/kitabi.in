"""ReadingNote model — a syncable (Layer-2) private note against a library
entry, optionally tied to the reading session it was written during and to the
page or page range it is about."""

import uuid

from sqlalchemy import ForeignKey, Integer, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, SyncableMixin


class ReadingNote(SyncableMixin, Base):
    """One private thought about a book.

    Notes are the third leg of feature-map.md rule 13's split — ratings attach
    to the shared Work, reviews to Work+user with a visibility flag, and notes
    stay private on the *library entry*, forever. There is deliberately no
    visibility column here: unlike a review there is no other setting, so
    adding one would only invite it to be wrong.

    `session_id` is nullable because a note doesn't need a sitting — the
    classic "lent to mom, she folds pages" belongs to the book, not to any
    stretch of reading. It's also `ondelete=SET NULL`: deleting a session must
    never take the thoughts you had during it.

    `page_start`/`page_end` are both nullable and both optional. A note about a
    passage carries a range; a note about a moment carries just `page_start`;
    a note about the book carries neither.
    """

    __tablename__ = "reading_notes"

    library_entry_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("library_entries.id"), nullable=False
    )
    session_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("reading_sessions.id", ondelete="SET NULL"), default=None
    )
    body: Mapped[str] = mapped_column(String, nullable=False)
    page_start: Mapped[int | None] = mapped_column(Integer, default=None)
    page_end: Mapped[int | None] = mapped_column(Integer, default=None)

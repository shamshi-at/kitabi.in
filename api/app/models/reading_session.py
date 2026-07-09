"""ReadingSession model — a syncable (Layer-2) timed reading session against a
library entry: when it started, when it ended, and the page range covered.
Only ever pushed once stopped (the client's live "timer running" state is
local-only, never synced mid-session)."""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, SyncableMixin


class ReadingSession(SyncableMixin, Base):
    """One start-to-stop reading session on a library entry (a specific
    owned copy, not the abstract Work — progress already lives on
    LibraryEntry, this is the timed-log analogue). `duration_seconds` is
    stored explicitly rather than derived, so a client clock skew between
    start and end never produces a different number than what the reader
    actually saw on their own screen."""

    __tablename__ = "reading_sessions"

    library_entry_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("library_entries.id"), nullable=False
    )
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    ended_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    duration_seconds: Mapped[int] = mapped_column(Integer, nullable=False)
    page_start: Mapped[int | None] = mapped_column(Integer, default=None)
    page_end: Mapped[int | None] = mapped_column(Integer, default=None)

import uuid
from datetime import date

from sqlalchemy import Date, ForeignKey, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, SyncableMixin


class LendingRecord(SyncableMixin, Base):
    """A record, not a flag (feature-map.md rule 14) — "lent to X, on date,
    returned Y/N" as its own entity. `borrower_name` is free text for now;
    `borrower_user_id` is a real user reference once Kitabi has more than one
    real user (dormant `[WIRED]` field, matching the community switchboard
    pattern from Phase 1's Profile visibility toggles)."""

    __tablename__ = "lending_records"

    library_entry_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("library_entries.id"), nullable=False
    )
    borrower_name: Mapped[str] = mapped_column(String, nullable=False)
    borrower_user_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, default=None)
    lent_date: Mapped[date] = mapped_column(Date, nullable=False)
    due_date: Mapped[date | None] = mapped_column(Date, default=None)
    returned_date: Mapped[date | None] = mapped_column(Date, default=None)

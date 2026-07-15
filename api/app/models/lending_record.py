"""LendingRecord model — a syncable (Layer-2) lend/borrow ledger entry ("lent to X,
on date, returned Y/N") as its own entity, running both directions."""

import uuid
from datetime import date

from sqlalchemy import Date, ForeignKey, Index, String, Uuid, text
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, SyncableMixin


class LendingRecord(SyncableMixin, Base):
    """A record, not a flag (feature-map.md rule 14) — "lent to X, on date,
    returned Y/N" as its own entity. Runs both directions (feature-map.md
    "Lending — the ledger, both ways").

    `direction` is 'lent' (I lent my copy out) or 'borrowed' (someone's copy is
    with me). Either way `library_entry_id` points at the account owner's own
    LibraryEntry for this loan: for 'lent' it's the owned copy that went out;
    for 'borrowed' it's the `ownership='borrowed'` entry created by the
    "log a borrowed book" flow (added 15 Jul 2026 — previously borrowed loans
    left this null and relied on `edition_id` alone; new borrowed records set
    both). `edition_id` stays populated on 'borrowed' rows too, so older
    clients/rows that never got a `library_entry_id` still resolve the book.
    `borrower_name` is the free-text counterparty (the borrower if I lent, the
    lender if I borrowed).

    `borrower_user_id` / `linked_loan_id` are dormant `[WIRED]` fields for the
    cross-user case: once both sides are Kitabi users, a lend can mirror a
    borrowed row onto the counterparty's account, correlated by `linked_loan_id`
    (not a shared row — each side closes its own copy)."""

    __tablename__ = "lending_records"
    __table_args__ = (
        # One mirror per (borrower, source loan) — enforced in the database so
        # two concurrent lender pushes can't each create a mirror (the app-level
        # select-then-insert in lend_mirror_service races without this).
        Index(
            "uq_lending_mirror_pair",
            "user_id",
            "linked_loan_id",
            unique=True,
            postgresql_where=text("linked_loan_id IS NOT NULL"),
        ),
    )

    direction: Mapped[str] = mapped_column(String, nullable=False, default="lent")
    library_entry_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("library_entries.id"), default=None
    )
    edition_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("editions.id"), default=None
    )
    borrower_name: Mapped[str] = mapped_column(String, nullable=False)
    borrower_user_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, default=None)
    linked_loan_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, default=None)
    lent_date: Mapped[date] = mapped_column(Date, nullable=False)
    due_date: Mapped[date | None] = mapped_column(Date, default=None)
    returned_date: Mapped[date | None] = mapped_column(Date, default=None)
    note: Mapped[str | None] = mapped_column(String, default=None)

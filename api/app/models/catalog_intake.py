"""`catalog_intake` — the staging table every new catalogue row passes through.

Until now the catalogue grew two ways: readers adding books, and a human running
the `etl/` scripts from a laptop with a 9 GB download. Neither is a daily job,
and the dump path in particular imported records that then needed repairing —
`etl/09_marc_cleanup.py` and `etl/10_title_restore.py` exist for no other reason
(docs/catalog-intake-plan.md §1).

This table is what lets intake run unattended without that happening again. It
holds *candidates*, not catalogue rows: discovery writes here and *only* here,
so a source can be crawled, re-crawled and argued with while the catalogue
itself stays untouched. Promotion is the single writer that turns a candidate
into a Work, and it only ever runs on a row the completeness gate has passed.

Three things the table buys that a straight-through pipeline cannot:

- **"What is new today" has an answer.** `(source, source_key)` is unique, so a
  re-crawl updates rather than duplicates, and `first_seen_at` is real.
- **A candidate that fails today can pass later.** A book missing an ISBN sits
  at `incomplete` and is re-screened when another source fills the hole,
  without re-crawling the first one.
- **Every promotion leaves a receipt.** `work_id`/`edition_id` record exactly
  what this pipeline created, so "undo last night" is one query — the same
  reversibility `08`/`09`/`10` get from their receipt files, except this job
  runs unattended, so the receipt has to live in the database.

Not a syncable table (rule 10 does not apply — no `user_id`, nothing to pull)
and not really Layer-1 catalog either: it is machinery. Hence a plain `Base`
with its own columns rather than `CatalogMixin`, and RLS deny-by-default like
every other table (rule 11).
"""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, Index, String, Uuid, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base

# --- states ---------------------------------------------------------------
# Stable strings: they are read by the admin console and written into logs, so
# a value from last month must still mean what it meant. Never rename in place.

#: Raw from a source adapter, not yet screened.
STATE_DISCOVERED = "discovered"
#: Passed the completeness gate; waiting for its turn in the daily budget.
STATE_COMPLETE = "complete"
#: Failed the gate on something another source could still supply. Re-screened
#: whenever the payload changes. This queue is the honest measure of coverage.
STATE_INCOMPLETE = "incomplete"
#: Failed on something no source will fix — a supplied heading that isn't a
#: book, a truncated import. Never retried; kept so we don't re-discover it
#: every night and reach the same conclusion.
STATE_REJECTED = "rejected"
#: The catalogue already holds this book. Not a failure, and not a second Work.
STATE_DUPLICATE = "duplicate"
#: In the catalogue. `work_id` / `edition_id` say where.
STATE_PROMOTED = "promoted"

STATES = (
    STATE_DISCOVERED,
    STATE_COMPLETE,
    STATE_INCOMPLETE,
    STATE_REJECTED,
    STATE_DUPLICATE,
    STATE_PROMOTED,
)


class CatalogIntake(Base):
    """One candidate book, from one source, on its way to the catalogue."""

    __tablename__ = "catalog_intake"
    __table_args__ = (
        # The uniqueness that makes a re-crawl converge instead of duplicating.
        Index("ux_catalog_intake_source_key", "source", "source_key", unique=True),
        # The promotion query: the oldest `complete` rows, every run.
        Index("ix_catalog_intake_state_seen", "state", "first_seen_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)

    #: Which adapter produced this — "openlibrary_en", "mathrubhumi", …
    source: Mapped[str] = mapped_column(String, nullable=False)
    #: That source's own stable id for the book (an OL work key, a product id).
    source_key: Mapped[str] = mapped_column(String, nullable=False)

    state: Mapped[str] = mapped_column(String, nullable=False, default=STATE_DISCOVERED)

    #: Canonical ISBN-13 where one could be derived. Indexed because promotion
    #: checks it against the catalogue, and because "did we already see this
    #: book from another source" is the cross-source-fill question.
    isbn: Mapped[str | None] = mapped_column(String, default=None, index=True)

    #: The screened candidate — cleaned title/authors, cover, publisher. Stored
    #: rather than re-derived so a gate change can be replayed against what the
    #: source actually said, without re-crawling.
    payload: Mapped[dict] = mapped_column(JSONB, nullable=False)
    #: Field names the gate found missing (`incomplete`), or the fatal flags
    #: that rejected it. Empty for a row that passed.
    missing: Mapped[list | None] = mapped_column(JSONB, default=None)
    #: Free text for a human reading the queue — why this row is where it is.
    note: Mapped[str | None] = mapped_column(String, default=None)

    #: The receipt. Null until promotion; set together, in one transaction.
    work_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, default=None, index=True)
    edition_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, default=None)

    #: How many times promotion has tried and failed on something transient.
    #: A row that keeps failing stops being retried rather than blocking the
    #: queue head forever.
    attempts: Mapped[int] = mapped_column(default=0, nullable=False)

    first_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
    promoted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)

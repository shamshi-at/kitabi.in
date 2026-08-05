"""Backfill editions.isbn to the canonical ISBN-13 form.

The same book is 8126403454 on a 2005 printing and 9788126403455 on a 2019 one.
Every lookup was `isbn = <what the reader typed>`, so whichever form we happened
to store decided whether the book could be found — a reader holding the older
copy was told the catalogue had never heard of it.

The fix has two halves and needs both: lookups now expand to every equivalent
form (`services/isbn.variants`), and new writes are canonicalised on the way in
(the `NormalizedIsbn` schema type). This migration is the third piece — the rows
already stored, which neither of those reaches.

Conservative by construction. A row is rewritten ONLY when:

  * it is ISBN-10 shaped, AND
  * its checksum is valid — a mis-keyed ISBN-10 converted anyway would yield a
    perfectly valid ISBN-13 belonging to a DIFFERENT book, which nothing
    downstream could ever detect — AND
  * the resulting ISBN-13 is not already on another edition. `editions.isbn` is
    UNIQUE, and a catalogue holding both forms on two rows is exactly the state
    this exists to clean up; colliding rows are left alone for the merge tooling
    rather than crashing the migration.

Anything skipped stays findable regardless, because `variants` matches the
literal stored value too. This migration is an optimisation and a tidy-up, not
the correctness fix.

The arithmetic is INLINE rather than imported from `app.services.isbn`. A
migration that calls application code is welded to a moving target — the classic
way a migration that ran fine in August fails to replay in December (see the
note in 000038). This is a frozen historical operation and carries its own copy.

Revision ID: 000041
Revises: 000040
Create Date: 2026-08-05
"""

import re

import sqlalchemy as sa

from alembic import op

revision: str = "000041"
down_revision: str | None = "000040"
branch_labels = None
depends_on = None

_ISBN10_RE = re.compile(r"^[0-9]{9}[0-9X]$")


def _is_valid_isbn10(value: str) -> bool:
    if not _ISBN10_RE.match(value):
        return False
    total = sum(
        (10 if char == "X" else int(char)) * (10 - index) for index, char in enumerate(value)
    )
    return total % 11 == 0


def _to_isbn13(isbn10: str) -> str:
    body = "978" + isbn10[:9]
    total = sum((1 if i % 2 == 0 else 3) * int(d) for i, d in enumerate(body))
    return body + str((10 - total % 10) % 10)


def upgrade() -> None:
    _backfill(op.get_bind())


def _backfill(connection) -> None:  # noqa: ANN001 — a SQLAlchemy Connection
    """The whole operation, taking its connection as an argument so a test can
    drive it against real rows. A migration whose only proof is that it ran
    without raising has not been tested — the interesting cases here are the two
    it must REFUSE to touch."""
    rows = connection.execute(
        sa.text("SELECT id, isbn FROM editions WHERE isbn IS NOT NULL AND length(isbn) = 10")
    ).fetchall()
    if not rows:
        return

    # One round trip for the collision check rather than one per row.
    candidates = {}
    for row_id, value in rows:
        cleaned = value.strip().upper()
        if _is_valid_isbn10(cleaned):
            candidates[row_id] = _to_isbn13(cleaned)
    if not candidates:
        return

    taken = {
        value
        for (value,) in connection.execute(
            sa.text("SELECT isbn FROM editions WHERE isbn = ANY(:values)"),
            {"values": list(set(candidates.values()))},
        ).fetchall()
    }

    for row_id, isbn13 in candidates.items():
        if isbn13 in taken:
            continue
        connection.execute(
            sa.text("UPDATE editions SET isbn = :isbn WHERE id = :id"),
            {"isbn": isbn13, "id": row_id},
        )


def downgrade() -> None:
    """Deliberately a no-op.

    Converting every 978-prefixed ISBN-13 back would also rewrite rows that were
    stored as ISBN-13 from the start — this migration does not record which rows
    it touched, and inventing that distinction on the way down would corrupt more
    than it restored. The forward direction is lossless (the ISBN-10 is
    recoverable from any 978 ISBN-13), so nothing is actually lost by not
    reversing it.
    """

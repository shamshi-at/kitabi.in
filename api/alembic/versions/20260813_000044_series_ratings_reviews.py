"""Let a rating or a review name a series instead of a book.

A reader who finishes Ponniyin Selvan has something to say about the *saga*
that is not a sentence about volume 3, and a five-star series is not the same
claim as five stars on each of its books. So a series carries its own rating
pool and its own reviews, and the books inside it keep theirs untouched.

**One table per act, not one table per subject.** A series review is the same
act as a book review on a different subject, and everything downstream of a
review is already subject-agnostic: the visibility flag, the moderation report
that points at it, the public renderer, the reader's profile list, the sync
entity that carries it. A parallel `series_reviews` table would fork all of
that, and forked pipelines drift — which is how every public review's text
came to be invisible on the web for months while the app showed it fine.

So `work_id` becomes nullable, `series_id` joins it, and a CHECK insists on
exactly one. That constraint is the whole safety argument: a row can never mean
both or neither, so every existing query — all of which filter by a specific
work, or join `work_id` to `works.id` — keeps excluding series rows by
construction rather than by remembering to.

Nothing is backfilled: every existing row is a book rating or a book review and
stays exactly that.

Revision ID: 000044
Revises: 000043
Create Date: 2026-08-13
"""

import sqlalchemy as sa

from alembic import op

revision: str = "000044"
down_revision: str | None = "000043"
branch_labels = None
depends_on = None


def upgrade() -> None:
    for table in ("ratings", "reviews"):
        op.add_column(table, sa.Column("series_id", sa.Uuid(), nullable=True))
        op.create_foreign_key(f"fk_{table}_series", table, "series", ["series_id"], ["id"])
        op.create_index(f"ix_{table}_series_id", table, ["series_id"])
        op.alter_column(table, "work_id", existing_type=sa.Uuid(), nullable=True)
        # Exactly one subject. Without this a row could name both (which
        # aggregate is it in?) or neither (a rating of nothing), and both would
        # only ever be noticed as a wrong number on a page.
        op.create_check_constraint(
            f"ck_{table}_one_subject",
            table,
            "num_nonnulls(work_id, series_id) = 1",
        )


def downgrade() -> None:
    for table in ("ratings", "reviews"):
        # Series rows have no home in the old shape; they go, rather than
        # being rewritten into book rows they were never about.
        op.execute(f"DELETE FROM {table} WHERE series_id IS NOT NULL")  # noqa: S608
        op.drop_constraint(f"ck_{table}_one_subject", table, type_="check")
        op.alter_column(table, "work_id", existing_type=sa.Uuid(), nullable=False)
        op.drop_index(f"ix_{table}_series_id", table_name=table)
        op.drop_constraint(f"fk_{table}_series", table, type_="foreignkey")
        op.drop_column(table, "series_id")

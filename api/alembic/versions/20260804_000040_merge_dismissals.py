"""merge_dismissals — "these two are not the same entity".

Without this the review queue can never empty. The candidate matchers recompute
from names on every run, so a cluster a human has already looked at and rejected
comes straight back the next time, and the reviewer is asked the same question
forever. Recording the rejection is what turns a list into a queue.

Stored as ordered pairs rather than clusters because cluster membership changes
as rows are added, while "A is not B" stays true.

RLS enabled with zero policies like every other table (CLAUDE.md rule 11).

Revision ID: 000040
Revises: 000039
Create Date: 2026-08-04
"""

import sqlalchemy as sa

from alembic import op

revision: str = "000040"
down_revision: str | None = "000039"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "merge_dismissals",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("kind", sa.String(), nullable=False),
        # Ordered so (A,B) and (B,A) are the same fact and cannot both be stored.
        sa.Column("left_id", sa.Uuid(), nullable=False),
        sa.Column("right_id", sa.Uuid(), nullable=False),
        sa.Column("dismissed_by", sa.Uuid(), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.UniqueConstraint("kind", "left_id", "right_id", name="uq_merge_dismissal_pair"),
    )
    op.execute("ALTER TABLE merge_dismissals ENABLE ROW LEVEL SECURITY")


def downgrade() -> None:
    op.drop_table("merge_dismissals")

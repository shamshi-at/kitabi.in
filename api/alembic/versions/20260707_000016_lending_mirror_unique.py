"""One mirror per (borrower, source loan) — dedupe then enforce in the DB.

Revision ID: 000016
Revises: 000015
Create Date: 2026-07-07
"""

import sqlalchemy as sa

from alembic import op

revision: str = "000016"
down_revision: str | None = "000015"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Remove any duplicate mirrors the select-then-insert race already created,
    # keeping the earliest row per (user_id, linked_loan_id). These are
    # server-generated mirror artifacts (never user-authored), so a hard delete
    # of the extras is safe — and a soft delete couldn't satisfy the index.
    op.execute(
        sa.text(
            """
            DELETE FROM lending_records a
            USING lending_records b
            WHERE a.linked_loan_id IS NOT NULL
              AND a.user_id = b.user_id
              AND a.linked_loan_id = b.linked_loan_id
              AND (a.created_at, a.id) > (b.created_at, b.id)
            """
        )
    )
    op.create_index(
        "uq_lending_mirror_pair",
        "lending_records",
        ["user_id", "linked_loan_id"],
        unique=True,
        postgresql_where=sa.text("linked_loan_id IS NOT NULL"),
    )


def downgrade() -> None:
    op.drop_index("uq_lending_mirror_pair", table_name="lending_records")

"""Buy-link clicks — who opened which bookseller link, for which book.

Append-only, like `promotion_events`. A new table and nothing else, so it is
safe to run against the previous version of the code, which never reads it.
RLS enabled with zero policies like every other table (CLAUDE.md rule 11).

Revision ID: 000054
Revises: 000053
Create Date: 2026-10-05
"""

import sqlalchemy as sa

from alembic import op

revision: str = "000054"
down_revision: str | None = "000053"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "buy_clicks",
        # Device-generated for the app: a retried batch collides on the PK and
        # is dropped instead of double-counted.
        sa.Column("id", sa.Uuid(), primary_key=True),
        # NULL for a website visitor — nothing about them is stored.
        sa.Column("user_id", sa.Uuid(), nullable=True),
        sa.Column("work_id", sa.Uuid(), sa.ForeignKey("works.id"), nullable=False),
        sa.Column("edition_id", sa.Uuid(), sa.ForeignKey("editions.id"), nullable=True),
        sa.Column("retailer", sa.String(), nullable=False),
        sa.Column("surface", sa.String(), nullable=False),
        sa.Column("affiliate", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "received_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
    )
    op.create_index("ix_buy_clicks_occurred", "buy_clicks", ["occurred_at"])
    op.create_index("ix_buy_clicks_work", "buy_clicks", ["work_id", "occurred_at"])
    op.create_index("ix_buy_clicks_user", "buy_clicks", ["user_id", "occurred_at"])

    # RLS deny-by-default (rule 11): enabled, zero policies.
    op.execute("ALTER TABLE buy_clicks ENABLE ROW LEVEL SECURITY")


def downgrade() -> None:
    op.drop_table("buy_clicks")

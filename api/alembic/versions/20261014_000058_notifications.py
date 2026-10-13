"""notifications — the in-app inbox behind the bell on Home

Every reader-to-reader push is also written here, so a reader can find what
they were told after the banner is gone (owner request, 14 Oct 2026). New table
only; safe against the previous image while the new one rolls. RLS enabled,
zero policies (rule 11).

Revision ID: 000058
Revises: 000057
"""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "000058"
down_revision: str | None = "000057"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "notifications",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("actor_id", sa.Uuid(), nullable=True),
        sa.Column("type", sa.String(), nullable=False),
        sa.Column("title", sa.String(), nullable=False),
        sa.Column("body", sa.String(), nullable=False),
        sa.Column(
            "data", postgresql.JSONB(), nullable=False, server_default=sa.text("'{}'::jsonb")
        ),
        sa.Column("image_url", sa.String(), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("read_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("cleared_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_notifications_user_created", "notifications", ["user_id", "created_at"])
    op.execute("ALTER TABLE notifications ENABLE ROW LEVEL SECURITY")


def downgrade() -> None:
    op.drop_table("notifications")

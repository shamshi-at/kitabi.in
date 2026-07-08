"""work_revisions — the wiki-style moderation queue for catalog edits.

An edit to a Work by anyone other than its contributor is stored here as a
pending revision instead of being applied; the contributor approves/rejects.
RLS enabled with zero policies (CLAUDE.md rule 11) — only the API touches it.

Revision ID: 000021
Revises: 000020
Create Date: 2026-07-08
"""

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

from alembic import op

revision: str = "000021"
down_revision: str | None = "000020"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "work_revisions",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "work_id", sa.Uuid(), sa.ForeignKey("works.id"), nullable=False, index=True
        ),
        sa.Column("proposed_by_user_id", sa.Uuid(), nullable=False, index=True),
        sa.Column("payload", JSONB(), nullable=False),
        sa.Column("status", sa.String(), nullable=False, index=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("decided_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("decided_by_user_id", sa.Uuid(), nullable=True),
    )
    op.execute("ALTER TABLE work_revisions ENABLE ROW LEVEL SECURITY")


def downgrade() -> None:
    op.drop_table("work_revisions")

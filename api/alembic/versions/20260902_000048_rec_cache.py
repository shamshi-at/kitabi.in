"""rec_cache — a reader's last generated recommendations, so re-opening the
screen is free.

The picks are a pure function of what feeds the prompt (the reader's rated
books and what they own), and none of that changes between two visits — yet
every visit that passed the free gates burned a fresh Anthropic call (owner
request, 2 Sep 2026). One row per reader: a fingerprint of the inputs, the
picks as work ids + "why" sentences, and when the LLM actually ran (the TTL
reads that). Server-side operational data like llm_usage — no sync columns,
no soft delete; dropping the table loses one regeneration per reader.

Safe against the previous code version (CLAUDE.md deploy rule): the table is
new and nothing running reads or writes it until the new image serves.

Revision ID: 000048
Revises: 000047
Create Date: 2026-09-02
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "000048"
down_revision: str | None = "000047"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "rec_cache",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("fingerprint", sa.String(), nullable=False),
        sa.Column("picks", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("generated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("user_id"),
    )
    # RLS enabled, zero policies, like every table (CLAUDE.md rule 11) — only
    # the API's direct connection touches it.
    op.execute("ALTER TABLE rec_cache ENABLE ROW LEVEL SECURITY")


def downgrade() -> None:
    op.drop_table("rec_cache")

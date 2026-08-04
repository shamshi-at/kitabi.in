"""llm_usage — daily spend metering for the paid LLM endpoints.

`GET /recommendations` and `POST /catalog/cover-extract` each cost an Anthropic
call, and until now neither had any ceiling: auth means "any Google account",
so the cap on the bill was the caller's patience. This table backs a per-reader
daily quota and a global daily circuit breaker (services/llm_quota.py).

Postgres, not Redis — CLAUDE.md rule 8. At Kitabi's scale one small table and a
SUM over one day's rows is cheaper than a service that adds a bill.

RLS enabled with zero policies like every other table (rule 11).

Revision ID: 000037
Revises: 000036
Create Date: 2026-08-04
"""

import sqlalchemy as sa

from alembic import op

revision: str = "000037"
down_revision: str | None = "000036"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "llm_usage",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("feature", sa.String(), nullable=False),
        sa.Column("day", sa.Date(), nullable=False),
        sa.Column("count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        # The quota upsert conflicts on this constraint by name — renaming it
        # breaks `llm_quota.consume`, which names it explicitly.
        sa.UniqueConstraint("user_id", "feature", "day", name="uq_llm_usage_user_feature_day"),
    )
    # Serves the global circuit breaker's SUM(count) WHERE day = today.
    op.create_index("ix_llm_usage_day", "llm_usage", ["day"])
    op.execute("ALTER TABLE llm_usage ENABLE ROW LEVEL SECURITY")


def downgrade() -> None:
    op.drop_index("ix_llm_usage_day", table_name="llm_usage")
    op.drop_table("llm_usage")

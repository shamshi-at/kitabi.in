"""catalog_intake — the staging table the daily intake job promotes from

Discovery writes candidates here and nowhere else; promotion is the only
writer that turns one into a Work. That separation is the whole point: a
source can be crawled and re-crawled without a single catalogue row appearing,
and every row that does appear leaves its receipt (`work_id`/`edition_id`)
behind on the candidate that produced it.

Purely additive — a new table, no existing column touched — so it is safe to
run against the previous version of the code, which is what serves traffic
while the new image rolls (CLAUDE.md: the container migrates on boot).

The job that reads it is dormant unless `CATALOG_INTAKE_ENABLED` is set, so
this migration reaching production does not by itself create anything.

Revision ID: 000053
Revises: 000052
"""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "000053"
down_revision: str | None = "000052"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "catalog_intake",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("source", sa.String(), nullable=False),
        sa.Column("source_key", sa.String(), nullable=False),
        sa.Column("state", sa.String(), nullable=False),
        sa.Column("isbn", sa.String(), nullable=True),
        sa.Column("payload", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("missing", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("note", sa.String(), nullable=True),
        sa.Column("work_id", sa.Uuid(), nullable=True),
        sa.Column("edition_id", sa.Uuid(), nullable=True),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column(
            "first_seen_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("promoted_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    # A re-crawl must converge, not duplicate.
    op.create_index(
        "ux_catalog_intake_source_key", "catalog_intake", ["source", "source_key"], unique=True
    )
    # The promotion query: oldest `complete` first, every run.
    op.create_index(
        "ix_catalog_intake_state_seen", "catalog_intake", ["state", "first_seen_at"]
    )
    op.create_index(op.f("ix_catalog_intake_isbn"), "catalog_intake", ["isbn"])
    op.create_index(op.f("ix_catalog_intake_work_id"), "catalog_intake", ["work_id"])
    # RLS deny-by-default on every new table (rule 11): enabled, zero policies.
    op.execute("ALTER TABLE catalog_intake ENABLE ROW LEVEL SECURITY")


def downgrade() -> None:
    op.drop_index(op.f("ix_catalog_intake_work_id"), table_name="catalog_intake")
    op.drop_index(op.f("ix_catalog_intake_isbn"), table_name="catalog_intake")
    op.drop_index("ix_catalog_intake_state_seen", table_name="catalog_intake")
    op.drop_index("ux_catalog_intake_source_key", table_name="catalog_intake")
    op.drop_table("catalog_intake")

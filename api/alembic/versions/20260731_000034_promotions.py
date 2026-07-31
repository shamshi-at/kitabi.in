"""Promotions — in-app banner/card campaigns, their per-language copy, and
append-only engagement events (docs/promotions-plan.md).

Operator-owned content served to readers who match a campaign's targeting.
RLS enabled with zero policies like every other table (CLAUDE.md rule 11).

Revision ID: 000034
Revises: 000033
Create Date: 2026-07-31
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "000034"
down_revision: str | None = "000033"
branch_labels = None
depends_on = None

_TABLES = ("promotions", "promotion_contents", "promotion_events")


def upgrade() -> None:
    op.create_table(
        "promotions",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("kind", sa.String(), nullable=False, server_default="banner"),
        sa.Column("card_style", sa.String(), nullable=True),
        sa.Column("placement", sa.String(), nullable=False, server_default="home_top"),
        sa.Column("status", sa.String(), nullable=False, server_default="draft"),
        sa.Column("sponsor", sa.String(), nullable=True),
        sa.Column("priority", sa.Integer(), nullable=False, server_default="5"),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "targeting", postgresql.JSONB(), nullable=False, server_default=sa.text("'{}'::jsonb")
        ),
        sa.Column(
            "frequency", postgresql.JSONB(), nullable=False, server_default=sa.text("'{}'::jsonb")
        ),
        sa.Column("work_id", sa.Uuid(), sa.ForeignKey("works.id"), nullable=True),
        sa.Column("edition_id", sa.Uuid(), sa.ForeignKey("editions.id"), nullable=True),
        sa.Column("created_by", sa.Uuid(), nullable=True),
        sa.Column("updated_by", sa.Uuid(), nullable=True),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_promotions_status", "promotions", ["status"])

    op.create_table(
        "promotion_contents",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "promotion_id", sa.Uuid(), sa.ForeignKey("promotions.id"), nullable=False
        ),
        sa.Column("language", sa.String(), nullable=True),
        sa.Column("headline", sa.String(), nullable=False),
        sa.Column("body", sa.String(), nullable=True),
        sa.Column("cta_label", sa.String(), nullable=True),
        sa.Column("image_url", sa.String(), nullable=True),
        sa.Column("action_type", sa.String(), nullable=False, server_default="none"),
        sa.Column("action_value", sa.String(), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
    )
    op.create_index("ix_promotion_contents_promotion_id", "promotion_contents", ["promotion_id"])
    # One row per named language, and exactly one default (language IS NULL).
    # Two partial indexes rather than one UNIQUE constraint: Postgres counts
    # NULLs as distinct, so UNIQUE(promotion_id, language) would let a campaign
    # collect any number of default variants.
    op.create_index(
        "uq_promotion_contents_lang",
        "promotion_contents",
        ["promotion_id", "language"],
        unique=True,
        postgresql_where=sa.text("language IS NOT NULL"),
    )
    op.create_index(
        "uq_promotion_contents_default",
        "promotion_contents",
        ["promotion_id"],
        unique=True,
        postgresql_where=sa.text("language IS NULL"),
    )

    op.create_table(
        "promotion_events",
        # Client-generated: a retried batch collides on the PK and is dropped
        # instead of double-counted.
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "promotion_id", sa.Uuid(), sa.ForeignKey("promotions.id"), nullable=False
        ),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("kind", sa.String(), nullable=False),
        sa.Column("language", sa.String(), nullable=True),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "received_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
    )
    op.create_index(
        "ix_promotion_events_reader", "promotion_events", ["user_id", "promotion_id", "kind"]
    )
    op.create_index(
        "ix_promotion_events_promo_kind", "promotion_events", ["promotion_id", "kind"]
    )

    # RLS deny-by-default on every new table (rule 11): enabled, zero policies.
    for table in _TABLES:
        op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY")

    # The reader's own switch (plan §11). Lives on profiles because it's an
    # identity preference, not campaign state.
    op.add_column(
        "profiles",
        sa.Column(
            "promotions_opt_out", sa.Boolean(), nullable=False, server_default=sa.text("false")
        ),
    )


def downgrade() -> None:
    op.drop_column("profiles", "promotions_opt_out")
    for table in reversed(_TABLES):
        op.drop_table(table)

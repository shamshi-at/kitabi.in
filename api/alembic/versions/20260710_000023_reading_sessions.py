"""Add reading_sessions (Layer 2, SyncableMixin) — a timed start-to-stop
reading session against a library entry. Feature pulled forward from
feature-map.md's [LATER] parking lot to [V1] (10 Jul 2026, owner request).
RLS enabled with zero policies (rule 11).

Revision ID: 000023
Revises: 000022
Create Date: 2026-07-10

"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "000023"
down_revision: str | None = "000022"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _syncable_columns() -> list[sa.Column]:
    return [
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "server_seq",
            sa.BigInteger(),
            server_default=sa.text("nextval('sync_seq')"),
            nullable=False,
            unique=True,
        ),
    ]


def upgrade() -> None:
    op.create_table(
        "reading_sessions",
        *_syncable_columns(),
        sa.Column(
            "library_entry_id", sa.Uuid(), sa.ForeignKey("library_entries.id"), nullable=False
        ),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("duration_seconds", sa.Integer(), nullable=False),
        sa.Column("page_start", sa.Integer(), nullable=True),
        sa.Column("page_end", sa.Integer(), nullable=True),
        sa.CheckConstraint("duration_seconds >= 0", name="ck_reading_sessions_duration_nonneg"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_reading_sessions_user_seq", "reading_sessions", ["user_id", "server_seq"])
    op.create_index(
        "ix_reading_sessions_library_entry_id", "reading_sessions", ["library_entry_id"]
    )
    op.execute("ALTER TABLE reading_sessions ENABLE ROW LEVEL SECURITY")


def downgrade() -> None:
    op.drop_table("reading_sessions")

"""Peer-to-peer lending connections (consent layer).

A directed request between two users: requester → addressee, status
pending/accepted/denied. Cross-user, online-only (not synced). RLS enabled,
deny-by-default (CLAUDE.md rule 11) — only FastAPI touches it.

Revision ID: 000012
Revises: 000011
Create Date: 2026-07-06

"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "000012"
down_revision: str | None = "000011"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "connections",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("requester_id", sa.Uuid(), nullable=False),
        sa.Column("addressee_id", sa.Uuid(), nullable=False),
        sa.Column("status", sa.String(), nullable=False, server_default="pending"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("requester_id", "addressee_id", name="uq_connections_pair"),
    )
    op.create_index("ix_connections_requester_id", "connections", ["requester_id"])
    op.create_index("ix_connections_addressee_id", "connections", ["addressee_id"])
    # RLS deny-by-default: no policies — only FastAPI (service role) reads/writes.
    op.execute("ALTER TABLE connections ENABLE ROW LEVEL SECURITY")


def downgrade() -> None:
    op.drop_index("ix_connections_addressee_id", table_name="connections")
    op.drop_index("ix_connections_requester_id", table_name="connections")
    op.drop_table("connections")

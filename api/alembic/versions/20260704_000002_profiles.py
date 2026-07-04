"""Add profiles table.

One row per Supabase auth user — id is auth.users.id directly, not a
generated UUID (app/models/profile.py). Visibility columns are the dormant
community switchboard (feature-map.md rule 4), all default false. RLS
enabled with zero policies (CLAUDE.md rule 11) — only the API, via the
service role / direct Postgres connection, touches this table.

Revision ID: 000002
Revises: 000001
Create Date: 2026-07-04

"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "000002"
down_revision: str | None = "000001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "profiles",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("email", sa.String(), nullable=False),
        sa.Column("full_name", sa.String(), nullable=True),
        sa.Column("avatar_url", sa.String(), nullable=True),
        sa.Column("profile_visible", sa.Boolean(), server_default=sa.false(), nullable=False),
        sa.Column("library_visible", sa.Boolean(), server_default=sa.false(), nullable=False),
        sa.Column(
            "reviews_visible_default", sa.Boolean(), server_default=sa.false(), nullable=False
        ),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.execute("ALTER TABLE profiles ENABLE ROW LEVEL SECURITY")


def downgrade() -> None:
    op.drop_table("profiles")

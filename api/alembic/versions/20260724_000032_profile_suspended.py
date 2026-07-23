"""profiles.suspended_at — the admin console's reader-moderation lever.

A suspended reader keeps their data (soft, reversible) but is locked out of the
API: the auth dependency rejects them with 403 until an admin unsuspends. Null
= active, the overwhelming majority, so the column is cheap.

Revision ID: 000032
Revises: 000031
Create Date: 2026-07-24
"""

import sqlalchemy as sa

from alembic import op

revision: str = "000032"
down_revision: str | None = "000031"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("profiles", sa.Column("suspended_at", sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    op.drop_column("profiles", "suspended_at")

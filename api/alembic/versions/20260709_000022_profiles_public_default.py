"""Profiles are public by default (owner decision, 9 Jul 2026).

Flips the profile_visible server default to true and backfills existing
rows — a reader is findable/viewable unless they opt out in the profile
screen. Library and review visibility stay opt-in (default false).

Revision ID: 000022
Revises: 000021
Create Date: 2026-07-09
"""

import sqlalchemy as sa

from alembic import op

revision: str = "000022"
down_revision: str | None = "000021"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.alter_column("profiles", "profile_visible", server_default=sa.true())
    op.execute("UPDATE profiles SET profile_visible = true")


def downgrade() -> None:
    op.alter_column("profiles", "profile_visible", server_default=sa.false())

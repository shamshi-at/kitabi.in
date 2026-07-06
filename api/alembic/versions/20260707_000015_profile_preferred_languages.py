"""Reader's preferred languages on the profile.

A JSONB list of language names (e.g. ["Malayalam", "English"]) captured at
onboarding, editable in profile. Nullable, no backfill.

Revision ID: 000015
Revises: 000014
Create Date: 2026-07-07

"""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "000015"
down_revision: str | None = "000014"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "profiles",
        sa.Column("preferred_languages", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("profiles", "preferred_languages")

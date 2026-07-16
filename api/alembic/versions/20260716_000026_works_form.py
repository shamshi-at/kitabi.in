"""works.form — the literary form (Type) as its own axis (owner decision,
16 Jul 2026).

Novel / Short stories / Poetry / Memoir… is a *form*, not a genre: one per
work, closed vocabulary (schemas.catalog.WORK_FORMS), and the primary way
Malayalam publishing (and so Kitabi's library filter) organizes books.
Nullable — existing works stay unset and backfill organically through the
"Improve this entry" flow; no data backfill here.

Revision ID: 000026
Revises: 000025
Create Date: 2026-07-16
"""

import sqlalchemy as sa

from alembic import op

revision: str = "000026"
down_revision: str | None = "000025"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("works", sa.Column("form", sa.String(), nullable=True))


def downgrade() -> None:
    op.drop_column("works", "form")

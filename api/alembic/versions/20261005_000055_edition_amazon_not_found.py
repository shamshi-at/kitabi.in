"""Editions: a mark for "searched Amazon, there is no listing".

The console's Buy links worklist is "editions with no curated Amazon link", and
for some books that never ends — the book is not on Amazon, so there is no
link to find. Without a mark those rows come back every time the list is
opened and bury the ones that can be finished. `amazon_not_found_at` is the
operator's "looked, nothing there": the row leaves the worklist and is listed
under its own filter, where it can be put back.

One nullable column, no default, no backfill — a metadata-only change in
Postgres, and the previous version of the code (which is what serves traffic
while this migrates on boot) never reads it.

Revision ID: 000055
Revises: 000054
Create Date: 2026-10-05
"""

import sqlalchemy as sa

from alembic import op

revision: str = "000055"
down_revision: str | None = "000054"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "editions", sa.Column("amazon_not_found_at", sa.DateTime(timezone=True), nullable=True)
    )


def downgrade() -> None:
    op.drop_column("editions", "amazon_not_found_at")

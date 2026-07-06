"""Edition buy_links ([WIRED] list of retailer links).

Replaces the single `buy_url` (000008, never populated) with `buy_links` — a
JSONB list of {retailer, url} entries, since a book page lists every store it's
available at (Amazon, Flipkart, …) rather than one link.

Revision ID: 000009
Revises: 000008
Create Date: 2026-07-06

"""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "000009"
down_revision: str | None = "000008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_column("editions", "buy_url")
    op.add_column("editions", sa.Column("buy_links", postgresql.JSONB(), nullable=True))


def downgrade() -> None:
    op.drop_column("editions", "buy_links")
    op.add_column("editions", sa.Column("buy_url", sa.String(), nullable=True))

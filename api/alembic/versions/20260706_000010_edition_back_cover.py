"""Edition back_cover_url — users can photograph both sides of a book.

Front (`cover_url`) is what lists/grids render; `back_cover_url` shows only on
the book page. Nullable, no backfill.

Revision ID: 000010
Revises: 000009
Create Date: 2026-07-06

"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "000010"
down_revision: str | None = "000009"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("editions", sa.Column("back_cover_url", sa.String(), nullable=True))


def downgrade() -> None:
    op.drop_column("editions", "back_cover_url")

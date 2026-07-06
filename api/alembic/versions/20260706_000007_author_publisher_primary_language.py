"""Author + publisher primary_language.

Adds `primary_language` to authors and publishers so the add-book author/
publisher pickers can show (and let users set) the language an author writes in
or a house mainly publishes in — the at-a-glance detail that tells two
same-named entries apart.

Revision ID: 000007
Revises: 000006
Create Date: 2026-07-06

"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "000007"
down_revision: str | None = "000006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("authors", sa.Column("primary_language", sa.String(), nullable=True))
    op.add_column("publishers", sa.Column("primary_language", sa.String(), nullable=True))


def downgrade() -> None:
    op.drop_column("publishers", "primary_language")
    op.drop_column("authors", "primary_language")

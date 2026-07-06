"""Username handle + catalog contributor tracking.

- profiles.username: optional unique public handle (find-a-reader-to-lend-to).
- works/authors.created_by_user_id: who contributed the catalog row, for scoring.

All nullable, no backfill.

Revision ID: 000011
Revises: 000010
Create Date: 2026-07-06

"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "000011"
down_revision: str | None = "000010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("profiles", sa.Column("username", sa.String(), nullable=True))
    op.create_unique_constraint("uq_profiles_username", "profiles", ["username"])

    op.add_column("works", sa.Column("created_by_user_id", sa.Uuid(), nullable=True))
    op.create_index("ix_works_created_by_user_id", "works", ["created_by_user_id"])

    op.add_column("authors", sa.Column("created_by_user_id", sa.Uuid(), nullable=True))
    op.create_index("ix_authors_created_by_user_id", "authors", ["created_by_user_id"])


def downgrade() -> None:
    op.drop_index("ix_authors_created_by_user_id", table_name="authors")
    op.drop_column("authors", "created_by_user_id")
    op.drop_index("ix_works_created_by_user_id", table_name="works")
    op.drop_column("works", "created_by_user_id")
    op.drop_constraint("uq_profiles_username", "profiles", type_="unique")
    op.drop_column("profiles", "username")

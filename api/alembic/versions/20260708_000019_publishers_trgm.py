"""Trigram index on publishers.name — the global search went fuzzy.

000018 indexed works.title and authors.name for the duplicate check; the
typo-tolerant global search (S4) also matches publishers, so give it the same
GIN gin_trgm_ops index (serves `%`, `<%`, and `ILIKE '%q%'`).

Revision ID: 000019
Revises: 000018
Create Date: 2026-07-08
"""

from alembic import op

revision: str = "000019"
down_revision: str | None = "000018"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_publishers_name_trgm "
        "ON publishers USING gin (name gin_trgm_ops)"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_publishers_name_trgm")

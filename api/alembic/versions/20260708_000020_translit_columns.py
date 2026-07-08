"""Cross-script search columns — "Kayary" finds "കയർ".

Adds the romanized twins of the searchable catalog text columns
(works.title_translit, authors.name_translit, publishers.name_translit),
backfills them through app.services.translit (the same function the ORM
hooks and the query side use — the three must always agree), and gives each
a GIN gin_trgm_ops index so the fuzzy operators stay index-served.

Revision ID: 000020
Revises: 000019
Create Date: 2026-07-08
"""

import sqlalchemy as sa

from alembic import op
from app.services.translit import transliterate

revision: str = "000020"
down_revision: str | None = "000019"
branch_labels = None
depends_on = None

_TABLES = (
    ("works", "title", "title_translit"),
    ("authors", "name", "name_translit"),
    ("publishers", "name", "name_translit"),
)


def upgrade() -> None:
    conn = op.get_bind()
    for table, source, target in _TABLES:
        op.add_column(table, sa.Column(target, sa.String(), nullable=True))
        # Backfill in Python — transliteration is app logic, not SQL. Catalog
        # tables are small (thousands, not millions); one pass is fine.
        rows = conn.execute(sa.text(f"SELECT id, {source} FROM {table}")).all()
        for row_id, text_value in rows:
            conn.execute(
                sa.text(f"UPDATE {table} SET {target} = :v WHERE id = :id"),
                {"v": transliterate(text_value), "id": row_id},
            )
        op.execute(
            f"CREATE INDEX IF NOT EXISTS ix_{table}_{target}_trgm "
            f"ON {table} USING gin ({target} gin_trgm_ops)"
        )


def downgrade() -> None:
    for table, _, target in _TABLES:
        op.execute(f"DROP INDEX IF EXISTS ix_{table}_{target}_trgm")
        op.drop_column(table, target)

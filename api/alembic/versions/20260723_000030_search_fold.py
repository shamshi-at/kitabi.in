"""Spelling-insensitive search columns — "chemmin" and "chemmeen" find the same book.

`*_translit` holds one romanization, but readers type many: long vowels doubled
or not, aspirates with or without the h, Tamil ச as ch or s, consonants doubled
or single. No single stored spelling equals all of them, so this adds the fold
(app.services.translit.fold) — the skeleton those variants collapse to — for
works.title, authors.name and publishers.name, backfills it through the same
function the ORM hooks and the query side use, and GIN-trigram-indexes each so
the fuzzy operators stay index-served.

Revision ID: 000030
Revises: 000029
Create Date: 2026-07-23
"""

import sqlalchemy as sa

from alembic import op
from app.services.translit import fold

revision: str = "000030"
down_revision: str | None = "000029"
branch_labels = None
depends_on = None

_TABLES = (
    ("works", "title", "title_fold"),
    ("authors", "name", "name_fold"),
    ("publishers", "name", "name_fold"),
)


def upgrade() -> None:
    conn = op.get_bind()
    for table, source, target in _TABLES:
        op.add_column(table, sa.Column(target, sa.String(), nullable=True))
        # Backfill in Python — folding is app logic, not SQL. Catalog tables are
        # small (thousands, not millions); one pass is fine. Same shape as 000020.
        rows = conn.execute(sa.text(f"SELECT id, {source} FROM {table}")).all()
        for row_id, text_value in rows:
            conn.execute(
                sa.text(f"UPDATE {table} SET {target} = :v WHERE id = :id"),
                {"v": fold(text_value), "id": row_id},
            )
        op.execute(
            f"CREATE INDEX IF NOT EXISTS ix_{table}_{target}_trgm "
            f"ON {table} USING gin ({target} gin_trgm_ops)"
        )


def downgrade() -> None:
    for table, _, target in _TABLES:
        op.execute(f"DROP INDEX IF EXISTS ix_{table}_{target}_trgm")
        op.drop_column(table, target)

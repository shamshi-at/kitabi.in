"""merged_into_id on authors and publishers — duplicate merging.

The catalogue holds ~100 redundant rows: "Perkins, John" beside "John Perkins",
"Patañjali." beside "Patanjali.", three separate Vaikom Muhammad Basheers. They
split one person's books across several pages, make search look broken, and are
why author pages can't safely be indexed.

**Why a pointer rather than a delete.** The loser is soft-deleted AND points at
the survivor, so:

  * its URL still resolves — /author/vokom-m-basheer 301s to the survivor
    instead of 404ing. Author pages may already be indexed, and a merge that
    breaks old URLs throws away the ranking it was meant to consolidate.
  * the merge is reversible by clearing one column. No audit table, no
    reconstruction — unset the pointer and the row is back.

Self-referential FK, nullable, indexed for the redirect lookup.

Revision ID: 000039
Revises: 000038
Create Date: 2026-08-04
"""

import sqlalchemy as sa

from alembic import op

revision: str = "000039"
down_revision: str | None = "000038"
branch_labels = None
depends_on = None

_TABLES = ("authors", "publishers")


def upgrade() -> None:
    for table in _TABLES:
        op.add_column(
            table,
            sa.Column("merged_into_id", sa.Uuid(), sa.ForeignKey(f"{table}.id"), nullable=True),
        )
        op.create_index(f"ix_{table}_merged_into", table, ["merged_into_id"])


def downgrade() -> None:
    for table in _TABLES:
        op.drop_index(f"ix_{table}_merged_into", table_name=table)
        op.drop_column(table, "merged_into_id")

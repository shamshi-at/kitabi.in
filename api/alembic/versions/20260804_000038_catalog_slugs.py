"""slug on works / authors / publishers / series — the public URL segment.

/book/chemmeen instead of /book/47e95a54-829f-5f0c-bdea-f4f3be8c6bbe. A UUID in
a URL looks like spam in a search result, carries no keyword relevance and can't
be said out loud, and being found is the entire point of the public web platform
(docs/web-platform-plan.md §4.1).

Nullable + UNIQUE. Postgres allows unlimited NULLs under a unique index, which
is exactly the semantics wanted: a slug is optional (a row whose title romanizes
to nothing stays reachable by UUID) but no two rows may share one.

**No backfill here.** Filling these needs `services/translit.transliterate` to
romanize Malayalam/Tamil titles, and importing application code into a migration
welds the migration to a moving target — the classic way a migration that ran
fine in July fails to replay in December. `slug_service.backfill_missing` owns
it instead: idempotent, bounded, and scheduled, so it also self-heals rows
created later by paths that never call `ensure_slug` (ETL bulk loads).

Revision ID: 000038
Revises: 000037
Create Date: 2026-08-04
"""

import sqlalchemy as sa

from alembic import op

revision: str = "000038"
down_revision: str | None = "000037"
branch_labels = None
depends_on = None

_TABLES = ("works", "authors", "publishers", "series")


def upgrade() -> None:
    for table in _TABLES:
        op.add_column(table, sa.Column("slug", sa.String(), nullable=True))
        # Unique AND the lookup index in one: every public page resolves by slug,
        # so this is the hottest index on the read path.
        op.create_index(f"ix_{table}_slug", table, ["slug"], unique=True)


def downgrade() -> None:
    for table in _TABLES:
        op.drop_index(f"ix_{table}_slug", table_name=table)
        op.drop_column(table, "slug")

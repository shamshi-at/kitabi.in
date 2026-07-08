"""pg_trgm + trigram indexes — typo-tolerant duplicate detection.

The add-book form checks "is this already in the catalog?" as the user types,
so the match must survive typos ("Chemeen" → "Chemmeen"). pg_trgm's trigram
similarity is the pure-Postgres answer (CLAUDE.md rule 8: no new service) and
works on any script, Malayalam included — trigrams are just character windows.

GIN `gin_trgm_ops` indexes accelerate all three operators the similar-works
query uses: `%` (similarity), `<%` (word_similarity), and `ILIKE '%q%'`.

Supabase note: if the project already has pg_trgm enabled (in its
`extensions` schema), IF NOT EXISTS makes this a no-op and the functions still
resolve — Supabase puts `extensions` on the database search_path.

Revision ID: 000018
Revises: 000017
Create Date: 2026-07-08
"""

from alembic import op

revision: str = "000018"
down_revision: str | None = "000017"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_works_title_trgm ON works USING gin (title gin_trgm_ops)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_authors_name_trgm ON authors USING gin (name gin_trgm_ops)"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_authors_name_trgm")
    op.execute("DROP INDEX IF EXISTS ix_works_title_trgm")
    # The extension stays — cheap, harmless, and something else may use it.

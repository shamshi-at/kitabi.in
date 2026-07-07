"""Enable RLS on alembic_version — the one table not created by our migrations.

Alembic creates its own bookkeeping table (the current revision id, one row)
outside any migration, so it never got the RLS-with-zero-policies treatment
every app table gets (CLAUDE.md rule 11) and Supabase's Security Advisor
flags it. The API's role owns the table, and owners bypass RLS, so `alembic
upgrade` keeps working; PostgREST/anon access is what gets shut off.

Revision ID: 000017
Revises: 000016
Create Date: 2026-07-08
"""

from alembic import op

revision: str = "000017"
down_revision: str | None = "000016"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE alembic_version ENABLE ROW LEVEL SECURITY")


def downgrade() -> None:
    op.execute("ALTER TABLE alembic_version DISABLE ROW LEVEL SECURITY")

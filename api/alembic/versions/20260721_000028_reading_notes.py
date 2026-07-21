"""Add reading_notes (Layer 2, SyncableMixin) — private per-book notes, each
optionally tied to the reading session it was written during and to the page
or page range it is about (owner request, 21 Jul 2026; mockups N1-N5).

Replaces nothing: `library_entries.notes` (the single free-text blob) stays put
so no reader loses what they already wrote. The app reads both and shows the
old blob as one undated note until it's migrated by hand — a lossy automatic
split of someone's prose is not worth the tidiness.

`session_id` is ON DELETE SET NULL on purpose: deleting a sitting must never
delete the thoughts you had during it.

RLS enabled with zero policies (rule 11).

Revision ID: 000028
Revises: 000027
Create Date: 2026-07-21

"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "000028"
down_revision: str | None = "000027"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _syncable_columns() -> list[sa.Column]:
    return [
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "server_seq",
            sa.BigInteger(),
            server_default=sa.text("nextval('sync_seq')"),
            nullable=False,
            unique=True,
        ),
    ]


def upgrade() -> None:
    op.create_table(
        "reading_notes",
        *_syncable_columns(),
        sa.Column(
            "library_entry_id", sa.Uuid(), sa.ForeignKey("library_entries.id"), nullable=False
        ),
        sa.Column(
            "session_id",
            sa.Uuid(),
            sa.ForeignKey("reading_sessions.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("body", sa.String(), nullable=False),
        sa.Column("page_start", sa.Integer(), nullable=True),
        sa.Column("page_end", sa.Integer(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_reading_notes_user_seq", "reading_notes", ["user_id", "server_seq"])
    op.create_index(
        "ix_reading_notes_library_entry_id", "reading_notes", ["library_entry_id"]
    )
    op.create_index("ix_reading_notes_session_id", "reading_notes", ["session_id"])
    op.execute("ALTER TABLE reading_notes ENABLE ROW LEVEL SECURITY")


def downgrade() -> None:
    op.drop_index("ix_reading_notes_session_id", table_name="reading_notes")
    op.drop_index("ix_reading_notes_library_entry_id", table_name="reading_notes")
    op.drop_index("ix_reading_notes_user_seq", table_name="reading_notes")
    op.drop_table("reading_notes")

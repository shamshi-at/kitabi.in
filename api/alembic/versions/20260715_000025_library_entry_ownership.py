"""library_entries.ownership — unify borrowed books into the library (owner
request, 15 Jul 2026).

A borrowed book gets a real `library_entries` row (`ownership='borrowed'`)
instead of existing only as a `lending_records` row invisible to reading
status/progress — so it can be marked reading/read, tracked, and stays on
the shelf after it's returned (return status is derived from the linked
`LendingRecord.returned_date`, never stored here). Backfills every existing
`lending_records` row with `direction='borrowed'` and no `library_entry_id`
into a fresh borrowed `library_entries` row, then links it back — so loans
logged before this migration show up too, not just new ones.

Revision ID: 000025
Revises: 000024
Create Date: 2026-07-15
"""

import uuid

import sqlalchemy as sa

from alembic import op

revision: str = "000025"
down_revision: str | None = "000024"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "library_entries",
        sa.Column("ownership", sa.String(), nullable=False, server_default="owned"),
    )

    # Backfill: every pre-existing borrowed loan that has no library_entry_id
    # yet gets one, so it starts showing up on the shelf like new borrows do.
    bind = op.get_bind()
    borrowed = bind.execute(
        sa.text(
            "SELECT id, user_id, edition_id, created_at FROM lending_records "
            "WHERE direction = 'borrowed' AND library_entry_id IS NULL "
            "AND edition_id IS NOT NULL AND deleted_at IS NULL"
        )
    ).fetchall()
    for row in borrowed:
        entry_id = uuid.uuid4()
        bind.execute(
            sa.text(
                "INSERT INTO library_entries "
                "(id, user_id, edition_id, status, ownership, created_at, updated_at, server_seq) "
                "VALUES (:id, :user_id, :edition_id, 'pending', 'borrowed', :created_at, now(), "
                "nextval('sync_seq'))"
            ),
            {
                "id": entry_id,
                "user_id": row.user_id,
                "edition_id": row.edition_id,
                "created_at": row.created_at,
            },
        )
        bind.execute(
            sa.text("UPDATE lending_records SET library_entry_id = :entry_id WHERE id = :lr_id"),
            {"entry_id": entry_id, "lr_id": row.id},
        )


def downgrade() -> None:
    op.drop_column("library_entries", "ownership")

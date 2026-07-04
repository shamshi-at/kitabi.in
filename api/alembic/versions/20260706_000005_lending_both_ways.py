"""Lending runs both ways: direction, borrowed-side edition_id, note, linked_loan_id.

A borrowed record doesn't own the book, so `library_entry_id` becomes nullable
and `edition_id` (catalog edition) carries the book instead. `direction`
distinguishes lent vs borrowed; `linked_loan_id` correlates the mirrored rows
when both sides are Kitabi users (dormant [WIRED]); `note` is free text.

Revision ID: 000005
Revises: 000004
Create Date: 2026-07-06

"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "000005"
down_revision: str | None = "000004"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "lending_records",
        sa.Column("direction", sa.String(), nullable=False, server_default="lent"),
    )
    op.add_column("lending_records", sa.Column("edition_id", sa.Uuid(), nullable=True))
    op.add_column("lending_records", sa.Column("linked_loan_id", sa.Uuid(), nullable=True))
    op.add_column("lending_records", sa.Column("note", sa.String(), nullable=True))
    op.create_foreign_key(
        "fk_lending_records_edition_id_editions",
        "lending_records",
        "editions",
        ["edition_id"],
        ["id"],
    )
    # Borrowed records have no owned library entry.
    op.alter_column("lending_records", "library_entry_id", existing_type=sa.Uuid(), nullable=True)


def downgrade() -> None:
    op.alter_column("lending_records", "library_entry_id", existing_type=sa.Uuid(), nullable=False)
    op.drop_constraint(
        "fk_lending_records_edition_id_editions", "lending_records", type_="foreignkey"
    )
    op.drop_column("lending_records", "note")
    op.drop_column("lending_records", "linked_loan_id")
    op.drop_column("lending_records", "edition_id")
    op.drop_column("lending_records", "direction")

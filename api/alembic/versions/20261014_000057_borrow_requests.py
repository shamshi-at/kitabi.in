"""borrow_requests — an ask to borrow is a record, not just a push

"Ask to borrow" shipped as a notification with nothing behind it: the owner
tapped it, landed nowhere that mentioned it, and couldn't find it in the app
afterwards (owner report, 14 Oct 2026). One row per ask, open until the owner
lends that book to the asker (closed by the lending mirror) or declines.

New table only — nothing existing changes shape, safe against the previous
image while the new one rolls (the container migrates on boot). RLS enabled,
zero policies (rule 11).

Revision ID: 000057
Revises: 000056
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "000057"
down_revision: str | None = "000056"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "borrow_requests",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("requester_id", sa.Uuid(), nullable=False),
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("edition_id", sa.Uuid(), sa.ForeignKey("editions.id"), nullable=False),
        sa.Column("status", sa.String(), nullable=False, server_default="open"),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        "ix_borrow_requests_owner_status", "borrow_requests", ["owner_id", "status"]
    )
    op.create_index(
        "ix_borrow_requests_requester_status", "borrow_requests", ["requester_id", "status"]
    )
    op.execute("ALTER TABLE borrow_requests ENABLE ROW LEVEL SECURITY")


def downgrade() -> None:
    op.drop_table("borrow_requests")

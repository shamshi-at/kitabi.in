"""active_reading_sessions — the sitting running right now, per account.

Owner request (14 Aug 2026): with the same account on two devices, a timer
started on one should be visible and stoppable on the other. The running timer
was device-local (Drift `key_values`, no server counterpart), so the second
device learned about a sitting only after it ended and synced.

One row per user, server-owned, online-only — *not* a syncable Layer-2 table.
A live sitting cannot be offline-first: two devices cannot both own it, and a
last-write-wins merge of "stopped" against "still running" would lose a real
sitting. See the model docstring.

RLS enabled with zero policies like every other table (CLAUDE.md rule 11).

Revision ID: 000045
Revises: 000044
Create Date: 2026-08-14
"""

import sqlalchemy as sa

from alembic import op

revision: str = "000045"
down_revision: str | None = "000044"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "active_reading_sessions",
        # One live sitting per account — starting anywhere replaces whatever
        # was running, which is the rule the app already applies on one device.
        sa.Column("user_id", sa.Uuid(), primary_key=True),
        # Client-minted at start; the finished reading_sessions row reuses it,
        # so whichever device stops the sitting writes the same row rather than
        # a second one.
        sa.Column("session_id", sa.Uuid(), nullable=False),
        sa.Column("library_entry_id", sa.Uuid(), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("page_start", sa.Integer(), nullable=True),
        sa.Column("confirmed_at", sa.DateTime(timezone=True), nullable=True),
        # The install that started it, echoed in the push so the originator can
        # ignore its own event.
        sa.Column("device_id", sa.String(), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
    )
    op.execute("ALTER TABLE active_reading_sessions ENABLE ROW LEVEL SECURITY")


def downgrade() -> None:
    op.drop_table("active_reading_sessions")

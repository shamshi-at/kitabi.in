"""reading_sessions.auto_stopped — was this sitting closed by the "still
reading?" safety net rather than the reader tapping Stop.

Owner report (23 Aug 2026): a session ran ~2 hours; the 60-minute check-in
notification was missed, and the 90-minute enforcement task silently closed
it. The reader only found out when they tried to stop reading themselves —
by then the logged end time and page were both wrong, with no way to fix
either. This column lets the client flag such a sitting so the reading log
can show it was auto-stopped and offer a correction.

Revision ID: 000047
Revises: 000046
Create Date: 2026-08-23
"""

import sqlalchemy as sa

from alembic import op

revision: str = "000047"
down_revision: str | None = "000046"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "reading_sessions",
        sa.Column("auto_stopped", sa.Boolean(), nullable=False, server_default=sa.false()),
    )


def downgrade() -> None:
    op.drop_column("reading_sessions", "auto_stopped")
